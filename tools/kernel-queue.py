#!/usr/bin/env python3
"""Import/export the evaluated device patch queue in a shared kernel Git repository."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile


# Nixpkgs kernel postPatch salt verified for the rc5 and rc6 preparation contracts.
RANDSTRUCT_SALT = "/1s3bzfisrvrdlla1qr3z074sphpb4cpz4rbacwp56cmp9237lv2y"


def run(*args, cwd=None, data=None):
    return subprocess.check_output(args, cwd=cwd, input=data).decode().strip()


def git(repo, *args, data=None):
    return run('git', '-C', str(repo), *args, data=data)


def queue(flake, device, system):
    patches = json.loads(run('nix', 'eval', '--json',
        f'{flake}#legacyPackages.{system}.devices.{device}.kernel.patches'))
    # Nixpkgs appends its build-only randstruct patch after the device queue.
    return [Path(p) for p in patches if '/pkgs/linux-kernel/' in p]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['import', 'export', 'verify', 'prepare'])
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--device', required=True, choices=['aurora', 'polaris', 'sheng', 'asphalt', 'clover'])
    parser.add_argument('--version', required=True, help='e.g. 7.3-rc5')
    parser.add_argument('--base', required=True, help='verified upstream tag, e.g. v7.3-rc5')
    parser.add_argument('--flake', default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument('--system', default='aarch64-linux')
    parser.add_argument('--source-identity', help='exact rc source store path used by Nix randstruct seed')
    parser.add_argument('--output', type=Path, help='new directory for exported mail patches')
    args = parser.parse_args()
    repo = args.repo.resolve()
    branch = f'android/{args.version}/{args.device}'
    base = git(repo, 'rev-parse', f'{args.base}^{{commit}}')
    makefile = git(repo, 'show', f'{base}:Makefile')
    fields = dict(re.findall(r'^(VERSION|PATCHLEVEL|SUBLEVEL|EXTRAVERSION) = (.*)$', makefile, re.MULTILINE))
    version = fields['VERSION'] + '.' + fields['PATCHLEVEL'] + fields['EXTRAVERSION']
    if fields['SUBLEVEL'] != '0' or version != args.version:
        parser.error(f'base release {version} does not match --version {args.version}')
    if args.action in ['import', 'verify', 'prepare']:
        status = json.loads(run('nix', 'eval', '--json',
            f'{args.flake}#legacyPackages.{args.system}.devices.{args.device}.kernel.patchQueueStatus'))
        if status['expectedVersion'] != args.version:
            parser.error(f'evaluated queue targets {status["expectedVersion"]}, not {args.version}')
    if args.action == 'prepare':
        if args.version not in ['7.3-rc5', '7.3-rc6']:
            parser.error('prepare implements only the verified 7.3-rc5 and 7.3-rc6 Nix postPatch contracts')
        if not args.source_identity:
            parser.error('prepare requires --source-identity for the selected release')
        if args.version == '7.3-rc6':
            contract = json.loads(run('nix', 'eval', '--json',
                f'{args.flake}#legacyPackages.{args.system}.devices.{args.device}.kernel',
                '--apply', 'k: { src = toString k.src; inherit (k) postPatch; }'))
            if args.source_identity != contract['src']:
                parser.error('--source-identity differs from the selected rc6 Nix source')
            if f"echo {args.source_identity} {RANDSTRUCT_SALT} | sha256sum" not in contract['postPatch']:
                parser.error('selected Nix randstruct preparation contract changed; review postPatch')
        if git(repo, 'status', '--porcelain'):
            parser.error('kernel worktree must be clean')
        prepared = f'android-prepared/{args.version}/{args.device}'
        subprocess.run([sys.executable, __file__, 'verify', '--repo', str(repo),
                        '--device', args.device, '--version', args.version, '--base', args.base,
                        '--flake', args.flake, '--system', args.system], check=True)
        git(repo, 'switch', '-c', prepared, branch)
        all_patches = json.loads(run('nix', 'eval', '--json',
            f'{args.flake}#legacyPackages.{args.system}.devices.{args.device}.kernel.patches'))
        build_patches = [Path(p) for p in all_patches if '/pkgs/linux-kernel/' not in p]
        for patch in build_patches:
            subprocess.run(['patch', '-p1', '--batch', '--forward', '--no-backup-if-mismatch',
                            '-i', str(patch)], cwd=repo, check=True)
            git(repo, 'add', '-A')
            git(repo, 'commit', '--quiet', '-m',
                f'build: apply Nixpkgs {patch.name}\n\nBuild-only patch; exclude from device queue export.\nImport-SHA256: {hashlib.sha256(patch.read_bytes()).hexdigest()}')
        makefile = repo / 'Makefile'
        makefile.write_text(makefile.read_text().replace('= /sbin/depmod', '= depmod'))
        seed = hashlib.sha256((args.source_identity +
            ' ' + RANDSTRUCT_SALT + '\n').encode()).hexdigest()
        for name in ['scripts/gen-randstruct-seed.sh', 'scripts/gcc-plugins/gen-random-seed.sh']:
            path = repo / name
            if path.exists():
                path.write_text(path.read_text().replace('NIXOS_RANDSTRUCT_SEED', seed))
                break
        for directory, children, files in os.walk(repo):
            children[:] = [child for child in children if child != '.git']
            for name in files:
                if name in ['Makefile', 'Kbuild']:
                    path = Path(directory) / name
                    path.write_text(re.sub(r'[ \t]-Werror([ \t]|$)', ' ', path.read_text(), flags=re.MULTILINE))
        git(repo, 'add', '-A')
        git(repo, 'commit', '--quiet', '-m',
            f'build: prepare Nix kernel source\n\nUse depmod from PATH, deterministic randstruct seed and remove standalone -Werror.\nShebang rewriting remains a Nix build-environment operation.\nRandstruct-Seed: {seed}\nSource-Identity: {args.source_identity}\nDevice-Queue: {branch}')
        preparation = {'branch': prepared, 'commit': git(repo, 'rev-parse', 'HEAD'),
                       'tree': git(repo, 'rev-parse', 'HEAD^{tree}'), 'seed': seed,
                       'sourceIdentity': args.source_identity,
                       'shebangs': 'left to formal Nix environment'}
        metadata = Path(git(repo, 'rev-parse', '--absolute-git-dir')) / 'android-queues'
        metadata.mkdir(exist_ok=True)
        manifest_path = metadata / f'{args.version}-{args.device}.json'
        manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
        manifest['prepared'] = preparation
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
        print(json.dumps(preparation))
        return
    if args.action == 'verify':
        git(repo, 'merge-base', '--is-ancestor', base, branch)
        patches = queue(args.flake, args.device, args.system)
        if int(git(repo, 'rev-list', '--count', f'{base}..{branch}')) != len(patches):
            parser.error('queue commit count differs from evaluated patch count')
        metadata = Path(git(repo, 'rev-parse', '--absolute-git-dir')) / 'android-queues'
        metadata.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=metadata) as temporary:
            temporary = Path(temporary)
            source = temporary / 'source'
            source.mkdir()
            archive = subprocess.Popen(['git', '-C', str(repo), 'archive', base], stdout=subprocess.PIPE)
            subprocess.run(['tar', '-xf', '-', '-C', str(source)], stdin=archive.stdout, check=True)
            archive.stdout.close()
            if archive.wait():
                raise RuntimeError('git archive failed')
            for patch in patches:
                subprocess.run(['patch', '-p1', '--batch', '--forward', '--no-backup-if-mismatch',
                                '-i', str(patch)], cwd=source, check=True)
            env = dict(os.environ, GIT_INDEX_FILE=str(temporary / 'index'), GIT_WORK_TREE=str(source))
            subprocess.run(['git', '-C', str(repo), 'read-tree', base], env=env, check=True)
            subprocess.run(['git', '-C', str(repo), 'add', '-A'], env=env, check=True)
            tree = subprocess.check_output(['git', '-C', str(repo), 'write-tree'], env=env).decode().strip()
            expected = git(repo, 'rev-parse', f'{branch}^{{tree}}')
            if tree != expected:
                raise RuntimeError(f'queue replay differs: {tree} != {expected}')
            print(json.dumps({'branch': branch, 'patches': len(patches), 'verifiedTree': tree}))
        return
    if args.action == 'export':
        if args.output is None:
            parser.error('export requires --output')
        if args.output.resolve().is_relative_to(repo):
            parser.error('--output must be outside the kernel worktree')
        if args.output.exists():
            parser.error('--output must not already exist')
        git(repo, 'merge-base', '--is-ancestor', base, branch)
        args.output.mkdir(parents=True)
        git(repo, 'format-patch', '--no-signature', '--output-directory',
            str(args.output.resolve()), f'{base}..{branch}')
        return
    if git(repo, 'status', '--porcelain'):
        parser.error('kernel worktree must be clean')
    if subprocess.run(['git', '-C', str(repo), 'show-ref', '--verify', '--quiet',
                       f'refs/heads/{branch}']).returncode == 0:
        parser.error(f'{branch} already exists; never overwrite an imported queue')
    patches = queue(args.flake, args.device, args.system)
    if not patches:
        parser.error('evaluated device queue is empty')
    git(repo, 'switch', '-c', branch, base)
    metadata = Path(git(repo, 'rev-parse', '--absolute-git-dir')) / 'android-queues'
    metadata.mkdir(exist_ok=True)
    manifest = {'branch': branch, 'base': base, 'tag': args.base, 'patches': []}
    with tempfile.TemporaryDirectory(dir=metadata) as temporary:
        temporary = Path(temporary)
        for patch in patches:
            content = patch.read_bytes()
            digest = hashlib.sha256(content).hexdigest()
            reused = None
            for previous in sorted(metadata.glob('*.json')):
                for entry in json.loads(previous.read_text()).get('patches', []):
                    if entry['sha256'] == digest and git(repo, 'rev-parse', entry['commit'] + '^') == git(repo, 'rev-parse', 'HEAD'):
                        reused = entry
                        break
                if reused:
                    break
            if reused:
                git(repo, 'merge', '--ff-only', reused['commit'])
                manifest['patches'].append(reused)
                continue
            message, diff = temporary / 'message', temporary / 'diff'
            info = run('git', 'mailinfo', '--encoding=UTF-8', str(message), str(diff), data=content)
            headers = dict(line.split(': ', 1) for line in info.splitlines() if ': ' in line)
            relative = 'pkgs/linux-kernel/' + str(patch).split('/pkgs/linux-kernel/', 1)[1]
            env = os.environ.copy()
            if headers.get('Author') and headers.get('Email'):
                env.update(GIT_AUTHOR_NAME=headers['Author'], GIT_AUTHOR_EMAIL=headers['Email'])
                if headers.get('Date'):
                    env['GIT_AUTHOR_DATE'] = headers['Date']
                body = headers.get('Subject', patch.stem) + '\n\n' + message.read_text()
                provenance = 'mail headers' if headers.get('Date') else 'mail author; import date (no original date supplied)'
            else:
                # Bare diffs do not identify their author. Attribute the import to
                # the operator and retain all supplied prose, without inventing authorship.
                body = (headers['Subject'] + '\n\n' + message.read_text()) if headers.get('Subject') else (
                    f'Import {patch.name}\n\nOriginal patch description:\n\n' +
                    content.decode().split('diff --git ', 1)[0].split('\n--- ', 1)[0])
                provenance = 'operator import; original patch has incomplete mail metadata'
            digest = hashlib.sha256(content).hexdigest()
            body = body.rstrip() + f'\n\nImport-Patch: {relative}\nImport-SHA256: {digest}\nImport-Provenance: {provenance}\n'
            # Match Nix patchPhase (GNU patch), including context/fuzz handling.
            subprocess.run(['patch', '-p1', '--batch', '--forward', '--no-backup-if-mismatch', '-i', str(patch)], cwd=repo, check=True)
            git(repo, 'add', '-A')
            subprocess.run(['git', '-C', str(repo), 'commit', '--quiet', '-F', '-'],
                           input=body.encode(), env=env, check=True)
            manifest['patches'].append({'path': relative, 'sha256': digest,
                'commit': git(repo, 'rev-parse', 'HEAD'), 'provenance': provenance})
    manifest['tree'] = git(repo, 'rev-parse', 'HEAD^{tree}')
    manifest['queueSource'] = str(patches[0]).split('/pkgs/linux-kernel/', 1)[0]
    (metadata / f'{args.version}-{args.device}.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'branch': branch, 'patches': len(patches), 'tree': manifest['tree']}))


if __name__ == '__main__':
    main()
