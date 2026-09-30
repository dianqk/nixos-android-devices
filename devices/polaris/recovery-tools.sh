#!/bin/sh
# Self-contained stage1 helper; explicit boot actions only change misc command.
set -eu
: "${POLARIS_SYSTEM_HOSTNAME:=polaris}"
fail() { echo "ERROR: $*" >&2; exit 1; }
# The selected storage role resolver is installed at this path.
. /etc/polaris-storage-roles
device() {
  tr '\000' '\n' < /proc/device-tree/compatible | grep -qx xiaomi,polaris || fail 'Not Polaris'
}
ufs() {
  device
  controller=/sys/bus/platform/devices/1d84000.ufshc
  echo on > "$controller/power/control"
  echo 0 > "$controller/clkgate_enable"
  echo 0 > "$controller/clkscale_enable"
  test "$(cat "$controller/power/control")" = on
  test "$(cat "$controller/clkgate_enable")" = 0
  test "$(cat "$controller/clkscale_enable")" = 0
}
root_partition() { polaris_partition_role userdata yes; target=$POLARIS_TARGET; }
# Hardshutdown bypasses service shutdown: never leave a disk mount or swap active.
reboot_gate() {
  device
  test "$(cat /proc/1/comm)" = systemd && test -f /etc/initrd-release &&
    test "$(cat /etc/mobile-ram-recovery)" = polaris || fail 'Use only in the RAM recovery stage1'
  while read -r _ _ mm rest; do
    test ! -e "/sys/dev/block/$mm" || fail 'Unmount ALL block filesystems before leaving recovery'
    case "$rest" in
      *' - rootfs '*|*' - ramfs '*|*' - tmpfs '*|*' - devtmpfs '*|\
      *' - proc '*|*' - sysfs '*|*' - devpts '*|*' - cgroup '*|*' - cgroup2 '*|\
      *' - securityfs '*|*' - debugfs '*|*' - tracefs '*|*' - configfs '*|\
      *' - functionfs '*|*' - pstore '*|*' - mqueue '*|*' - bpf '*|*' - fusectl '*) ;;
      *) fail 'Unmount non-RAM filesystems before leaving recovery' ;;
    esac
  done < /proc/self/mountinfo
  test "$(wc -l < /proc/swaps)" -le 1 || fail 'Disable swap before leaving recovery'
}

# Caller has validated and locked misc. Preserve every byte outside command[32].
# Backup is intentionally in RAM: do not claim it survives the requested reboot.
write_boot_request() {
  request=$1
  scratch=$(mktemp -d /tmp/polaris-bcb.XXXXXX)
  chmod 700 "$scratch"
  dd if="$target" of="$scratch/misc.img" bs=1048576 count=4 2>/dev/null
  test "$(wc -c < "$scratch/misc.img")" = 4194304 || fail 'Short misc backup'
  cmp -s "$target" "$scratch/misc.img" || fail 'Misc backup verification failed'
  dd if=/dev/zero of="$scratch/empty" bs=32 count=1 2>/dev/null
  cp "$scratch/empty" "$scratch/recovery"
  printf boot-recovery | dd of="$scratch/recovery" conv=notrunc 2>/dev/null
  dd if="$scratch/misc.img" of="$scratch/old-command" bs=32 count=1 2>/dev/null
  if ! cmp -s "$scratch/old-command" "$scratch/empty" &&
     ! cmp -s "$scratch/old-command" "$scratch/recovery"; then
    fail "Unknown misc command; refusing to overwrite. RAM backup: $scratch/misc.img"
  fi
  case "$request" in
    system) command_file=$scratch/empty ;;
    recovery) command_file=$scratch/recovery ;;
    *) fail 'Invalid boot request' ;;
  esac
  cp "$scratch/misc.img" "$scratch/expected"
  dd if="$command_file" of="$scratch/expected" bs=32 count=1 conv=notrunc 2>/dev/null
  if cmp -s "$scratch/misc.img" "$scratch/expected"; then
    rm -r "$scratch"
    return
  fi
  # Detect concurrent changes before writing; the lock serializes our CLI/GUI.
  cmp -s "$target" "$scratch/misc.img" || fail 'Misc changed before write'
  if ! dd if="$command_file" of="$target" bs=32 count=1 conv=notrunc,fsync 2>/dev/null ||
     ! cmp -s "$target" "$scratch/expected"; then
    # Restore command only; never overwrite unrelated metadata changed elsewhere.
    dd if="$scratch/old-command" of="$target" bs=32 count=1 conv=notrunc,fsync 2>/dev/null ||
      fail "CRITICAL: command restore failed. RAM backup: $scratch/misc.img"
    cmp -s "$target" "$scratch/misc.img" ||
      fail "CRITICAL: misc differs after restore. RAM backup: $scratch/misc.img"
    fail "Boot request write failed and was restored. RAM backup: $scratch/misc.img"
  fi
  sync
  echo "Boot request verified; temporary RAM backup: $scratch/misc.img"
}

operation_lock() {
  mkdir -p /run/lock
  exec 9>/run/lock/polaris-recovery-boot.lock
  flock -n 9 || fail 'Another recovery storage or boot action is running'
}

validate_deploy_manifest() {
  manifest=$1
  new_system=$2
  test -f "$manifest" && test ! -L "$manifest" || fail 'Deployment manifest is not a regular file'
  test "$(wc -l < "$manifest")" -gt 0 || fail 'Deployment manifest is empty'
  found_system=false
  while read -r hash path extra; do
    test -z "${extra:-}" || fail 'Malformed deployment manifest'
    case "$hash" in sha256:*) ;; *) fail 'Malformed NAR hash' ;; esac
    case "$path" in /nix/store/*) ;; *) fail 'Manifest path is outside /nix/store' ;; esac
    test "$path" = "$new_system" || continue
    found_system=true
  done < "$manifest"
  $found_system || fail 'Selected system is absent from deployment manifest'
  case "$new_system" in /nix/store/*-nixos-system-"$POLARIS_SYSTEM_HOSTNAME"-*) ;; *) fail 'Invalid Polaris system path' ;; esac
}

mount_userdata_plain() {
  mode=$1
  ufs
  root_partition
  mm=$(cat "/sys/class/block/$(basename "$target")/dev")
  awk -v mm="$mm" '$3 == mm { found=1 } END { exit !found }' /proc/self/mountinfo && fail 'Userdata is already mounted'
  e2fsck -fn "$target" >/tmp/polaris-deploy-e2fsck.log 2>&1 || fail 'Read-only userdata fsck failed'
  mkdir -p /recovery
  mount -t ext4 -o "$mode" "$target" /recovery
  if test "${MOBILE_RECOVERY_LIBRARY_ONLY:-0}" != 1 &&
    test -e /recovery/var/lib/mobile-offline-deploy/pending; then
    umount /recovery
    fail 'Resume the pending recovery deploy before other storage operations'
  fi
}

selected_system() {
  selected_profile_path=/recovery/nix/var/nix/profiles/system
  selected_generation_name=$(readlink "$selected_profile_path") || fail 'Selected userdata profile is unreadable'
  case "$selected_generation_name" in
    system-[0-9]*-link) ;;
    *) fail 'Selected userdata profile has an invalid generation target' ;;
  esac
  selected_store_path=$(readlink "$(dirname "$selected_profile_path")/$selected_generation_name") ||
    fail 'Selected userdata generation is unreadable'
  case "$selected_store_path" in
    /nix/store/*-nixos-system-"$POLARIS_SYSTEM_HOSTNAME"-*)
      test -f "/recovery$selected_store_path/mobile-efi" || fail 'Polaris requires an EFI system'
      printf '%s\n' "$selected_store_path" ;;
    *) fail 'Selected userdata generation is not a Polaris system' ;;
  esac
}

# First installation operates inside the existing GPT userdata entry.  The
# format and install commands are separate so a check cannot silently erase it.
format_userdata() {
  if test "$#" != 2 || { test "$2" != --check && test "$2" != --confirm; }; then
    fail 'Usage: recovery format-userdata --check|--confirm'
  fi
  operation_lock
  reboot_gate
  ufs
  polaris_partition_role userdata no
  test "$POLARIS_FS_TYPE" = ext4 || fail 'First install requires an ext4 userdata contract'
  case "$POLARIS_FS_LABEL" in ''|*[!A-Za-z0-9._-]*) fail 'Invalid userdata filesystem label' ;; esac
  test "$(printf %s "$POLARIS_FS_LABEL" | wc -c)" -le 16 || fail 'Userdata filesystem label is too long'
  if test -n "$POLARIS_FS_UUID"; then
    printf '%s\n' "$POLARIS_FS_UUID" |
      grep -Eiq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' ||
      fail 'Invalid userdata filesystem UUID'
  fi
  format_target=$POLARIS_TARGET
  format_mm=$(cat "/sys/class/block/$(basename "$format_target")/dev")
  awk -v mm="$format_mm" '$3 == mm { found=1 } END { exit !found }' /proc/self/mountinfo &&
    fail 'Userdata is mounted'
  echo "Existing userdata: $format_target ($POLARIS_PART_BYTES bytes, GPT $POLARIS_PARTUUID)"
  echo "New ext4 identity: $POLARIS_FS_LABEL $POLARIS_FS_UUID"
  if test "$2" = --check; then
    echo 'Check only; --confirm irreversibly erases userdata without changing GPT.'
    return
  fi
  if test -n "$POLARIS_FS_UUID"; then
    mke2fs -F -t ext4 -m 0 -L "$POLARIS_FS_LABEL" -U "$POLARIS_FS_UUID" "$format_target"
  else
    mke2fs -F -t ext4 -m 0 -L "$POLARIS_FS_LABEL" "$format_target"
  fi
  sync
  polaris_partition_role userdata yes
  test "$POLARIS_TARGET" = "$format_target" || fail 'Userdata target changed after formatting'
  e2fsck -fn "$format_target" || fail 'Formatted userdata failed read-only fsck'
  echo 'Userdata formatted and verified; prepare-boot then install-initial before booting the installed system.'
}

boot_action() {
  action=$1
  test "$#" = 2 && test "$2" = --confirm || fail "Usage: recovery $action --confirm"
  operation_lock
  reboot_gate
  if test "$action" = reboot-system; then
    mount_userdata_plain ro,noload
    umount /recovery
  fi
  ufs
  if test "$action" != poweroff; then
    polaris_partition_role misc
    target=$POLARIS_TARGET
    case "$action" in
      reboot-recovery) write_boot_request recovery ;;
      reboot-system|reboot-bootloader) write_boot_request system ;;
      *) fail 'Unknown boot action' ;;
    esac
  fi
  sync
  case "$action" in
    reboot-system|reboot-recovery) exec /bin/systemctl --force --force reboot ;;
    reboot-bootloader) exec /bin/systemctl --force --force --reboot-argument=bootloader reboot ;;
    poweroff) exec /bin/systemctl --force --force poweroff ;;
  esac
}

test "${MOBILE_RECOVERY_LIBRARY_ONLY:-0}" != 1 || return 0
export POLARIS_SYSTEM_HOSTNAME POLARIS_REQUIRE_RADIO_IDENTITY
case "${1:-}" in
  install-initial) exec /bin/mobile-install-initial "$@" ;;
  mount-target|unmount-target|target-status|enter|rebuild) exec /bin/mobile-recovery-target "$@" ;;
  prepare-boot) shift; exec /bin/polaris-prepare-boot "$@" ;;
  deploy-query|deploy-offline|deploy-check-boot) exec /bin/mobile-recovery-deploy "$@" ;;
  reboot-system) /bin/mobile-recovery-deploy deploy-check-boot ;;

esac
case "${1:-help}" in
  help) cat /etc/recovery-help ;;
  reboot-system|reboot-recovery|reboot-bootloader|poweroff) boot_action "$@" ;;
  status) uname -a; cat /proc/uptime; lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTLABEL,PARTUUID,MOUNTPOINTS ;;
  safe-ufs) operation_lock; ufs ;;
  mount-ro)
    operation_lock
    ufs; root_partition
    mountpoint -q /recovery && fail '/recovery already mounted'
    mkdir -p /recovery
    mount -t ext4 -o ro,noload "$target" /recovery
    ;;
  unmount) operation_lock; umount /recovery; sync ;;
  check-root)
    operation_lock
    ufs; root_partition
    mm=$(cat "/sys/class/block/$(basename "$target")/dev")
    awk -v mm="$mm" '$3 == mm { found=1 } END { exit !found }' /proc/self/mountinfo && fail 'Root is mounted'
    e2fsck -fn "$target"
    ;;
  format-userdata) format_userdata "$@" ;;
  *) fail 'Unknown action; run recovery help' ;;
esac
