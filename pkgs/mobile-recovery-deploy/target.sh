#!/bin/sh
# Explicit target mounts and an isolated offline NixOS environment.
set -eu
fail() { echo "ERROR: $*" >&2; exit 1; }
ROOT=/mnt
STATE=/run/mobile-recovery/target
MOBILE_RECOVERY_LIBRARY_ONLY=1
export MOBILE_RECOVERY_LIBRARY_ONLY
. /etc/mobile-recovery-target
board=$(cat /etc/mobile-ram-recovery)
test -f /etc/initrd-release && test "$(id -u)" = 0 || fail 'Use root in RAM recovery'
case "$board" in
  polaris) . /bin/recovery; recovery_gate() { reboot_gate; } ;;
  clover|asphalt|sheng) . "/bin/$board-storage" ;;
  *) fail 'Unsupported recovery device' ;;
esac

checked_devices() {
  case "$board" in
    polaris)
      device
      polaris_partition_role userdata yes; root_device=$POLARIS_TARGET
      polaris_partition_role esp yes; esp_device=$POLARIS_TARGET
      ;;
    clover)
      root_partition; root_device=$root_target
      clover_partition_role system no; esp_device=$CLOVER_TARGET
      test "$(dirname "$(readlink -f "/sys/class/block/$(basename "$root_device")")")" = \
           "$(dirname "$(readlink -f "/sys/class/block/$(basename "$esp_device")")")" || fail 'ESP/root disks differ'
      ;;
    asphalt|sheng)
      linux_partition; root_device=$linux_target
      test "$(blkid -p -s PART_ENTRY_TYPE -o value "$root_device")" = 0fc63daf-8483-4772-8e79-3d69d8477de4 || fail 'Linux GPT type mismatch'
      check_ufs_partition linux-boot; esp_device=$partition
      test "/dev/$(basename "$(readlink -f "/sys/class/block/$(basename "$esp_device")/..")")" = "$linux_disk" || fail 'ESP/root disks differ'
      test "$(blkid -p -s PART_ENTRY_TYPE -o value "$esp_device")" = c12a7328-f81f-11d2-ba4b-00a0c93ec93b || fail 'ESP GPT type mismatch'
      test "${MOBILE_ESP_BYTES:-1073741824}" = 0 ||
        test "$(blockdev --getsize64 "$esp_device")" = "${MOBILE_ESP_BYTES:-1073741824}" || fail 'ESP size differs from configuration'
      ;;
  esac
  test -b "$root_device" && test -b "$esp_device" && test "$root_device" != "$esp_device" || fail 'Invalid root/ESP devices'
  test "$(blkid -p -s TYPE -o value "$root_device")" = ext4 || fail 'Expected ext4 root'
  if test "$board" != polaris; then
    test "$(blkid -p -s LABEL -o value "$root_device")" = "$TARGET_ROOT_LABEL" || fail 'Root filesystem label mismatch'
  fi
  test "$(blkid -p -s PART_ENTRY_NAME -o value "$esp_device")" = "$TARGET_ESP_LABEL" || fail 'ESP partition label mismatch'
  test "$(blkid -p -s TYPE -o value "$esp_device")" = vfat || fail 'Prepare the FAT boot partition first'
}
checked_mounts() {
  checked_devices
  test -f "$STATE" || fail 'Use recovery mount-target first'
  test "$(findmnt -rn -M "$ROOT" -o SOURCE)" = "$root_device" || fail 'Target root mount mismatch'
  test "$(findmnt -rn -M "$ROOT/boot" -o SOURCE)" = "$esp_device" || fail 'Target ESP mount mismatch'
  test "$(cat "$STATE")" = "$root_device $esp_device" || fail 'Mounted devices differ from the recorded session'
}
selected() {
  generation=$(readlink "$ROOT/nix/var/nix/profiles/system") || fail 'Missing installed system profile'
  case "$generation" in
    system-[0-9]*-link) system=$(readlink "$ROOT/nix/var/nix/profiles/$generation") ;;
    /nix/store/*) system=$generation ;;
    *) fail 'Invalid system profile' ;;
  esac
  case "$system" in /nix/store/*-nixos-system-"$TARGET_HOSTNAME"-*) ;; *) fail 'System belongs to another host' ;; esac
  test -f "$ROOT$system/mobile-efi" || fail 'Offline rebuild requires an installed EFI system'
  test -f "$ROOT/etc/NIXOS" && test -f "$ROOT/nix/var/nix/db/db.sqlite" || fail 'Installed NixOS database is missing'
}
require_rw() {
  for point in "$ROOT" "$ROOT/boot"; do
    case ",$(findmnt -rn -M "$point" -o OPTIONS)," in *,rw,*) ;; *) fail 'Unmount then mount-target --rw first' ;; esac
  done
}

# Re-entered only by unshare below. /run never exposes recovery's PID1 or Nix sockets.
if test "${1:-}" = --inside; then
  shift
  checked_mounts
  selected
  mount --make-rprivate /
  for name in dev proc sys run tmp; do
    test -d "$ROOT/$name" && test ! -L "$ROOT/$name" || fail "Unsafe target directory: $name"
  done
  mount --rbind /dev "$ROOT/dev"
  mount --rbind /proc "$ROOT/proc"
  mount --rbind /sys "$ROOT/sys"
  mount -t tmpfs -o mode=0755 tmpfs "$ROOT/run"
  mount -t tmpfs -o mode=1777 tmpfs "$ROOT/tmp"
  ln -s "$system" "$ROOT/run/current-system"
  mkdir -p "$ROOT/run/mobile-recovery/bin"
  cp /bin/mobile-offline-rebuild "$ROOT/run/mobile-recovery/bin/nixos-rebuild"
  chmod +x "$ROOT/run/mobile-recovery/bin/nixos-rebuild"
  export PATH=/run/mobile-recovery/bin:/run/current-system/sw/bin
  export NIX_REMOTE=local NIXOS_REBUILD_NO_SYSTEMD_RUN=1 NIXOS_SWITCH_USE_DIRTY_ENV=1
  export TMPDIR=/tmp HOME=/root
  unset NIX_DAEMON_SOCKET_PATH
  if test "$#" = 0; then
    exec /bin/chroot "$ROOT" "$system/sw/bin/bash" --noprofile --norc -i
  fi
  exec /bin/chroot "$ROOT" "$@"
fi

operation_lock
case "${1:-}" in
  mount-target)
    mode=${2:---ro}
    test "$#" -le 2 || fail 'Usage: recovery mount-target [--ro|--rw]'
    case "$mode" in --ro) root_options=ro,noload; esp_options=ro ;; --rw) root_options=rw; esp_options=rw ;; *) fail 'Choose --ro or --rw' ;; esac
    if mountpoint -q "$ROOT"; then
      checked_mounts
      echo 'Already mounted; unmount-target before changing access mode.'
      exit 0
    fi
    recovery_gate
    checked_devices
    e2fsck -fn "$root_device" || fail 'Root failed read-only fsck'
    fsck.fat -n "$esp_device" || fail 'FAT boot failed read-only fsck'
    test ! -L "$ROOT" || fail 'Unsafe mountpoint'
    mkdir -p "$ROOT" /run/mobile-recovery
    mount -t ext4 -o "$root_options" "$root_device" "$ROOT"
    trap 'umount /mnt 2>/dev/null || true' EXIT
    test -d "$ROOT/boot" && test ! -L "$ROOT/boot" || fail 'Target /boot must be a real directory'
    mount -t vfat -o "$esp_options,umask=0077" "$esp_device" "$ROOT/boot"
    printf '%s %s\n' "$root_device" "$esp_device" > "$STATE"
    trap - EXIT
    echo "Mounted $root_device at /mnt and $esp_device at /mnt/boot ($mode); no profile or boot files changed."
    ;;
  target-status)
    checked_mounts
    findmnt -R "$ROOT"
    selected
    printf 'Selected system: %s\n' "$system"
    ;;
  unmount-target)
    checked_devices
    test -f "$STATE" && test "$(cat "$STATE")" = "$root_device $esp_device" || fail 'No matching target session'
    test "$(findmnt -rn -M "$ROOT" -o SOURCE)" = "$root_device" || fail 'Target root mount mismatch'
    if mountpoint -q "$ROOT/boot"; then
      test "$(findmnt -rn -M "$ROOT/boot" -o SOURCE)" = "$esp_device" || fail 'Target ESP mount mismatch'
    fi
    systemctl stop mobile-recovery-store.service
    # No lazy/forced unmount: active sessions and transfers must finish first.
    sync
    if mountpoint -q "$ROOT/boot"; then umount "$ROOT/boot"; fi
    umount "$ROOT"
    rm -f "$STATE"
    ;;
  enter|rebuild)
    action=$1; shift
    checked_mounts
    selected
    if test "$action" = rebuild; then
      test "${1:-}" = boot || fail 'Offline rebuild supports boot only; switch/test would act on recovery'
      require_rw
      set -- /run/mobile-recovery/bin/nixos-rebuild "$@"
    fi
    # The lock stays held until the session ends; child mounts disappear on exit.
    unshare --mount --fork --propagation private /bin/mobile-recovery-target --inside "$@"
    ;;
  *) fail 'Use mount-target [--ro|--rw], target-status, unmount-target, enter, or rebuild boot ...' ;;
esac
