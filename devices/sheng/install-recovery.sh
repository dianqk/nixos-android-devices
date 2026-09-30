#!/usr/bin/env bash
# Install only recovery_b while Sheng recovery runs entirely in RAM.
set -Eeuo pipefail
fail() { echo "ERROR: $*" >&2; exit 1; }
[[ $# == 4 && ( $1 == --check || $1 == --execute ) ]] || fail 'Usage: sheng-install-recovery --check|--execute IMAGE SHA256 EXPECTED_OLD_SHA256'
mode=$1 image=$2 image_hash=$3 old_hash=$4
[[ $image_hash =~ ^[0-9a-f]{64}$ && $old_hash =~ ^[0-9a-f]{64}$ ]] || fail 'Invalid SHA-256'
[[ $EUID == 0 && $(cat /proc/1/comm) == systemd && -f /etc/initrd-release && $(cat /etc/mobile-ram-recovery) == sheng ]] || fail 'Run in Sheng RAM recovery'
tr '\0' '\n' < /proc/device-tree/compatible | grep -qx xiaomi,sheng || fail 'Not Sheng'
# shellcheck source=devices/sheng/slot-gate.sh
source /bin/sheng-slot-gate
sheng_slot_gate
exec 9>/run/recovery.lock
flock -n 9 || fail 'Another recovery action is running'
while read -r _ _ mm rest; do
  [[ ! -e /sys/dev/block/$mm ]] || fail 'Unmount all block filesystems'
  fs=${rest#* - }; fs=${fs%% *}
  case "$fs" in rootfs|ramfs|tmpfs|devtmpfs|proc|sysfs|devpts|cgroup|cgroup2|securityfs|debugfs|tracefs|configfs|functionfs|pstore|mqueue|bpf|fusectl) ;; *) fail 'Unmount non-RAM filesystems' ;; esac
done < /proc/self/mountinfo
[[ $(wc -l < /proc/swaps) -le 1 ]] || fail 'Disable swap'
target=$(readlink -f /dev/disk/by-partlabel/recovery_b)
[[ -b $target && $(blkid -p -s PART_ENTRY_NAME -o value "$target") == recovery_b && $(blockdev --getsize64 "$target") == 104857600 ]] || fail 'Unexpected recovery_b identity or capacity'
node=$(basename "$target")
case "$(readlink -f "/sys/class/block/$node")" in */1d84000.ufshc/*) ;; *) fail 'Not Sheng UFS' ;; esac
disk=/dev/$(basename "$(readlink -f "/sys/class/block/$node/..")")
[[ $(blockdev --getss "$disk") == 4096 ]] || fail 'Unexpected UFS sector size'
sfdisk --verify "$disk" >/dev/null || fail 'Invalid recovery GPT'
[[ -f $image && ! -L $image ]] || fail 'Expected a regular image file'
[[ $(sha256sum "$image" | cut -d ' ' -f1) == "$image_hash" ]] || fail 'Image transfer hash mismatch'
bash "${SHENG_IMAGE_CHECK:-/bin/sheng-check-recovery-image}" "$image"
[[ $(sha256sum "$target" | cut -d ' ' -f1) == "$old_hash" ]] || fail 'Recovery changed since host check'
if [[ $mode == --check ]]; then
  echo "CHECK PASSED: recovery_b=$target old=$old_hash new=$image_hash"
  exit 0
fi
dd if="$image" of="$target" bs=4M conv=notrunc,fsync status=none
[[ $(sha256sum "$target" | cut -d ' ' -f1) == "$image_hash" ]] || fail 'CRITICAL: recovery readback mismatch; stay in RAM recovery and reinstall'
sync
echo "INSTALLED: recovery_b full partition SHA-256 $image_hash"
