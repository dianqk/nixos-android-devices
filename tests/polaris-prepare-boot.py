#!/usr/bin/env python3
"""Exercise recovery preparation gates with files and an instrumented formatter."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]

class PrepareBoot(unittest.TestCase):
    def run_prepare(self, *, execute=False, valid=True, fat=False, label='system', uuid='501a-0048'):
        with tempfile.TemporaryDirectory(dir=REPO / 'tmp') as directory:
            work = Path(directory)
            root = work / 'root'
            (root / 'nix/var/nix/profiles').mkdir(parents=True)
            (root / 'nix/var/nix/profiles/system').symlink_to('/nix/store/test-system')
            (work / 'mountinfo').write_text('')
            (work / 'dev').write_text('8:48\n')
            script = (REPO / 'devices/polaris/prepare-boot.sh').read_text()
            shim = f'''
fail() {{ echo "$*" >&2; exit 1; }}
operation_lock() {{ :; }}
reboot_gate() {{ :; }}
mount_userdata_plain() {{ :; }}
selected_system() {{ echo /nix/store/test-system; }}
mount() {{ :; }}
umount() {{ :; }}
sync() {{ :; }}
chroot() {{
 case "$*" in *'/sw/bin/nix store verify --all --no-trust') ;; *) return 99 ;; esac
 test "$NIX_REMOTE" = 'local?read-only=true' || return 98
 return {0 if valid else 1}
}}
polaris_partition_role() {{
 POLARIS_TARGET=/dev/test-esp
 POLARIS_PARTUUID=11111111-2222-3333-4444-555555555555
 POLARIS_PARTLABEL={label}
 POLARIS_PART_BYTES=3221225472
 POLARIS_FS_TYPE=vfat
 POLARIS_FS_LABEL=NIXOS_BOOT
 POLARIS_FS_UUID={uuid}
}}
blkid() {{ echo {'vfat' if fat else 'unknown'}; }}
fsck.fat() {{ :; }}
mkfs.fat() {{ printf '%s\\n' "$*" > '{work}/formatted'; }}
'''
            script = script.replace('. /bin/recovery', shim)
            script = script.replace('/recovery', str(root)).replace('/proc/self/mountinfo', str(work / 'mountinfo'))
            script = script.replace('"/sys/class/block/$(basename "$esp")/dev"', f'"{work}/dev"')
            p = work / 'prepare.sh'
            p.write_text(script)
            result = subprocess.run(['sh', str(p), '--confirm' if execute else '--check'], capture_output=True)
            return result, (work / 'formatted').exists(), (root / 'var/lib/mobile-efi-preparation/pending').exists()

    def test_check_never_formats(self):
        result, formatted, marker = self.run_prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(formatted)
        self.assertFalse(marker)

    def test_confirm_formats_only_after_verification_and_marks_incomplete(self):
        result, formatted, marker = self.run_prepare(execute=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(formatted)
        self.assertTrue(marker)

    def test_default_contract_needs_no_fat_volume_id(self):
        result, formatted, marker = self.run_prepare(execute=True, uuid='')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(formatted)
        self.assertTrue(marker)

    def test_invalid_store_cannot_format(self):
        result, formatted, marker = self.run_prepare(execute=True, valid=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(formatted)
        self.assertFalse(marker)

    def test_existing_fat_is_not_reformatted(self):
        result, formatted, marker = self.run_prepare(execute=True, fat=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(formatted)
        self.assertFalse(marker)

    def test_super_and_other_partition_names_are_rejected(self):
        for label in ('super', 'userdata', 'system_a', 'boot'):
            result, formatted, _ = self.run_prepare(execute=True, label=label)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(formatted)

    def test_empty_root_allows_only_preparation_marker(self):
        source = (REPO / 'pkgs/mobile-recovery-deploy/initial.sh').read_text()
        function = source[source.index('empty_root() {'):source.index('cleanup() {')]
        with tempfile.TemporaryDirectory(dir=REPO / 'tmp') as directory:
            root = Path(directory)
            (root / 'var/lib/mobile-efi-preparation').mkdir(parents=True)
            (root / 'var/lib/mobile-efi-preparation/pending').touch()
            script = 'fail() { exit 1; };\n' + f'ROOT={root}\n' + function + '\nempty_root'
            self.assertEqual(subprocess.run(['sh', '-c', script]).returncode, 0)
            (root / 'var/valuable').write_text('preserve')
            self.assertNotEqual(subprocess.run(['sh', '-c', script]).returncode, 0)

if __name__ == '__main__': unittest.main()
