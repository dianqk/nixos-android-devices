#!/usr/bin/env bash
# Request RAM recovery through BCB; mobile-device performs the subsequent reboot.
set -Eeuo pipefail
fail() { echo "ERROR: $*" >&2; exit 1; }
[[ $# == 1 && ( $1 == --check || $1 == --execute ) ]] || fail 'Usage: request-recovery.sh --check|--execute'
mode=$1
[[ $EUID == 0 && $(cat /proc/1/comm) == systemd && ! -e /etc/initrd-release ]] || fail 'Run as root in the installed Sheng system'
tr '\0' '\n' < /proc/device-tree/compatible | grep -qx xiaomi,sheng || fail 'Not Sheng'
# shellcheck source=devices/sheng/slot-gate.sh
source "${SHENG_SLOT_GATE:-$(dirname "${BASH_SOURCE[0]}")/slot-gate.sh}"
sheng_slot_gate
exec 9>/run/recovery.lock
flock -n 9 || fail 'Another recovery action is running'
target=$(readlink -f /dev/disk/by-partlabel/misc)
[[ -b $target && $(blkid -p -s PART_ENTRY_NAME -o value "$target") == misc &&
   $(blkid -p -s PART_ENTRY_TYPE -o value "$target" | tr A-F a-f) == 82acc91f-357c-4a68-9c8f-689e1b1a23a1 &&
   $(blockdev --getsize64 "$target") == 4194304 ]] || fail 'Unexpected misc identity or capacity'
node=$(basename "$target")
case "$(readlink -f "/sys/class/block/$node")" in */1d84000.ufshc/*) ;; *) fail 'Not Sheng UFS' ;; esac
disk=/dev/$(basename "$(readlink -f "/sys/class/block/$node/..")")
[[ $(blockdev --getss "$disk") == 4096 ]] || fail 'Unexpected UFS sector size'
sfdisk --verify "$disk" >/dev/null || fail 'Invalid misc GPT'
scratch=$(mktemp -d /run/sheng-bcb.XXXXXXXX)
chmod 700 "$scratch"
dd if="$target" of="$scratch/before" bs=4194304 count=1 status=none
[[ $(stat -c %s "$scratch/before") == 4194304 ]] || fail 'Short misc snapshot'
cmp -s "$target" "$scratch/before" || fail 'Misc changed during snapshot'
dd if="$scratch/before" of="$scratch/command" bs=32 count=1 status=none
# Interpret only the NUL-terminated command; preserve the remaining BCB bytes.
command=$(od -An -tx1 -N 32 "$scratch/command" | tr -d ' \n')
case "$command" in 00*|626f6f742d7265636f7665727900*) ;; *) fail 'Unknown BCB command' ;; esac
dd if=/dev/zero of="$scratch/recovery" bs=32 count=1 status=none
printf boot-recovery | dd of="$scratch/recovery" conv=notrunc status=none
cp "$scratch/before" "$scratch/expected"
dd if="$scratch/recovery" of="$scratch/expected" bs=32 count=1 conv=notrunc status=none
if [[ $mode == --check ]]; then
  rm -rf "$scratch"
  echo 'CHECK PASSED: Sheng B slot, misc GPT and current BCB command; no write'
  exit 0
fi
cmp -s "$target" "$scratch/before" || fail 'Misc changed before write'
if ! dd if="$scratch/recovery" of="$target" bs=32 count=1 conv=notrunc,fsync status=none || ! cmp -s "$target" "$scratch/expected"; then
  dd if="$scratch/command" of="$target" bs=32 count=1 conv=notrunc,fsync status=none || fail "CRITICAL: BCB restore failed; snapshot $scratch/before"
  cmp -s "$target" "$scratch/before" || fail "CRITICAL: BCB differs after restore; snapshot $scratch/before"
  fail 'BCB request failed and was restored'
fi
rm -rf "$scratch"
sync
echo 'Verified boot-recovery request; reboot normally to enter RAM recovery.'
