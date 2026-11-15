#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Deterministic KernelSU Manager ZIP. Packaging only; never a write backend."""
import hashlib
import json
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import zipfile

source, native, template, output, sources, license_file = map(Path, sys.argv[1:])
module = output / 'module'
module.mkdir(parents=True)
for name in ['module.prop', 'customize.sh', 'action.sh', 'uninstall.sh']:
    shutil.copyfile(source / 'module' / name, module / name)
for name in ['bin/boot-choice', 'system/bin/boot-choice']:
    p = module / name
    p.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(native, p)
shutil.copytree(template, module / 'template')
shutil.copytree(source / 'module/webroot', module / 'webroot')
shutil.copyfile(source / 'USAGE.md', module / 'USAGE.md')
if (source / 'USAGE.zh.md').exists():
    shutil.copyfile(source / 'USAGE.zh.md', module / 'USAGE.zh.md')
shutil.copyfile(license_file, module / 'COPYING')
shutil.copyfile(sources, module / 'source.tar.gz')
elf = subprocess.check_output(['readelf', '-h', '-l', '-d', '-Ws', str(native)], text=True)
assert 'AArch64' in elf and 'INTERP' not in elf and '(NEEDED)' not in elf and '(RPATH)' not in elf and '(RUNPATH)' not in elf
assert not any(' UND ' in line and line.split()[-1] != 'UND' for line in elf.splitlines()), 'undefined native import'
for name in ['selector.elf', 'firmware.elf']:
    info = subprocess.check_output(['readelf', '-l', '-d', str(template / name)], text=True)
    assert 'INTERP' not in info and '(NEEDED)' not in info and '(RPATH)' not in info and '(RUNPATH)' not in info, name
assert b'/nix/store/' not in native.read_bytes(), 'native executable embeds Nix store reference'
t = json.loads((template / 'template.json').read_text())
assert t['profile'] == 'dodge'
for field, name in [('selector', 'selector.bin'), ('raw', 'firmware.bin'), ('elf', 'firmware.elf'), ('config', 'firmware.config'), ('helper', 'boot-choice.efi')]:
    assert hashlib.sha256((template / name).read_bytes()).hexdigest() == t[field + '_sha256']
files = sorted(p for p in module.rglob('*') if p.is_file())
for p in files:
    data = p.read_bytes()
    assert b'/home/' not in data, p
    assert p.suffix.lower() not in ['.img', '.apk'], p
    assert not data.startswith(b'ANDROID!'), p
    executable = p.relative_to(module).as_posix() in ['bin/boot-choice', 'system/bin/boot-choice', 'action.sh', 'uninstall.sh']
    p.chmod(0o755 if executable else 0o444)
manifest = {
    'schema': 1, 'profile': 'dodge', 'module_id': 'android-devices-dodge-boot-choice',
    'template': t, 'runtime': 'static-aarch64-linux-musl',
    'components': {p.relative_to(module).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
}
(module / 'payload.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
(module / 'payload.json').chmod(0o444)
files = sorted(p for p in module.rglob('*') if p.is_file())
(module / 'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(module).as_posix()}\n' for p in files))
(module / 'SHA256SUMS').chmod(0o444)
with zipfile.ZipFile(output / 'dodge-boot-choice-kernelsu.zip', 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for p in sorted(module.rglob('*')):
        if not p.is_file():
            continue
        info = zipfile.ZipInfo(p.relative_to(module).as_posix(), (1980, 1, 1, 0, 0, 0))
        info.create_system = 3
        info.external_attr = (stat.S_IFREG | stat.S_IMODE(p.stat().st_mode)) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(info, p.read_bytes())
(output / 'manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
print('PASS: deterministic self-contained KernelSU ZIP; static native ELF and template bindings verified')
