#!/bin/sh
# RAM recovery commands for the Lenovo Y700 2023.
set -eu
fail() { echo "ERROR: $*" >&2; exit 1; }
: "${ASPHALT_SYSTEM_HOSTNAME:=asphalt}"
device() {
  tr '\000' '\n' </proc/device-tree/compatible | grep -qx lenovo,asphalt || fail 'Device tree identity mismatch'
}
slot_gate() {
  if grep -Eq '(^|[[:space:]])(androidboot|boot)\.slot_suffix=_a([[:space:]]|$)' /proc/cmdline; then
    fail 'Run the Y700 recovery from slot B'
  fi
  if test -r /proc/bootconfig &&
    grep -Eq '^[[:space:]]*(androidboot|boot)\.slot_suffix[[:space:]]*=[[:space:]]*"?_a"?[[:space:]]*$' /proc/bootconfig; then
    fail 'Run the Y700 recovery from slot B'
  fi
}
gate() {
  device
  test "$(cat /proc/1/comm)" = systemd && test -f /etc/initrd-release &&
    test "$(cat /etc/mobile-ram-recovery)" = asphalt || fail 'Not the RAM recovery'
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
# Android's boot-recovery BCB command can persist after recovery boots. Never
# assume a plain reboot will select boot_b while that request remains set.
clear_asphalt_request() {
  target=/dev/disk/by-partlabel/misc
  check_ufs_disk "$target"
  sfdisk --verify "$ufs_disk" >/dev/null || fail 'GPT verification failed'
  test -b "$target" && test "$(blkid -p -s PART_ENTRY_NAME -o value "$target")" = misc &&
    test "$(blkid -p -s PART_ENTRY_TYPE -o value "$target" | tr 'A-F' 'a-f')" = 82acc91f-357c-4a68-9c8f-689e1b1a23a1 &&
    test "$(blockdev --getsize64 "$target")" = 1048576 || fail 'Y700 misc identity or size mismatch'
  scratch=$(mktemp -d /tmp/asphalt-bcb.XXXXXX)
  chmod 700 "$scratch"
  dd if="$target" of="$scratch/before" bs=1048576 count=1 status=none
  test "$(wc -c <"$scratch/before")" = 1048576 || fail 'Short misc backup'
  cmp -s "$target" "$scratch/before" || fail 'misc changed during backup'
  dd if=/dev/zero of="$scratch/empty" bs=32 count=1 status=none
  cp "$scratch/empty" "$scratch/recovery"
  printf boot-recovery | dd of="$scratch/recovery" conv=notrunc status=none
  cp "$scratch/empty" "$scratch/bootloader"
  printf '%s' '-bootloader' | dd of="$scratch/bootloader" bs=1 seek=8 conv=notrunc status=none
  dd if="$scratch/before" of="$scratch/command" bs=32 count=1 status=none
  # This exact marker remained after a verified ordinary B boot through
  # fastboot. It does not request recovery and needs no misc write.
  if cmp -s "$scratch/command" "$scratch/empty" ||
    cmp -s "$scratch/command" "$scratch/bootloader"; then
    rm -rf "$scratch"
    return
  fi
  cmp -s "$scratch/command" "$scratch/recovery" || fail "Unknown BCB command; RAM backup: $scratch/before"
  cp "$scratch/before" "$scratch/expected"
  dd if="$scratch/empty" of="$scratch/expected" bs=32 count=1 conv=notrunc status=none
  cmp -s "$target" "$scratch/before" || fail 'misc changed before command write'
  if ! dd if="$scratch/empty" of="$target" bs=32 count=1 conv=notrunc,fsync status=none ||
    ! cmp -s "$target" "$scratch/expected"; then
    dd if="$scratch/command" of="$target" bs=32 count=1 conv=notrunc,fsync status=none || fail "CRITICAL: misc restore failed; RAM backup: $scratch/before"
    cmp -s "$target" "$scratch/before" || fail "CRITICAL: misc differs after restore; RAM backup: $scratch/before"
    fail 'BCB command write failed and was restored'
  fi
  sync
  echo "BCB command cleared; RAM backup: $scratch/before"
}
operation_lock() {
  exec 9>/run/recovery.lock
  flock -n 9 || fail 'Another recovery action is running'
}
check_ufs_disk() {
  device
  ufs_partition=$(readlink -f "${1:-/dev/disk/by-partlabel/userdata}") || fail 'Missing UFS partition'
  test -b "$ufs_partition" || fail 'UFS partition is absent'
  ufs_node=$(basename "$ufs_partition")
  case "$(readlink -f "/sys/class/block/$ufs_node")" in
    */1d84000.ufshc/*) ;;
    *) fail 'Partition is not on the Y700 UFS controller' ;;
  esac
  test -f "/sys/class/block/$ufs_node/partition" || fail 'Expected a partition'
  ufs_disk=/dev/$(basename "$(readlink -f "/sys/class/block/$ufs_node/..")")
  test -b "$ufs_disk" && test "$(blockdev --getss "$ufs_disk")" = 4096 || fail 'Unsupported UFS disk'
}
backlight_id() {
  device
  bus=""
  for adapter in /sys/class/i2c-dev/i2c-*; do
    test -e "$adapter" || continue
    if test "$(cat "$adapter/name")" = Geni-I2C &&
      test "$(basename "$(readlink -f "$adapter/device/of_node")")" = i2c@988000; then
      bus=${adapter##*-}
      break
    fi
  done
  test -n "$bus" || fail 'i2c@988000 adapter not found'
  id=$("${ASPHALT_I2CTRANSFER:-i2ctransfer}" -y "$bus" w1@0x11 0x01 r1)
  value=$((id))
  printf 'i2c@988000 is Linux I2C bus %s\n' "$bus"
  printf 'KTZ8866 DEVICE_ID: 0x%02x\n' "$value"
  test "$((value & 0x38))" = 32 || fail 'Unexpected KTZ8866 vendor ID bits'
}
plan_uefi() {
  test "$#" = 2 || fail 'Usage: recovery plan-uefi TOTAL_SIZE|existing'
  operation_lock
  gate
  slot_gate
  check_ufs_disk
  sfdisk --verify "$ufs_disk" >/dev/null || fail 'Current GPT verification failed'
  plan_dir=$(mktemp -d /run/asphalt-uefi-plan.XXXXXX)
  trap 'rm -rf "$plan_dir"' EXIT HUP INT TERM
  sfdisk --json "$ufs_disk" > "$plan_dir/gpt.json"
  sfdisk --dump "$ufs_disk" > "$plan_dir/gpt.sfdisk"
  /bin/asphalt-uefi-plan "$plan_dir/gpt.json" "$plan_dir/gpt.sfdisk" "$2" "$(uuidgen)" "$(uuidgen)" \
    --esp-bytes "${MOBILE_ESP_BYTES:-1073741824}" \
    --minimum-root-bytes "${MOBILE_MINIMUM_ROOT_BYTES:-17179869184}"
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
  backlight-id) backlight_id ;;
  plan-uefi) plan_uefi "$@" ;;
  format-root) exec /bin/asphalt-storage "$@" ;;
  reboot-system|reboot-recovery|reboot-bootloader|poweroff)
    test "${2:-}" = --confirm && test "$#" = 2 || fail "Usage: recovery $1 --confirm"
    operation_lock
    gate
    if test "$1" = reboot-system; then
      slot_gate
      clear_asphalt_request
    fi
    sync
    # The RAM initrd has no logind bus. The gate above excludes disk mounts,
    # so invoke the kernel shutdown path directly instead of systemctl's bus.
    case "$1" in
      reboot-system) exec /bin/systemctl --force --force reboot ;;
      reboot-recovery) exec /bin/systemctl --force --force --reboot-argument=recovery reboot ;;
      reboot-bootloader) exec /bin/systemctl --force --force --reboot-argument=bootloader reboot ;;
      poweroff) exec /bin/systemctl --force --force poweroff ;;
    esac
    ;;
  *) fail 'Unknown action; run recovery help' ;;
esac
