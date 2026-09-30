#!/usr/bin/env python3
"""Exercise Polaris name-based partition selection without block-device writes."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
SOURCE = REPO / "devices/polaris/storage-roles-auto.sh"


class AutoStorage(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=REPO / "tmp")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.devices = self.work / "dev"
        self.labels = self.devices / "disk/by-partlabel"
        self.labels.mkdir(parents=True)
        self.controller = self.work / "ufs"
        self.controller.mkdir()
        self.class_block = self.work / "sys/class/block"
        self.class_block.mkdir(parents=True)
        self.compatible = self.work / "compatible"
        self.compatible.write_bytes(b"qcom,sdm845\0xiaomi,polaris\0")
        for name, number in (("userdata", 21), ("system", 48), ("boot", 45), ("recovery", 19), ("misc", 9)):
            self.add_partition(name, number)

        self.bin = self.work / "bin"
        self.bin.mkdir()
        blkid = self.bin / "blkid"
        blkid.write_text("""#!/bin/sh
name=${6##*/}
case "$3" in
  PART_ENTRY_SCHEME) echo gpt ;;
  PART_ENTRY_NAME)
    case "$name" in p21) echo userdata ;; p48|p99) echo system ;; p45) echo boot ;; p19) echo recovery ;; p9) echo misc ;; esac ;;
  PART_ENTRY_UUID) echo 11111111-2222-3333-4444-555555555555 ;;
  PART_ENTRY_NUMBER) echo "${name#p}" ;;
  PART_ENTRY_OFFSET) echo 8192 ;;
  TYPE)
    case "$name" in p21) echo ext4 ;; p48) echo vfat ;; esac ;;
  LABEL)
    case "$name" in p21) echo "${TEST_ROOT_LABEL:-NIXOS}" ;; p48) echo NIXOS_BOOT ;; esac ;;
esac
""")
        blkid.chmod(0o755)
        blockdev = self.bin / "blockdev"
        blockdev.write_text("""#!/bin/sh
case "$2" in
  */p9) echo "${TEST_MISC_BYTES:-4194304}" ;;
  *) echo 3221225472 ;;
esac
""")
        blockdev.chmod(0o755)

        source = SOURCE.read_text()
        source = source.replace("/proc/device-tree/compatible", str(self.compatible))
        source = source.replace("/dev/disk/by-partlabel", str(self.labels))
        source = source.replace('"/dev/${candidate##*/}"', f'"{self.devices}/${{candidate##*/}}"')
        source = source.replace("/sys/class/block", str(self.class_block))
        source = source.replace("/sys/devices/platform/soc@0/1d84000.ufshc", str(self.controller))
        self.script = self.work / "roles.sh"
        self.script.write_text(source)

    def add_partition(self, name, number):
        device = self.devices / f"p{number}"
        device.touch()
        sysfs = self.controller / f"p{number}"
        sysfs.mkdir()
        (sysfs / "partition").write_text(str(number))
        (self.class_block / f"p{number}").symlink_to(sysfs)
        (self.labels / name).symlink_to(device)

    def select(self, role, require_fs="no", **environment):
        env = os.environ | environment | {"PATH": f"{self.bin}:{os.environ['PATH']}"}
        return subprocess.run(
            ["bash", "-c", """
set -e
fail() { echo "$*" >&2; exit 1; }
test() {
  if [[ ${1:-} == -b ]]; then shift; builtin test -f "$1";
  else builtin test "$@"; fi
}
. "$SCRIPT"
POLARIS_DEFAULT_ROOT_LABEL=NIXOS
polaris_partition_role "$ROLE" "$REQUIRE_FS"
printf '%s %s %s %s\n' "$POLARIS_TARGET" "$POLARIS_PARTLABEL" "$POLARIS_PART_BYTES" "$POLARIS_FS_UUID"
"""],
            env=env | {"SCRIPT": str(self.script), "ROLE": role, "REQUIRE_FS": require_fs},
            text=True,
            capture_output=True,
        )

    def test_stock_names_and_filesystems(self):
        root = self.select("userdata", "yes")
        self.assertEqual(root.returncode, 0, root.stderr)
        self.assertIn("p21 userdata 3221225472", root.stdout)
        esp = self.select("esp", "yes")
        self.assertEqual(esp.returncode, 0, esp.stderr)
        self.assertIn("p48 system 3221225472", esp.stdout)

    def test_duplicate_gpt_name_is_rejected(self):
        self.add_partition("duplicate", 99)
        result = self.select("esp")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not unique", result.stderr)

    def test_wrong_controller_is_rejected(self):
        (self.class_block / "p48").unlink()
        other = self.work / "other/p48"
        other.mkdir(parents=True)
        (other / "partition").write_text("48")
        (self.class_block / "p48").symlink_to(other)
        result = self.select("esp")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("built-in UFS", result.stderr)

    def test_wrong_root_label_is_rejected(self):
        result = self.select("userdata", "yes", TEST_ROOT_LABEL="OTHER")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("filesystem label mismatch", result.stderr)

    def test_misc_needs_exact_bcb_size(self):
        self.assertEqual(self.select("misc").returncode, 0)
        result = self.select("misc", TEST_MISC_BYTES="8388608")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("4 MiB", result.stderr)

    def test_wrong_model_is_rejected(self):
        self.compatible.write_bytes(b"xiaomi,other\0")
        result = self.select("boot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Not a Polaris device", result.stderr)


if __name__ == "__main__":
    unittest.main()
