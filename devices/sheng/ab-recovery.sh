#!/bin/sh
# RAM recovery commands for Xiaomi Pad 6S Pro (sheng).
set -eu
fail() { echo "ERROR: $*" >&2; exit 1; }
device() {
  tr '\000' '\n' </proc/device-tree/compatible | grep -qx xiaomi,sheng || fail 'Device tree identity mismatch'
}
. /bin/sheng-slot-gate
slot_gate() { sheng_slot_gate; }

gate() {
  device
  test "$(cat /proc/1/comm)" = systemd && test -f /etc/initrd-release &&
    test "$(cat /etc/mobile-ram-recovery)" = sheng || fail 'Not the Sheng RAM recovery'
  while read -r _ _ mm rest; do
    test ! -e "/sys/dev/block/$mm" || fail 'Unmount all block filesystems before leaving recovery'
    fs=${rest#* - }; fs=${fs%% *}
    case "$fs" in
      rootfs|ramfs|tmpfs|devtmpfs|proc|sysfs|devpts|cgroup|cgroup2|securityfs|debugfs|tracefs|configfs|functionfs|pstore|mqueue|bpf|fusectl) ;;
      *) fail 'Unmount non-RAM filesystems before leaving recovery' ;;
    esac
  done </proc/self/mountinfo
  test "$(wc -l </proc/swaps)" -le 1 || fail 'Disable swap before leaving recovery'
}
clear_boot_request() {
  target=/dev/disk/by-partlabel/misc
  check_ufs_partition misc
  misc_disk=$(parent_disk "$target")
  check_ufs_disk "$misc_disk"
  sfdisk --verify "$misc_disk" >/dev/null || fail 'GPT verification failed'
  test -b "$target" && test "$(blkid -p -s PART_ENTRY_NAME -o value "$target")" = misc ||
    fail 'Sheng misc identity mismatch'
  case "$(readlink -f "/sys/class/block/$(basename "$(readlink -f "$target")")")" in
    */1d84000.ufshc/*) ;;
    *) fail 'Sheng misc is not on the expected UFS controller' ;;
  esac
  test "$(blkid -p -s PART_ENTRY_TYPE -o value "$target" | tr A-F a-f)" = 82acc91f-357c-4a68-9c8f-689e1b1a23a1 &&
    test "$(blockdev --getsize64 "$target")" = 4194304 ||
    fail 'Unexpected Sheng misc GPT type or capacity'
  scratch=$(mktemp -d /tmp/sheng-bcb.XXXXXX)
  chmod 700 "$scratch"
  dd if="$target" of="$scratch/before" bs=4194304 count=1 status=none
  test "$(wc -c <"$scratch/before")" = 4194304 || fail 'Short misc snapshot'
  cmp -s "$target" "$scratch/before" || fail 'misc changed during snapshot'
  dd if=/dev/zero of="$scratch/empty" bs=32 count=1 status=none
  cp "$scratch/empty" "$scratch/recovery"
  printf boot-recovery | dd of="$scratch/recovery" conv=notrunc status=none
  dd if="$scratch/before" of="$scratch/command" bs=32 count=1 status=none
  # Android reads command as a NUL-terminated string. Fastboot can leave bytes
  # from the previous longer command after that NUL; they are not a new request.
  dd if="$scratch/command" of="$scratch/prefix" bs=1 count=1 status=none
  dd if="$scratch/empty" of="$scratch/empty-prefix" bs=1 count=1 status=none
  if cmp -s "$scratch/prefix" "$scratch/empty-prefix"; then
    rm -rf "$scratch"
    return
  fi
  dd if="$scratch/command" of="$scratch/prefix" bs=14 count=1 status=none
  dd if="$scratch/recovery" of="$scratch/recovery-prefix" bs=14 count=1 status=none
  cmp -s "$scratch/prefix" "$scratch/recovery-prefix" ||
    fail "Unknown BCB command; RAM snapshot: $scratch/before"
  cp "$scratch/before" "$scratch/expected"
  dd if="$scratch/empty" of="$scratch/expected" bs=32 count=1 conv=notrunc status=none
  cmp -s "$target" "$scratch/before" || fail 'misc changed before command write'
  if ! dd if="$scratch/empty" of="$target" bs=32 count=1 conv=notrunc,fsync status=none ||
    ! cmp -s "$target" "$scratch/expected"; then
    dd if="$scratch/command" of="$target" bs=32 count=1 conv=notrunc,fsync status=none ||
      fail "CRITICAL: misc restore failed; RAM snapshot: $scratch/before"
    cmp -s "$target" "$scratch/before" ||
      fail "CRITICAL: misc differs after restore; RAM snapshot: $scratch/before"
    fail 'BCB command write failed and was restored'
  fi
  sync
  echo "BCB command cleared; RAM snapshot: $scratch/before"
}
operation_lock() {
  exec 9>/run/recovery.lock
  flock -n 9 || fail 'Another recovery action is running'
}
parent_disk() {
  real=$(readlink -f "$1") || fail 'Partition device is absent'
  printf '/dev/%s\n' "$(basename "$(readlink -f "/sys/class/block/$(basename "$real")/..")")"
}
check_ufs_partition() {
  expected=$1
  target=$(readlink -f "/dev/disk/by-partlabel/$expected") || fail "$expected is absent"
  test -b "$target" && test "$(blkid -p -s PART_ENTRY_NAME -o value "$target")" = "$expected" ||
    fail "$expected GPT identity mismatch"
  case "$(readlink -f "/sys/class/block/$(basename "$target")")" in
    */1d84000.ufshc/*) ;;
    *) fail "$expected is not on the Sheng UFS controller" ;;
  esac
}
check_ufs_disk() {
  disk=$1
  device
  test -b "$disk" || fail 'UFS disk is absent'
  case "$(readlink -f "/sys/class/block/$(basename "$disk")")" in
    */1d84000.ufshc/*) ;;
    *) fail 'Disk is not on the Sheng UFS controller' ;;
  esac
  test "$(blockdev --getss "$disk")" = 4096 || fail 'Unsupported logical sector size'
}
case "${1:-}" in
  install-initial) exec /bin/mobile-install-initial "$@" ;;
  mount-target|unmount-target|target-status|enter|rebuild) exec /bin/mobile-recovery-target "$@" ;;
  deploy-query|deploy-offline|deploy-check-boot|base-install|base-verify) exec /bin/mobile-recovery-deploy "$@" ;;
  reboot-system) /bin/mobile-recovery-deploy deploy-check-boot ;;
esac
case "${1:-help}" in
  help) cat /etc/recovery-help ;;
  status) device; uname -a; cat /proc/uptime; lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTLABEL,PARTUUID,MOUNTPOINTS ;;
  install-recovery) shift; exec /bin/bash /bin/sheng-install-recovery "$@" ;;
  format-root) exec /bin/sheng-storage "$@" ;;
  reboot-system|reboot-recovery|reboot-bootloader|poweroff)
    test "${2:-}" = --confirm && test "$#" = 2 || fail "Usage: recovery $1 --confirm"
    operation_lock
    gate
    if test "$1" = reboot-system; then slot_gate; clear_boot_request; fi
    sync
    case "$1" in
      reboot-system) exec /bin/systemctl --force --force reboot ;;
      reboot-recovery) exec /bin/systemctl --force --force --reboot-argument=recovery reboot ;;
      reboot-bootloader) exec /bin/systemctl --force --force --reboot-argument=bootloader reboot ;;
      poweroff) exec /bin/systemctl --force --force poweroff ;;
    esac
    ;;
  *) fail 'Unknown action; run recovery help' ;;
esac
