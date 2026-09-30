#!/bin/sh
# Checked storage helpers for RAM recovery.
set -eu
: "${ASPHALT_SYSTEM_HOSTNAME:=asphalt}"
: "${ASPHALT_ROOT_LABEL:=NIXOS}"
fail() { echo "ERROR: $*" >&2; exit 1; }
asphalt_slot_gate() {
  if grep -Eq '(^|[[:space:]])(androidboot|boot)\.slot_suffix=_a([[:space:]]|$)' /proc/cmdline; then
    fail 'Run the Y700 recovery from slot B'
  fi
  if test -r /proc/bootconfig &&
    grep -Eq '^[[:space:]]*(androidboot|boot)\.slot_suffix[[:space:]]*=[[:space:]]*"?_a"?[[:space:]]*$' /proc/bootconfig; then
    fail 'Run the Y700 recovery from slot B'
  fi
  if ! grep -Eq '(^|[[:space:]])(androidboot|boot)\.slot_suffix=_b([[:space:]]|$)' /proc/cmdline &&
    { test ! -r /proc/bootconfig ||
      ! grep -Eq '^[[:space:]]*(androidboot|boot)\.slot_suffix[[:space:]]*=[[:space:]]*"?_b"?[[:space:]]*$' /proc/bootconfig; }; then
    fail 'Cannot verify active slot B'
  fi
}
recovery_gate() {
  tr '\000' '\n' </proc/device-tree/compatible | grep -qx lenovo,asphalt || fail 'Not a Y700 2023'
  test "$(cat /proc/1/comm)" = systemd && test -f /etc/initrd-release &&
    test "$(cat /etc/mobile-ram-recovery)" = asphalt || fail 'Use the Y700 RAM recovery'
  asphalt_slot_gate
  while read -r _ _ mm rest; do
    test ! -e "/sys/dev/block/$mm" || fail 'Unmount all block filesystems first'
    fs=${rest#* - }; fs=${fs%% *}
    case "$fs" in
      rootfs|ramfs|tmpfs|devtmpfs|proc|sysfs|devpts|cgroup|cgroup2|securityfs|debugfs|tracefs|configfs|functionfs|pstore|mqueue|bpf|fusectl) ;;
      *) fail 'Unmount non-RAM filesystems first' ;;
    esac
  done </proc/self/mountinfo
  test "$(wc -l </proc/swaps)" -le 1 || fail 'Disable swap first'
}
operation_lock() {
  exec 9>/run/recovery.lock
  flock -n 9 || fail 'Another recovery action is running'
}
check_ufs_partition() {
  expected=$1
  partition=$(readlink -f "/dev/disk/by-partlabel/$expected") || fail "$expected is absent"
  test -b "$partition" || fail "$expected is not a block partition"
  test "$(blkid -p -s PART_ENTRY_NAME -o value "$partition")" = "$expected" ||
    fail "$expected GPT label mismatch"
  case "$(readlink -f "/sys/class/block/$(basename "$partition")")" in
    */1d84000.ufshc/*) ;;
    *) fail "$expected is not on the Y700 UFS controller" ;;
  esac
}
linux_partition() {
  check_ufs_partition linux
  test "$(blkid -p -s PART_ENTRY_NUMBER -o value "$partition")" -gt 0 ||
    fail 'Invalid Linux GPT entry number'
  test "$(blkid -p -s PART_ENTRY_TYPE -o value "$partition" | tr A-F a-f)" = \
    0fc63daf-8483-4772-8e79-3d69d8477de4 || fail 'Linux GPT type mismatch'
  linux_bytes=$(blockdev --getsize64 "$partition")
  test "$linux_bytes" -ge "${MOBILE_MINIMUM_ROOT_BYTES:-17179869184}" || fail 'Linux partition is smaller than the configured minimum'
  linux_target=$partition
  linux_disk=/dev/$(basename "$(readlink -f "/sys/class/block/$(basename "$linux_target")/..")")
  test -b "$linux_disk" && test "$(blockdev --getss "$linux_disk")" = 4096 ||
    fail 'Linux root is not on a 4096-byte-sector UFS disk'
  sfdisk --verify "$linux_disk" >/dev/null || fail 'Linux root GPT verification failed'
  sfdisk --json "$linux_disk" | jq -e --arg disk "$linux_disk" --arg node "$linux_target" \
    --argjson espBytes "${MOBILE_ESP_BYTES:-1073741824}" \
    -f /bin/mobile-linux-layout.jq >/dev/null || fail 'Unsupported Linux/userdata GPT layout'
}
format_root() {
  if test "$#" != 2 || { test "$2" != --check && test "$2" != --confirm; }; then
    fail 'Usage: recovery format-root --check|--confirm'
  fi
  operation_lock
  recovery_gate
  linux_partition
  echo "Linux root: $linux_target ($linux_bytes bytes); new ext4 label: $ASPHALT_ROOT_LABEL"
  if test "$2" = --check; then
    echo 'Check only; --confirm erases the Linux partition.'
    return
  fi
  mke2fs -F -t ext4 -m 0 -L "$ASPHALT_ROOT_LABEL" "$linux_target"
  sync
  linux_partition
  test "$(blkid -p -s TYPE -o value "$linux_target")" = ext4 &&
    test "$(blkid -p -s LABEL -o value "$linux_target")" = "$ASPHALT_ROOT_LABEL" ||
    fail 'Formatted Linux root identity mismatch'
  e2fsck -fn "$linux_target" || fail 'Formatted Linux root failed read-only fsck'
  echo 'Linux root formatted and verified.'
}
mount_root() {
  mode=$1
  linux_partition
  test "$(blkid -p -s TYPE -o value "$linux_target")" = ext4 &&
    test "$(blkid -p -s LABEL -o value "$linux_target")" = "$ASPHALT_ROOT_LABEL" ||
    fail 'Linux root filesystem identity mismatch'
  e2fsck -fn "$linux_target" >/tmp/asphalt-root-fsck.log 2>&1 ||
    fail 'Linux root failed read-only fsck'
  mkdir -p /recovery
  mount -t ext4 -o "$mode" "$linux_target" /recovery
}
validate_manifest() {
  manifest=$1
  system=$2
  test -f "$manifest" && test ! -L "$manifest" && test -s "$manifest" ||
    fail 'Missing closure manifest'
  case "$system" in
    /nix/store/*-nixos-system-"$ASPHALT_SYSTEM_HOSTNAME"-*) ;;
    *) fail 'System path does not match the configured Y700 host name' ;;
  esac
  found=false
  while read -r nar_hash path extra; do
    test -z "${extra:-}" || fail 'Malformed closure manifest'
    case "$nar_hash" in sha256:*) ;; *) fail 'Malformed NAR hash' ;; esac
    case "$path" in /nix/store/*) ;; *) fail 'Manifest path is outside /nix/store' ;; esac
    test "$path" = "$system" && found=true
  done < "$manifest"
  $found || fail 'Selected system is missing from the manifest'
}
selected_system() {
  profile=/recovery/nix/var/nix/profiles/system
  generation=$(readlink "$profile") || fail 'System profile is unreadable'
  case "$generation" in system-[0-9]*-link) ;; *) fail 'Invalid profile generation' ;; esac
  selected=$(readlink "$(dirname "$profile")/$generation") || fail 'Profile generation is unreadable'
  case "$selected" in
    /nix/store/*-nixos-system-"$ASPHALT_SYSTEM_HOSTNAME"-*) printf '%s\n' "$selected" ;;
    *) fail 'Selected profile is not a Y700 system' ;;
  esac
}
test "${MOBILE_RECOVERY_LIBRARY_ONLY:-0}" != 1 || return 0
case "${1:-}" in
  format-root) format_root "$@" ;;
  *) fail 'Use format-root; install EFI generations with recovery rebuild boot' ;;
esac
