#!/bin/sh
# Checked storage helpers for RAM recovery.
set -eu
: "${CLOVER_SYSTEM_HOSTNAME:=clover}"
: "${CLOVER_ROOT_LABEL:=NIXOS}"
fail() { echo "ERROR: $*" >&2; exit 1; }
# shellcheck disable=SC1090
. "${CLOVER_STORAGE_ROLES:?Clover storage contract is required}"
recovery_gate() {
  tr '\000' '\n' </proc/device-tree/compatible | grep -qx xiaomi,clover-lte || fail 'Not a Clover LTE'
  test "$(cat /proc/1/comm)" = systemd && test -f /etc/initrd-release &&
    test "$(cat /etc/mobile-ram-recovery)" = clover || fail 'Use the Clover LTE RAM recovery'
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
verify_gpt() {
  clover_partition_role userdata no
  disk=/dev/$(basename "$(readlink -f "/sys/class/block/$(basename "$CLOVER_TARGET")/..")")
  test -b "$disk" || fail 'Clover eMMC is absent'
  sfdisk --verify "$disk" >/dev/null || fail 'Clover GPT verification failed'
}
root_partition() {
  clover_partition_role userdata no
  root_target=$CLOVER_TARGET
  root_bytes=$CLOVER_PART_BYTES
  test "$root_bytes" -ge 17179869184 || fail 'Clover userdata is smaller than 16 GiB'
}
format_root() {
  if test "$#" != 2 || { test "$2" != --check && test "$2" != --confirm; }; then
    fail 'Usage: recovery format-root --check|--confirm'
  fi
  operation_lock
  recovery_gate
  verify_gpt
  root_partition
  echo "Clover userdata root: $root_target ($root_bytes bytes); new ext4 label: $CLOVER_ROOT_LABEL"
  if test "$2" = --check; then
    echo 'Check only; --confirm erases the existing userdata filesystem.'
    return
  fi
  if test -n "${CLOVER_ROOT_UUID:-}"; then
    set -- -U "$CLOVER_ROOT_UUID"
  else
    set --
  fi
  mke2fs -F -t ext4 -m 0 -L "$CLOVER_ROOT_LABEL" "$@" "$root_target"
  sync
  root_partition
  test "$(blkid -p -s TYPE -o value "$root_target")" = ext4 &&
    test "$(blkid -p -s LABEL -o value "$root_target")" = "$CLOVER_ROOT_LABEL" ||
    fail 'Formatted root identity mismatch'
  e2fsck -fn "$root_target" || fail 'Formatted root failed read-only fsck'
  echo 'Clover userdata root formatted and verified.'
}
mount_root() {
  mode=$1
  root_partition
  test "$(blkid -p -s TYPE -o value "$root_target")" = ext4 &&
    test "$(blkid -p -s LABEL -o value "$root_target")" = "$CLOVER_ROOT_LABEL" ||
    fail 'Clover root filesystem identity mismatch'
  e2fsck -fn "$root_target" >/tmp/clover-root-fsck.log 2>&1 ||
    fail 'Clover root failed read-only fsck'
  mkdir -p /recovery
  mount -t ext4 -o "$mode" "$root_target" /recovery
}
validate_manifest() {
  manifest=$1
  system=$2
  test -f "$manifest" && test ! -L "$manifest" && test -s "$manifest" ||
    fail 'Missing closure manifest'
  case "$system" in
    /nix/store/*-nixos-system-"$CLOVER_SYSTEM_HOSTNAME"-*) ;;
    *) fail 'System path does not match the configured Clover LTE host name' ;;
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
    /nix/store/*-nixos-system-"$CLOVER_SYSTEM_HOSTNAME"-*) printf '%s\n' "$selected" ;;
    *) fail 'Selected profile is not a Clover LTE system' ;;
  esac
}
test "${MOBILE_RECOVERY_LIBRARY_ONLY:-0}" != 1 || return 0
case "${1:-}" in
  format-root) format_root "$@" ;;
  *) fail 'Use format-root; install EFI generations with recovery rebuild boot' ;;
esac
