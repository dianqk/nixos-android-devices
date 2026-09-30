#!/usr/bin/env python3
"""Execute the shared receiver with real tar/NAR hashes and file-backed firmware.
Only mount, block-device and target Nix/EFI interfaces are simulated.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tarfile
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
IMAGE = '/nix/store/' + '2' * 32 + '-uboot.img'


def nar(path):
    return subprocess.check_output(['nix', '--extra-experimental-features', 'nix-command',
                                   'hash', 'path', '--type', 'sha256', '--base32', str(path)], text=True).strip()


class FirstInstall(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get('MOBILE_TEST_TMP', REPO / 'tmp'))
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.root = self.work / 'root'
        self.root.mkdir()
        (self.root / 'lost+found').mkdir()
        self.ram = self.work / 'ram'
        self.ram.mkdir()
        self.payload = self.work / 'payload'
        self.boot = self.work / 'boot-partition'
        self.before = b'old firmware'.ljust(16384, b'!')
        self.boot.write_bytes(self.before)
        for name in ('root-partition', 'esp-partition', 'boot_a', 'recovery_a', 'recovery_b', 'super'):
            (self.work / name).write_bytes(b'preserve')
        self.manifest = self.work / 'manifest'
        self.registration = self.work / 'registration'
        self.registration.write_text('fixture')
        source = (REPO / 'pkgs/mobile-recovery-deploy/initial.sh').read_text()
        source = source.replace('ROOT=/recovery', 'ROOT="$WORK/root"')
        source = source.replace('/run/mobile-', str(self.ram / 'mobile-'))
        source = source.replace('. /etc/mobile-recovery-target', 'TARGET_HOSTNAME=$BOARD; TARGET_ROOT_LABEL=TEST_ROOT; TARGET_ESP_LABEL=$ESP_LABEL')
        source = source.replace('. /etc/mobile-initial-install-adapter', ':')
        source = source.replace('cat /etc/mobile-ram-recovery', 'printf %s "$BOARD"')
        shim = r'''
operation_lock() { :; }
recovery_gate() { test "$GATE" = 1 || fail 'Device or slot refused'; }
initial_devices() {
  root_device=$WORK/root-partition
  esp_device=$WORK/esp-partition
  boot_device=$WORK/boot-partition
}
initial_check_system() { test "$CONTRACT" = 1 || fail 'Storage contract differs'; }
test() {
  if [ "$1" = -b ]; then
    case "$2" in "$WORK/"*-partition) return 0 ;; *) return 1 ;; esac
  fi
  command test "$@"
}
readlink() {
  case "$2" in
    /sys/class/block/root-partition) echo /sys/devices/controller/lun0/root-partition ;;
    /sys/class/block/esp-partition) echo /sys/devices/controller/lun5/esp-partition ;;
    /dev/disk/by-label/TEST_ROOT|/dev/disk/by-partlabel/userdata|/dev/disk/by-uuid/test-root) echo "$WORK/root-partition" ;;
    /dev/test-esp) echo "$WORK/esp-partition" ;;
    *) command readlink "$@" ;;
  esac
}
blkid() {
  case "$3:$6" in
    PART_ENTRY_NAME:*root-partition) echo "$ROOT_LABEL" ;;
    PART_ENTRY_NAME:*esp-partition) echo "$ESP_LABEL" ;;
    PART_ENTRY_NAME:*boot-partition) echo "$BOOT_LABEL" ;;
    PART_ENTRY_UUID:*) echo "fixture-$6" ;;
    PART_ENTRY_OFFSET:*) echo 2048 ;;
    TYPE:*root-partition) echo ext4 ;;
    TYPE:*esp-partition) test "$FAT_READY" = 1 || return 1; echo vfat ;;
    LABEL:*) echo TEST_ROOT ;;
    *) exit 80 ;;
  esac
}
lsblk() {
  printf '%s %s\n' "$WORK/root-partition" "$ROOT_LABEL" "$WORK/esp-partition" "$ESP_LABEL" "$WORK/boot-partition" "$BOOT_LABEL"
  if test "$DUPLICATE" = 1; then echo "/dev/other $BOOT_LABEL"; fi
}
blockdev() { stat -c %s "$2"; }
e2fsck() { :; }
fsck.fat() { :; }
mount() {
  for arg in "$@"; do last=$arg; done
  if test "$last" = "$ROOT"; then touch "$WORK/mounted"; fi
}
umount() { if test "$1" = "$ROOT"; then rm -f "$WORK/mounted"; fi; }
mountpoint() { test "$2" = "$ROOT" && test -e "$WORK/mounted"; }
sync() { :; }
df() { printf 'fixture 999999999 0 %s 0%% /\n' "$FREE_SPACE"; }
chroot() {
  shift; executable=$1; shift
  case "$executable" in
    */sw/bin/test) return 0 ;;
    */sw/bin/awk) command awk "$1" "$2" "$3" "$ROOT$4" ;;
    */sw/bin/nix-store)
      case "$1" in
        --load-db) cat >/dev/null; test "$REGISTRATION" = 1 ;;
        --verify) test "$VALID_STORE" = 1 ;;
        --query) printf '%s\n' "$SYSTEM" "$IMAGE" ;;
        *) exit 90 ;;
      esac ;;
    */sw/bin/nix)
      for arg in "$@"; do last=$arg; done
      command nix --extra-experimental-features nix-command hash path --type sha256 --base32 "$ROOT$last" ;;
    */sw/bin/nix-env)
      ln -s "$SYSTEM" "$ROOT/nix/var/nix/profiles/system-1-link"
      ln -s system-1-link "$ROOT/nix/var/nix/profiles/system" ;;
    */sw/bin/readlink)
      case "$2" in
        */mobile-boot.img) echo "$IMAGE" ;;
        /nix/var/nix/profiles/system) cat "$WORK/selected" ;;
        *) exit 91 ;;
      esac ;;
    */bin/switch-to-configuration)
      test "$1" = boot && test "$NIXOS_INSTALL_BOOTLOADER" = 1 || exit 92
      test -f "$ROOT/etc/NIXOS" || exit 93
      echo efi >> "$WORK/order"
      test "$FAIL_EFI" = 0 || return 94
      mkdir -p "$ROOT/boot/EFI/BOOT" "$ROOT/boot/loader/entries"
      echo efi > "$ROOT/boot/EFI/BOOT/BOOTAA64.EFI"
      if test "$MISSING_ENTRY" = 0; then echo "options init=$SYSTEM/init" > "$ROOT/boot/loader/entries/first.conf"; fi
      if test "$CHANGE_BOOT" = 1; then printf changed | command dd of="$WORK/boot-partition" conv=notrunc status=none; fi
      ;;
    */sw/bin/dd)
      # Only this regular fixture file is writable by the firmware interface.
      test "$2" = "of=$WORK/boot-partition" || exit 95
      case "$1" in
        if=/nix/store/*) echo firmware >> "$WORK/order"; source=${1#if=}; shift; set -- "if=$ROOT$source" "$@" ;;
        if=/dev/zero) ;;
        *) exit 96 ;;
      esac
      command dd "$@"
      if test "$FAIL_READBACK" = 1; then printf BAD | command dd of="$WORK/boot-partition" conv=notrunc status=none; fi
      ;;
    *) echo "Unexpected chroot: $executable" >&2; exit 99 ;;
  esac
}
'''
        self.script = self.work / 'install'
        source = source.replace('\noperation_lock\n', '\n' + shim + '\noperation_lock\n')
        self.script.write_text(source)
        self.prepare('polaris')

    def prepare(self, board):
        if self.payload.exists():
            shutil.rmtree(self.payload)
        self.board = board
        self.system = '/nix/store/' + '1' * 32 + f'-nixos-system-{board}-test'
        self.system_dir = self.payload / self.system[1:]
        (self.system_dir / 'etc').mkdir(parents=True, exist_ok=True)
        (self.system_dir / 'etc/fstab').write_text('/dev/disk/by-label/TEST_ROOT / ext4 defaults 0 1\n/dev/test-esp /boot vfat defaults 0 2\n')
        (self.system_dir / 'mobile-efi').touch()
        (self.system_dir / 'mobile-device').write_text(board)
        (self.payload / IMAGE[1:]).write_bytes(b'ANDROID!' + b'B' * 8192)
        (self.work / 'selected').write_text(self.system)
        self.update_manifest()

    def update_manifest(self):
        self.manifest.write_text(''.join(f'sha256:{nar(self.payload / p[1:])} {p}\n' for p in [self.system, IMAGE]))

    def install(self, *, execute=True, **settings):
        archive = self.work / 'closure.tar'
        with tarfile.open(archive, 'w') as out:
            out.add(self.payload / 'nix', arcname='nix')
        ab = self.board in ('asphalt', 'sheng')
        defaults = dict(FAT_READY='1', VALID_STORE='1', FAIL_EFI='0', MISSING_ENTRY='0',
                        CHANGE_BOOT='0', FAIL_READBACK='0', GATE='1', DUPLICATE='0',
                        CONTRACT='1', REGISTRATION='1', FREE_SPACE='999999999')
        env = os.environ | defaults | settings | dict(WORK=str(self.work), SYSTEM=self.system,
                    IMAGE=IMAGE, BOARD=self.board, ROOT_LABEL='linux' if ab else 'userdata',
                    ESP_LABEL='linux-boot' if ab else 'system', BOOT_LABEL='boot_b' if ab else 'boot')
        return subprocess.run(['sh', str(self.script), 'install-initial', str(self.manifest),
                               str(self.registration), self.system, '1024', '--confirm' if execute else '--check'],
                              input=archive.read_bytes(), capture_output=True, env=env)

    def marker(self):
        return self.root / 'var/lib/mobile-efi-preparation/pending'

    def test_fresh_root_installs_efi_before_firmware(self):
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.work / 'order').read_text(), 'efi\nfirmware\n')
        self.assertFalse(self.marker().exists())
        image = (self.payload / IMAGE[1:]).read_bytes()
        self.assertEqual(self.boot.read_bytes(), image.ljust(len(self.before), b'\0'))
        self.assertTrue((self.ram / 'mobile-initial-install.result').read_text().startswith('installed '))
        for name in ('boot_a', 'recovery_a', 'recovery_b', 'super'):
            self.assertEqual((self.work / name).read_bytes(), b'preserve')

    def test_check_does_not_extract_or_mark(self):
        result = self.install(execute=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / 'nix').exists())
        self.assertFalse(self.marker().exists())
        self.assertEqual(self.boot.read_bytes(), self.before)

    def test_existing_root_is_preserved(self):
        (self.root / 'valuable').write_text('preserve')
        self.assertNotEqual(self.install().returncode, 0)
        self.assertEqual((self.root / 'valuable').read_text(), 'preserve')
        self.assertEqual(self.boot.read_bytes(), self.before)

    def test_preconditions_fail_before_transfer(self):
        for setting in (dict(FAT_READY='0'), dict(GATE='0'), dict(DUPLICATE='1'), dict(FREE_SPACE='1')):
            with self.subTest(setting=setting):
                self.assertNotEqual(self.install(**setting).returncode, 0)
                self.assertFalse((self.root / 'nix').exists())
                self.assertEqual(self.boot.read_bytes(), self.before)

    def test_invalid_store_leaves_pending_and_preserves_boot(self):
        result = self.install(VALID_STORE='0')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.marker().exists())
        self.assertEqual(self.boot.read_bytes(), self.before)

    def test_actual_content_corruption_is_detected(self):
        (self.payload / IMAGE[1:]).write_bytes(b'ANDROID!' + b'C' * 8192)
        result = self.install()
        self.assertIn(b'Content hash mismatch', result.stderr)
        self.assertTrue(self.marker().exists())
        self.assertEqual(self.boot.read_bytes(), self.before)

    def test_failed_efi_never_writes_boot(self):
        result = self.install(FAIL_EFI='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.work / 'order').read_text(), 'efi\n')
        self.assertTrue(self.marker().exists())
        self.assertEqual(self.boot.read_bytes(), self.before)

    def test_readback_failure_keeps_reboot_gate(self):
        result = self.install(FAIL_READBACK='1')
        self.assertIn(b'Firmware readback mismatch', result.stderr)
        self.assertTrue(self.marker().exists())
        self.assertTrue((self.ram / 'mobile-initial-install.result').read_text().startswith('failed '))

    def test_changed_boot_is_not_overwritten(self):
        result = self.install(CHANGE_BOOT='1')
        self.assertIn(b'Boot changed during installation', result.stderr)
        self.assertEqual(self.boot.read_bytes(), b'changed' + self.before[7:])
        self.assertEqual((self.work / 'order').read_text(), 'efi\n')

    def test_wrong_board_is_refused_before_profile(self):
        (self.system_dir / 'mobile-device').write_text('other-board')
        result = self.install()
        self.assertIn(b'another device', result.stderr)
        self.assertFalse((self.root / 'nix/var/nix/profiles/system').is_symlink())
        self.assertEqual(self.boot.read_bytes(), self.before)

    def test_interrupted_tar_cannot_clear_pending(self):
        (self.payload / IMAGE[1:]).unlink()
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.marker().exists())
        self.assertEqual(self.boot.read_bytes(), self.before)

    def test_prepared_empty_root_is_accepted(self):
        (self.root / 'boot').mkdir()
        self.marker().parent.mkdir(parents=True)
        self.marker().write_text('prepared')
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.marker().exists())

    def test_wrong_fstab_is_refused(self):
        (self.system_dir / 'etc/fstab').write_text('/dev/other / ext4 defaults 0 1\n/dev/test-esp /boot vfat defaults 0 2\n')
        self.update_manifest()
        result = self.install()
        self.assertIn(b'System fstab selects another partition', result.stderr)
        self.assertTrue(self.marker().exists())
        self.assertEqual(self.boot.read_bytes(), self.before)

    def test_missing_efi_entry_preserves_boot(self):
        result = self.install(MISSING_ENTRY='1')
        self.assertIn(b'Selected EFI generation is missing', result.stderr)
        self.assertTrue(self.marker().exists())
        self.assertEqual(self.boot.read_bytes(), self.before)

    def test_registration_failure_preserves_boot(self):
        self.assertNotEqual(self.install(REGISTRATION='0').returncode, 0)
        self.assertTrue(self.marker().exists())
        self.assertEqual(self.boot.read_bytes(), self.before)

    def test_storage_contract_failure_preserves_boot(self):
        result = self.install(CONTRACT='0')
        self.assertIn(b'Storage contract differs', result.stderr)
        self.assertTrue(self.marker().exists())
        self.assertEqual(self.boot.read_bytes(), self.before)

    def test_invalid_manifest_fails_before_mount(self):
        self.manifest.write_text(self.manifest.read_text() * 2)
        result = self.install()
        self.assertIn(b'Duplicate manifest path', result.stderr)
        self.assertFalse(self.marker().exists())
        self.assertFalse((self.root / 'nix').exists())
        self.assertEqual(self.boot.read_bytes(), self.before)


class CloverFirstInstall(FirstInstall):
    def setUp(self):
        super().setUp()
        self.prepare('clover')


class AsphaltFirstInstall(FirstInstall):
    def setUp(self):
        super().setUp()
        self.prepare('asphalt')


class ShengFirstInstall(FirstInstall):
    def setUp(self):
        super().setUp()
        self.prepare('sheng')


if __name__ == '__main__':
    unittest.main()
