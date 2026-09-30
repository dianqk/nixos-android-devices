#!/usr/bin/env python3
"""Run actual device gates with fixture procfs / blkid responses, without disks."""
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]

class DeviceGates(unittest.TestCase):
    def test_initial_adapters_select_only_their_partition_roles(self):
        shim = r'''set -eu
TARGET_ROOT_LABEL=TEST_ROOT
fail() { echo "$*" >&2; exit 1; }
ufs() { :; }
verify_gpt() { :; }
polaris_partition_role() {
  case "$1" in esp) POLARIS_PARTLABEL=system ;; *) POLARIS_PARTLABEL=$1 ;; esac
  POLARIS_TARGET=/dev/$POLARIS_PARTLABEL
}
clover_partition_role() { CLOVER_TARGET=/dev/$1; }
asphalt_slot_gate() { test "$ALLOW_B" = 1 || fail 'slot refused'; }
sheng_slot_gate() { asphalt_slot_gate; }
linux_partition() { linux_target=/dev/linux; }
check_ufs_partition() { partition=/dev/$1; }
blkid() { echo c12a7328-f81f-11d2-ba4b-00a0c93ec93b; }
blockdev() { echo 1073741824; }
'''
        for device in ['polaris', 'clover', 'asphalt', 'sheng']:
            adapter = (REPO / f'devices/{device}/initial-install.sh').read_text()
            # Substitute only the library import; execute the actual adapter.
            adapter = '\n'.join(line for line in adapter.splitlines() if not line.startswith('. /bin/'))
            ab = device in ['asphalt', 'sheng']
            for allow in ['1', '0'] if ab else ['1']:
                with self.subTest(device=device, allow_b=allow):
                    script = shim + f'\nALLOW_B={allow}\n' + adapter + '\ninitial_devices\nprintf "%s %s %s" "$root_device" "$esp_device" "$boot_device"'
                    result = subprocess.run(['sh', '-c', script], capture_output=True)
                    if allow == '0':
                        self.assertNotEqual(result.returncode, 0)
                        self.assertEqual(result.stdout, b'')
                    else:
                        self.assertEqual(result.returncode, 0, result.stderr)
                        expected = b'/dev/linux /dev/linux-boot /dev/boot_b' if ab else b'/dev/userdata /dev/system /dev/boot'
                        self.assertEqual(result.stdout, expected)

    def test_asphalt_root_uses_efi_entry_without_fixed_disk_letter(self):
        text = (REPO / 'devices/asphalt/storage.sh').read_text()
        gate = text[text.index('linux_partition() {'):text.index('format_root() {')]
        shim = r'''set -eu
fail() { echo "$*" >&2; exit 1; }
check_ufs_partition() { partition=/dev/sdc17; }
test() { if [ "$1" = -b ]; then return 0; fi; command test "$@"; }
blkid() {
  case "$3" in
    PART_ENTRY_NUMBER) echo "$ROOT_NUMBER" ;;
    PART_ENTRY_TYPE) echo 0fc63daf-8483-4772-8e79-3d69d8477de4 ;;
    *) exit 2 ;;
  esac
}
blockdev() { case "$1" in --getsize64) echo 17179869184 ;; --getss) echo 4096 ;; esac; }
readlink() { echo /sys/devices/1d84000.ufshc/sdc; }
sfdisk() { :; }
jq() { cat >/dev/null; }
'''
        for number, allowed in [('17', True), ('16', True), ('0', False)]:
            result = subprocess.run(['sh', '-c', shim + '\nROOT_NUMBER=' + number + '\n' + gate + '\nlinux_partition'], capture_output=True)
            self.assertEqual(result.returncode == 0, allowed, result.stderr)

    def test_ab_deployment_requires_b_and_rejects_a_or_unknown(self):
        for device, compatible in [('asphalt', 'lenovo,asphalt'), ('sheng', 'xiaomi,sheng')]:
            text = (REPO / f'devices/{device}/storage.sh').read_text()
            gate = text[text.index('recovery_gate() {'):text.index('operation_lock() {')]
            if device == 'asphalt':
                gate = text[text.index('asphalt_slot_gate() {'):text.index('recovery_gate() {')] + gate
            if device == 'sheng':
                gate = (REPO / 'devices/sheng/slot-gate.sh').read_text() + '\n' + gate
            for cmdline, bootconfig, allowed in [
                ('androidboot.slot_suffix=_b', '', True),
                ('', 'androidboot.slot_suffix = "_b"', True),
                ('androidboot.slot_suffix=_a', '', False),
                ('', '', False),
                ('androidboot.slot_suffix=_b', 'androidboot.slot_suffix = "_a"', False),
                ('androidboot.slot_suffix=_a', 'androidboot.slot_suffix = "_b"', False),
            ]:
                with self.subTest(device=device, cmdline=cmdline, bootconfig=bootconfig):
                    with tempfile.TemporaryDirectory(dir=REPO / 'tmp') as directory:
                        root = Path(directory)
                        values = {'proc/device-tree/compatible': compatible + '\0', 'proc/1/comm': 'systemd',
                                  'etc/initrd-release': '', 'etc/mobile-ram-recovery': device,
                                  'proc/cmdline': cmdline, 'proc/bootconfig': bootconfig,
                                  'proc/self/mountinfo': '', 'proc/swaps': 'header\n'}
                        for path, value in values.items():
                            p = root / path
                            p.parent.mkdir(parents=True, exist_ok=True)
                            p.write_text(value)
                        fixture_gate = gate.replace('/proc/', str(root / 'proc') + '/').replace('/etc/', str(root / 'etc') + '/')
                        result = subprocess.run(['sh', '-c', 'set -eu\nfail() { echo "$*" >&2; exit 1; }\n' + fixture_gate + '\nrecovery_gate'], capture_output=True)
                        self.assertEqual(result.returncode == 0, allowed, result.stderr)

if __name__ == '__main__': unittest.main()
