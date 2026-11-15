#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Host-only module contract tests. Native stub, never a device/reset backend."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import tarfile
import zipfile

module, archive = map(Path, sys.argv[1:])
manifest = json.loads((module / 'payload.json').read_text())
for name, digest in manifest['components'].items():
    assert hashlib.sha256((module / name).read_bytes()).hexdigest() == digest, name
with zipfile.ZipFile(archive) as z:
    assert not any(n.startswith('/') or '..' in Path(n).parts for n in z.namelist())
    assert not any(n.startswith('META-INF/') or n.endswith(('.img', '.apk')) for n in z.namelist())
    assert z.read('bin/boot-choice') == z.read('system/bin/boot-choice')
    for name in ['bin/boot-choice', 'system/bin/boot-choice', 'action.sh', 'uninstall.sh']:
        assert stat.S_IMODE(z.getinfo(name).external_attr >> 16) == 0o755
    assert stat.S_IMODE(z.getinfo('template/template.json').external_attr >> 16) == 0o444
    assert 'source.tar.gz' in z.namelist()
    assert all('webroot/'+f in z.namelist() for f in ['index.html','app.mjs','bridge.mjs','style.css'])
# Source delivery must be usable outside Nix: no symlink farm to store paths.
with tarfile.open(module / 'source.tar.gz') as t:
    members = {m.name: m for m in t.getmembers()}
    for m in members.values():
        assert not m.name.startswith('/') and '..' not in Path(m.name).parts
        if m.issym() or m.islnk():
            assert not m.linkname.startswith('/') and '/nix/store/' not in m.linkname, m.name
    assert members['source/cargo-vendor/sha2-0.10.9/src/lib.rs'].isfile()
    audit = json.loads((module / 'template/sources.json').read_text())
    for item in audit['sources']:
        assert item['root'] == 'public'
        data = t.extractfile('source/project/' + item['path']).read()
        assert hashlib.sha256(data).hexdigest() == item['sha256'], item['path']
assert (module / 'module.prop').read_text().startswith('id=android-devices-dodge-boot-choice\n')
assert not any((module / n).exists() for n in ['post-fs-data.sh', 'service.sh', 'boot-completed.sh'])
with tempfile.TemporaryDirectory(prefix='boot-choice-module-') as tmp:
    adb = Path(tmp) / 'android root/data/adb'
    update = adb / 'modules_update'
    update.mkdir(parents=True)
    adb.chmod(0o700)
    update.chmod(0o777)
    root = update / 'module path with spaces'
    shutil.copytree(module, root)
    native = root / 'bin/boot-choice'
    native.chmod(0o755)
    native.write_text('#!' + sys.executable + '\nimport json,os,sys,pathlib,hashlib,stat\nwith open(os.environ["NATIVE_LOG"],"a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\nif sys.argv[1] == "install":\n p=pathlib.Path(sys.argv[2]); source=pathlib.Path(os.environ["MODPATH"])/"template"\n assert p.parent == pathlib.Path(os.environ["FIXTURE_ADB"]) and p != source\n assert stat.S_IMODE(p.stat().st_mode)==0o700\n assert sorted(x.name for x in p.iterdir())==sorted(x.name for x in source.iterdir())\n for f in source.iterdir():\n  assert (p/f.name).read_bytes()==f.read_bytes()\n  assert stat.S_IMODE((p/f.name).stat().st_mode)==0o400\nsys.exit(int(os.environ.get("FAIL_NATIVE","0")))\n')
    log = Path(tmp) / 'calls'
    trap_log = Path(tmp) / 'installer-exit'
    env = {**os.environ, 'KSU': 'true', 'MODPATH': str(root), 'NATIVE_LOG': str(log), 'FIXTURE_ADB': str(adb), 'TRAP_LOG': str(trap_log)}
    shell = shutil.which('sh')
    install = r'''trap 'echo installer-exit >> "$TRAP_LOG"' 0
ui_print(){ printf "%s\n" "$*"; }
abort(){ printf "%s\n" "$*" >&2; exit 41; }
set_perm(){ chmod "$4" "$1"; }
set_perm_recursive(){
  if [ "$1" != "$MODPATH" ] && [ "${FAIL_STAGE_PERMS:-0}" = 1 ]; then return 1; fi
  find "$1" -type d -exec chmod "$4" '{}' +
  find "$1" -type f -exec chmod "$5" '{}' +
}
mktemp(){
  [ "$*" = '-d /data/adb/boot-choice-template.XXXXXX' ] || exit 98
  [ "${FAIL_MKTEMP:-0}" = 0 ] || return 1
  command mktemp -d "$FIXTURE_ADB/boot-choice-template.XXXXXX"
}
cp(){
  if [ "${FAIL_COPY:-0}" = 1 ]; then echo partial > "$BOOT_CHOICE_STAGE/partial"; return 1; fi
  command cp "$@"
}
rm(){ [ "${FAIL_CLEANUP:-0}" = 0 ] || return 1; command rm "$@"; }
. "$MODPATH/customize.sh"
'''
    def run(args, fail=0, extra=None):
        log.write_text('')
        trap_log.write_text('')
        r = subprocess.run(args, env={**env, 'FAIL_NATIVE': str(fail), **(extra or {})}, text=True, capture_output=True)
        calls = [json.loads(x) for x in log.read_text().splitlines()]
        assert stat.S_IMODE(update.stat().st_mode) == 0o777, 'shared KernelSU directory changed'
        return r, calls
    # One native install, using protected assets rather than the standard
    # world-writable staging parent. Installer EXIT trap is not replaced.
    r, calls = run([shell, '-c', install])
    assert r.returncode == 0 and len(calls) == 1 and calls[0][0] == 'install', (r, calls)
    assert Path(calls[0][1]).parent == adb and not Path(calls[0][1]).exists()
    assert trap_log.read_text() == 'installer-exit\n'
    r, calls = run([shell, '-c', install], 17)
    assert r.returncode == 41 and len(calls) == 1 and 'does not prove' in r.stderr
    assert not Path(calls[0][1]).exists() and trap_log.read_text() == 'installer-exit\n'
    for fault in ['FAIL_MKTEMP', 'FAIL_COPY', 'FAIL_STAGE_PERMS']:
        r, calls = run([shell, '-c', install], extra={fault: '1'})
        assert r.returncode == 41 and not calls and not list(adb.glob('boot-choice-template.*')), (fault,r,calls)
        assert trap_log.read_text() == 'installer-exit\n'
    r, calls = run([shell, '-c', install], extra={'FAIL_CLEANUP': '1'})
    assert r.returncode == 41 and len(calls) == 1 and 'VERIFIED' in r.stderr
    assert Path(calls[0][1]).is_dir()
    shutil.rmtree(calls[0][1])
    r, calls = run([shell, str(root / 'action.sh')])
    assert r.returncode == 0 and calls == [['status']]
    r, calls = run([shell, str(root / 'action.sh')], 19)
    assert r.returncode == 19 and calls == [['status']]
    r, calls = run([shell, str(root / 'uninstall.sh')])
    assert r.returncode == 0 and calls == [['restore']]
    r, calls = run([shell, str(root / 'uninstall.sh')], 23)
    assert r.returncode == 23 and calls == [['restore']] and 'may still delete' in r.stderr
    assert 'recover' in r.stderr
print('PASS: six native-stub lifecycle cases plus four staging faults; private protected assets, cleanup, untouched installer EXIT trap/shared0777 parent, ZIP modes/static duplication and payload hashes')
