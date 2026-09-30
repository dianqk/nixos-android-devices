"""Exercise the shared storage checks without touching block devices."""
import os
from pathlib import Path
import subprocess
import unittest

CHECKER = Path(__file__).resolve().parents[1] / "devices/clover/check-partition.sh"
SCRIPT = r'''
set -eu
fail() { echo "$*" >&2; exit 1; }
. "$CHECKER"
CLOVER_PARTUUID=11111111-2222-3333-4444-555555555555
CLOVER_PART_NUMBER=${EXPECTED_NUMBER-64}
CLOVER_PART_OFFSET=${EXPECTED_OFFSET-15795488}
CLOVER_PART_BYTES=54449765888
CLOVER_ROOT_LABEL=CLOVER_NIXOS
CLOVER_ROOT_UUID=${EXPECTED_UUID-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}
test() {
  if [ "$1" = -b ]; then return 0; fi
  command test "$@"
}
readlink() {
  case "$2" in
    /dev/disk/*) echo /dev/mmcblk1p64 ;;
    */mmcblk1p64/..) echo /sys/devices/c0c4000.sdhci/mmcblk1 ;;
    */mmcblk1p64) echo "/sys/devices/${BUS-c0c4000.sdhci}/mmcblk1/mmcblk1p64" ;;
    *) return 1 ;;
  esac
}
blkid() {
  case "$3" in
    PART_ENTRY_UUID) echo "${ACTUAL_PARTUUID-$CLOVER_PARTUUID}" ;;
    PART_ENTRY_NAME) echo "${LABEL-userdata}" ;;
    PART_ENTRY_NUMBER) echo "${NUMBER-64}" ;;
    PART_ENTRY_OFFSET) echo "${OFFSET-15795488}" ;;
    TYPE) echo "${FSTYPE-ext4}" ;;
    LABEL) echo "${FSLABEL-CLOVER_NIXOS}" ;;
    UUID) echo "${FSUUID-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}" ;;
    *) return 1 ;;
  esac
}
blockdev() { echo "${BYTES-54449765888}"; }
cat() { echo "${REMOVABLE-0}"; }
clover_check_partition userdata yes
'''


class CloverStorage(unittest.TestCase):
    def run_check(self, **values):
        return subprocess.run(
            ["sh", "-c", SCRIPT],
            env={**os.environ, "CHECKER": str(CHECKER), **values},
            capture_output=True, text=True,
        )

    def test_measured_contract(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_optional_geometry_and_uuid_contract(self):
        result = self.run_check(EXPECTED_NUMBER="", EXPECTED_OFFSET="", EXPECTED_UUID="")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_reject_identity_geometry_and_filesystem_mismatches(self):
        for field, value in {
            "ACTUAL_PARTUUID": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            "LABEL": "boot", "NUMBER": "12", "OFFSET": "0", "BYTES": "67108864",
            "BUS": "external", "REMOVABLE": "1", "FSTYPE": "vfat",
            "FSLABEL": "wrong", "FSUUID": "11111111-2222-3333-4444-555555555555",
            "EXPECTED_NUMBER": "oops", "EXPECTED_OFFSET": "-1",
        }.items():
            with self.subTest(field=field):
                self.assertNotEqual(self.run_check(**{field: value}).returncode, 0)


if __name__ == "__main__":
    unittest.main()
