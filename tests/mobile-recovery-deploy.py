#!/usr/bin/env python3
"""Execute shared deployment against regular files with simulated device/Nix APIs.

Real shell, NAR hashing, file writes/readback, and transaction markers are used.
No block devices or mounts are available to the fixture adapters.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
OLD = '/nix/store/' + '0' * 32 + '-nixos-system-clover-old'
NEW = '/nix/store/' + '1' * 32 + '-nixos-system-clover-new'

class Deployment(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=REPO / 'tmp')
        self.root = Path(self.temp.name)
        self.run = self.root / 'ram'
        self.run.mkdir()
        for path, byte in [(OLD, b'a'), (NEW, b'b')]:
            system = self.root / path[1:]
            (system / 'etc').mkdir(parents=True)
            (system / 'etc/fstab').write_text('/dev/test-root / ext4 defaults 0 1\n')
            (system / 'mobile-efi').touch()
            (system / 'init').write_text('fixture')
        self.boot = self.root / 'boot-partition'
        self.boot.write_bytes(b'existing U-Boot firmware')
        self.boot_before = self.boot.read_bytes()
        (self.root / 'selected').write_text(OLD)
        digest = subprocess.check_output(['nix', '--extra-experimental-features', 'nix-command',
                                         'hash', 'path', '--type', 'sha256', '--base32', str(self.root / NEW[1:])], text=True).strip()
        self.manifest = self.root / 'manifest'
        self.manifest.write_text(f'sha256:{digest} {NEW}\n')
        text = (REPO / 'pkgs/mobile-recovery-deploy/deploy.sh').read_text()
        a = text.index('device_name=')
        b = text.index('cleanup() {')
        text = text[:a] + "device_name=clover\n" + text[b:]
        text = text.replace('ROOT=/recovery', f"ROOT='{self.root}'").replace('/run/mobile', str(self.run / 'mobile'))
        shim = '''
operation_lock() { :; }
recovery_gate() { :; }
mount_root() { :; }
mount() { :; }
umount() { :; }
mountpoint() { return 1; }
sync() { :; }
validate_manifest() { :; }
selected_system() { cat "$ROOT/selected"; }
esp_partition() { esp_target=/dev/fixture-esp; }
dd() { echo "Unexpected firmware write" >&2; exit 99; }
chroot() {
  shift
  executable=$1
  shift
  case "$executable" in
    */sw/bin/nix-store)
      case "$1" in
        --version) echo fixture ;;
        --check-validity) test -e "$ROOT$2" ;;
        --query) test "$2" = --requisites; echo "$3" ;;
        *) echo "Unexpected Nix call: $*" >&2; exit 91 ;;
      esac ;;
    */sw/bin/nix)
      for argument in "$@"; do last=$argument; done
      command nix --extra-experimental-features nix-command hash path --type sha256 --base32 "$ROOT$last" ;;
    */sw/bin/nix-env)
      for argument in "$@"; do last=$argument; done
      printf '%s' "$last" > "$ROOT/selected" ;;
    */bin/switch-to-configuration)
      test "$1" = boot || exit 94
      test "${FAIL_WRITE:-0}" = 0 || exit 99
      mkdir -p "$ROOT/boot/EFI/BOOT" "$ROOT/boot/loader/entries"
      printf EFI > "$ROOT/boot/EFI/BOOT/BOOTAA64.EFI"
      system=${executable%/bin/switch-to-configuration}
      printf 'options init=%s/init\n' "$system" > "$ROOT/boot/loader/entries/generation.conf"
      ;;
    */sw/bin/awk) command awk "$1" "$ROOT$2" ;;
    */sw/bin/cat) command cat "$ROOT$1" ;;
    */sw/bin/readlink) test "$1" = -f; echo "$2" ;;
    *) echo "Unexpected chroot call: $executable" >&2; exit 92 ;;
  esac
}
'''
        index = text.index('\noperation_lock\n')
        self.script = self.root / 'deploy'
        self.script.write_text(text[:index] + '\n' + shim + text[index:])

    def tearDown(self):
        self.temp.cleanup()

    def deploy(self, fail_write=False):
        return subprocess.run(['sh', str(self.script), 'deploy-offline', str(self.manifest), NEW, '0', '--confirm'],
                              input=b'', capture_output=True,
                              env=os.environ | {'FAIL_WRITE': '1' if fail_write else '0'})

    def test_efi_import_verify_select_installs_files_without_writing_firmware(self):
        result = self.deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'selected').read_text(), NEW)
        self.assertEqual(self.boot.read_bytes(), self.boot_before)
        self.assertTrue((self.run / 'mobile-offline-deploy.result').read_text().startswith('installed '))
        self.assertFalse((self.root / 'var/lib/mobile-offline-deploy/pending').exists())

    def test_corrupt_closure_does_not_select_or_write_boot(self):
        before = self.boot.read_bytes()
        (self.root / NEW[1:] / 'init').write_text('corrupt')
        result = self.deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'Content hash mismatch', result.stderr)
        self.assertEqual((self.root / 'selected').read_text(), OLD)
        self.assertEqual(self.boot.read_bytes(), before)

    def test_all_devices_require_efi_source_and_target(self):
        for device in ['polaris', 'asphalt', 'clover', 'sheng']:
            for candidate in [OLD, NEW]:
                with self.subTest(device=device, candidate=candidate):
                    marker = self.root / candidate[1:] / 'mobile-efi'
                    marker.unlink()
                    script = self.script.read_text()
                    self.script.write_text(script.replace('device_name=clover',
                        f'device_name={device}\nvalidate_deploy_manifest() {{ :; }}'))
                    digest = subprocess.check_output(['nix', '--extra-experimental-features', 'nix-command',
                        'hash', 'path', '--type', 'sha256', '--base32', str(self.root / NEW[1:])], text=True).strip()
                    self.manifest.write_text(f'sha256:{digest} {NEW}\n')
                    result = self.deploy()
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(b'Deploy requires EFI-capable systems', result.stderr)
                    self.assertEqual((self.root / 'selected').read_text(), OLD)
                    self.assertEqual(self.boot.read_bytes(), self.boot_before)
                    marker.touch()
                    self.script.write_text(script)

    def test_unfinished_install_or_rebuild_is_not_overridden(self):
        for name in ['mobile-efi-preparation', 'mobile-offline-rebuild']:
            with self.subTest(name=name):
                marker = self.root / 'var/lib' / name / 'pending'
                marker.parent.mkdir(parents=True)
                marker.touch()
                result = self.deploy()
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(marker.exists())
                self.assertEqual((self.root / 'selected').read_text(), OLD)
                self.assertEqual(self.boot.read_bytes(), self.boot_before)
                marker.unlink()

    def test_interrupted_efi_install_can_resume_without_writing_firmware(self):
        result = self.deploy(fail_write=True)
        self.assertNotEqual(result.returncode, 0)
        marker = self.root / 'var/lib/mobile-offline-deploy/pending'
        self.assertEqual(marker.read_text().strip(), NEW)
        result = self.deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(marker.exists())
        self.assertEqual(self.boot.read_bytes(), self.boot_before)

if __name__ == '__main__': unittest.main()
