#!/bin/sh
set -eu
fail() { echo "ERROR: $*" >&2; exit 1; }
# shellcheck disable=SC1090
. "${CLOVER_STORAGE_ROLES:?Clover storage contract is required}"
device() {
  tr '\000' '\n' < /proc/device-tree/compatible | grep -qx xiaomi,clover-lte || fail 'Not Clover LTE'
}
partition() {
  device
  clover_partition_role "$1" "${2:-no}"
  target=$CLOVER_TARGET
}
root_partition() {
  partition userdata yes
}
mounted() {
  mm=$(cat "/sys/class/block/$(basename "$target")/dev")
  awk -v mm="$mm" '$3 == mm { found=1 } END { exit !found }' /proc/self/mountinfo
}
operation_lock() {
  exec 9>/run/recovery.lock
  flock -n 9 || fail 'Another recovery storage or boot action is running'
}
reboot_gate() {
  device
  test "$(cat /proc/1/comm)" = systemd && test -f /etc/initrd-release &&
    test "$(cat /etc/mobile-ram-recovery)" = clover || fail 'Use only in the RAM recovery stage1'
  while read -r _ _ mm rest; do
    test ! -e "/sys/dev/block/$mm" || fail 'Unmount ALL block filesystems before leaving recovery'
    filesystem=${rest#* - }
    filesystem=${filesystem%% *}
    case "$filesystem" in
      rootfs|ramfs|tmpfs|devtmpfs|proc|sysfs|devpts|cgroup|cgroup2|securityfs|debugfs|\
      tracefs|configfs|functionfs|pstore|mqueue|bpf|fusectl) ;;
      *) fail 'Unmount non-RAM filesystems before leaving recovery' ;;
    esac
  done < /proc/self/mountinfo
  test "$(wc -l < /proc/swaps)" -le 1 || fail 'Disable swap before leaving recovery'
}
write_boot_request() {
  request=$1
  scratch=$(mktemp -d /tmp/clover-bcb.XXXXXX)
  chmod 700 "$scratch"
  dd if="$target" of="$scratch/misc.img" bs=1048576 count=1 2>/dev/null
  test "$(wc -c < "$scratch/misc.img")" = 1048576 || fail 'Short misc backup'
  dd if="$target" bs=1048576 count=1 2>/dev/null | cmp -s - "$scratch/misc.img" || fail 'Misc backup verification failed'
  dd if=/dev/zero of="$scratch/empty" bs=32 count=1 2>/dev/null
  cp "$scratch/empty" "$scratch/recovery"
  printf boot-recovery | dd of="$scratch/recovery" conv=notrunc 2>/dev/null
  dd if="$scratch/misc.img" of="$scratch/old-command" bs=32 count=1 2>/dev/null
  if ! cmp -s "$scratch/old-command" "$scratch/empty" && ! cmp -s "$scratch/old-command" "$scratch/recovery"; then
    fail "Unknown misc command; refusing to overwrite. RAM backup: $scratch/misc.img"
  fi
  case "$request" in system) command_file=$scratch/empty ;; recovery) command_file=$scratch/recovery ;; *) fail 'Invalid boot request' ;; esac
  cp "$scratch/misc.img" "$scratch/expected"
  dd if="$command_file" of="$scratch/expected" bs=32 count=1 conv=notrunc 2>/dev/null
  dd if="$target" bs=1048576 count=1 2>/dev/null | cmp -s - "$scratch/misc.img" || fail 'Misc changed before write'
  if ! dd if="$command_file" of="$target" bs=32 count=1 conv=notrunc,fsync 2>/dev/null ||
    ! dd if="$target" bs=1048576 count=1 2>/dev/null | cmp -s - "$scratch/expected"; then
    dd if="$scratch/old-command" of="$target" bs=32 count=1 conv=notrunc,fsync 2>/dev/null || fail 'CRITICAL: misc command restore failed'
    dd if="$target" bs=1048576 count=1 2>/dev/null | cmp -s - "$scratch/misc.img" || fail 'CRITICAL: misc differs after restore'
    fail 'Boot request write failed and was restored'
  fi
  sync
}
boot_action() {
  action=$1
  test "$#" = 2 && test "$2" = --confirm || fail "Usage: recovery $action --confirm"
  operation_lock; reboot_gate
  if test "$action" != poweroff; then
    partition misc
    test "$CLOVER_PART_BYTES" = 1048576 || fail 'Unexpected misc size'
    case "$action" in reboot-recovery) write_boot_request recovery ;; reboot-system|reboot-bootloader) write_boot_request system ;; *) fail 'Unknown boot action' ;; esac
  fi
  sync
  case "$action" in
    reboot-system) exec /bin/systemctl --force --force reboot ;;
    reboot-recovery) exec /bin/systemctl --force --force --reboot-argument=recovery reboot ;;
    reboot-bootloader) exec /bin/systemctl --force --force --reboot-argument=bootloader reboot ;;
    poweroff) exec /bin/systemctl --force --force poweroff ;;
  esac
  fail 'Shutdown returned; inspect hardware before retrying'
}
case "${1:-}" in
  install-initial) exec /bin/mobile-install-initial "$@" ;;
  mount-target|unmount-target|target-status|enter|rebuild) exec /bin/mobile-recovery-target "$@" ;;
  deploy-query|deploy-offline|deploy-check-boot|base-install|base-verify) exec /bin/mobile-recovery-deploy "$@" ;;
  reboot-system) /bin/mobile-recovery-deploy deploy-check-boot ;;
esac
case "${1:-help}" in
  help) cat /etc/recovery-help ;;
  format-root) exec /bin/clover-storage "$@" ;;
  reboot-system|reboot-recovery|reboot-bootloader|poweroff) boot_action "$@" ;;
  status) device; uname -a; cat /proc/uptime; lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTLABEL,PARTUUID,MOUNTPOINTS ;;
  mount-ro) operation_lock; root_partition; ! mounted || fail 'Root is already mounted'; mkdir -p /recovery; mount -t ext4 -o ro,noload "$target" /recovery ;;
  unmount) operation_lock; umount /recovery; sync ;;
  check-root) operation_lock; root_partition; ! mounted || fail 'Root is mounted'; e2fsck -fn "$target" ;;
  *) fail 'Unknown action; run recovery help' ;;
esac
