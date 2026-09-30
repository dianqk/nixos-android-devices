#!/bin/sh
# Resolve the stock Polaris GPT by its partition names on the built-in UFS.
# The caller supplies fail(); the module supplies POLARIS_DEFAULT_ROOT_LABEL.
polaris_partition_role() {
  role=$1
  require_fs=${2:-no}
  case "$role" in
    userdata)
      POLARIS_PARTLABEL=userdata
      POLARIS_FS_TYPE=ext4
      POLARIS_FS_LABEL=${POLARIS_DEFAULT_ROOT_LABEL:-NIXOS}
      ;;
    esp)
      POLARIS_PARTLABEL=system
      POLARIS_FS_TYPE=vfat
      POLARIS_FS_LABEL=NIXOS_BOOT
      ;;
    boot|recovery)
      POLARIS_PARTLABEL=$role
      POLARIS_FS_TYPE=
      POLARIS_FS_LABEL=
      ;;
    misc)
      POLARIS_PARTLABEL=misc
      POLARIS_FS_TYPE=
      POLARIS_FS_LABEL=
      ;;
    *) fail "Unknown Polaris storage role: $role" ;;
  esac
  POLARIS_FS_UUID=

  tr '\000' '\n' < /proc/device-tree/compatible | grep -qx xiaomi,polaris || fail 'Not a Polaris device'
  link="/dev/disk/by-partlabel/$POLARIS_PARTLABEL"
  test -L "$link" || fail "$role GPT partition name is missing"
  POLARIS_TARGET=$(readlink -f "$link")
  test -b "$POLARIS_TARGET" || fail "$role partition is not a block device"
  block_name=$(basename "$POLARIS_TARGET")
  block_sysfs=$(readlink -f "/sys/class/block/$block_name")
  case "$block_sysfs" in
    /sys/devices/platform/soc@0/1d84000.ufshc/*) ;;
    *) fail "$role partition is not on the built-in UFS" ;;
  esac
  test -f "/sys/class/block/$block_name/partition" || fail "$role target is not a partition"
  test "$(blkid -p -s PART_ENTRY_SCHEME -o value "$POLARIS_TARGET")" = gpt || fail "$role is not a GPT partition"
  test "$(blkid -p -s PART_ENTRY_NAME -o value "$POLARIS_TARGET")" = "$POLARIS_PARTLABEL" || fail "$role GPT name mismatch"

  # udev's by-partlabel symlink can pick either device when names are repeated.
  matches=0
  for candidate in /sys/class/block/*; do
    test -f "$candidate/partition" || continue
    case "$(readlink -f "$candidate")" in
      /sys/devices/platform/soc@0/1d84000.ufshc/*) ;;
      *) continue ;;
    esac
    if test "$(blkid -p -s PART_ENTRY_NAME -o value "/dev/${candidate##*/}")" = "$POLARIS_PARTLABEL"; then
      matches=$((matches + 1))
    fi
  done
  test "$matches" = 1 || fail "$role GPT name is not unique on the built-in UFS"

  POLARIS_PARTUUID=$(blkid -p -s PART_ENTRY_UUID -o value "$POLARIS_TARGET" | tr A-F a-f)
  POLARIS_PART_NUMBER=$(blkid -p -s PART_ENTRY_NUMBER -o value "$POLARIS_TARGET")
  POLARIS_PART_OFFSET=$(blkid -p -s PART_ENTRY_OFFSET -o value "$POLARIS_TARGET")
  POLARIS_PART_BYTES=$(blockdev --getsize64 "$POLARIS_TARGET")
  test -n "$POLARIS_PARTUUID" && test -n "$POLARIS_PART_NUMBER" && test -n "$POLARIS_PART_OFFSET" || fail "$role GPT identity is incomplete"
  test "$POLARIS_PART_BYTES" -gt 0 || fail "$role partition is empty"
  if test "$role" = misc; then
    test "$POLARIS_PART_BYTES" = 4194304 || fail 'misc must be 4 MiB for the boot request writer'
  fi
  if test "$require_fs" = yes; then
    test -n "$POLARIS_FS_TYPE" || fail "$role has no filesystem contract"
    test "$(blkid -p -s TYPE -o value "$POLARIS_TARGET")" = "$POLARIS_FS_TYPE" || fail "$role filesystem type mismatch"
    test "$(blkid -p -s LABEL -o value "$POLARIS_TARGET")" = "$POLARIS_FS_LABEL" || fail "$role filesystem label mismatch"
  fi
  export POLARIS_TARGET POLARIS_PARTUUID POLARIS_PARTLABEL POLARIS_PART_NUMBER
  export POLARIS_PART_OFFSET POLARIS_PART_BYTES POLARIS_FS_TYPE POLARIS_FS_LABEL POLARIS_FS_UUID
}
