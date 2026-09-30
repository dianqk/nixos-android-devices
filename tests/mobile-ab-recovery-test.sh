#!/usr/bin/env bash
# Exercise the production Y700 BCB transaction against a regular 1 MiB file.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
test_dir="$repo/tmp/mobile-ab-recovery-test"
mkdir -p "$test_dir"
fixture="$test_dir/misc.img"
function_file="$test_dir/clear-asphalt-request.sh"
# shellcheck disable=SC2016
sed -n '/^clear_asphalt_request() {/,/^}/p' "$repo/devices/asphalt/ab-recovery.sh" \
  | sed -e "s@target=/dev/disk/by-partlabel/misc@target=$fixture@" \
        -e 's/test -b "$target"/test -f "$target"/' \
        -e "s@/tmp/asphalt-bcb.@$test_dir/asphalt-bcb.@" > "$function_file"
# Hardware identity and GPT checks are stubbed; dd/cmp and the BCB transaction are real.
blkid() {
  case "$3" in
    PART_ENTRY_NAME) printf '%s\n' misc ;;
    PART_ENTRY_TYPE)
      if test "${TEST_BAD_TYPE:-0}" = 1; then
        printf '%s\n' 00000000-0000-0000-0000-000000000000
      else
        printf '%s\n' 82ACC91F-357C-4A68-9C8F-689E1B1A23A1
      fi
      ;;
    *) return 1 ;;
  esac
}
blockdev() { stat -c %s "$fixture"; }
sfdisk() { test "$*" = '--verify /dev/sda'; }
readlink() {
  if test "$*" = "-f $fixture"; then
    printf '%s\n' /dev/sda7
  else
    command readlink "$@"
  fi
}
check_ufs_disk() { ufs_disk=/dev/sda; }
fail() { echo "ERROR: $*" >&2; exit 1; }
# shellcheck source=/dev/null
source "$function_file"
python3 - "$fixture" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1])
p.write_bytes(b'boot-recovery' + bytes(32-len('boot-recovery')) + bytes((n % 251 for n in range(1048576-32))))
PY
cp "$fixture" "$test_dir/before.img"
clear_asphalt_request
python3 - "$fixture" "$test_dir/before.img" <<'PY'
import sys
from pathlib import Path
new, old = (Path(p).read_bytes() for p in sys.argv[1:])
assert len(new) == len(old) == 1048576
assert new[:32] == bytes(32)
assert new[32:] == old[32:]
PY
# An unknown command must not be changed.
printf 'other-command' | dd of="$fixture" bs=1 count=13 conv=notrunc status=none
cp "$fixture" "$test_dir/unknown-before.img"
if (clear_asphalt_request 2>"$test_dir/unknown-error.log"); then
  echo 'Unknown BCB command was accepted' >&2; exit 1
fi
cmp "$fixture" "$test_dir/unknown-before.img"
grep -q 'Unknown BCB command' "$test_dir/unknown-error.log"
# A wrong GPT identity must fail before any command write.
cp "$test_dir/before.img" "$fixture"
if (TEST_BAD_TYPE=1; clear_asphalt_request 2>"$test_dir/identity-error.log"); then
  echo 'Wrong misc partition type was accepted' >&2; exit 1
fi
cmp "$fixture" "$test_dir/before.img"
grep -q 'identity or size mismatch' "$test_dir/identity-error.log"
# Clean only generated fixture and retained RAM copies from this test.
rm -f "$fixture" "$test_dir/before.img" "$test_dir/unknown-before.img" "$test_dir/unknown-error.log" "$test_dir/identity-error.log" "$function_file"
rm -rf "$test_dir"/asphalt-bcb.*
rmdir "$test_dir"
echo MOBILE_AB_RECOVERY_TESTS_PASSED
