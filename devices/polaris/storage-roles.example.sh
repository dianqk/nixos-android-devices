#!/bin/sh
# Copy this file outside the repository, replace every CHANGE_ME value with
# measurements from one phone, then pass it as storageRolesFile to both builds.
# The caller supplies fail(). A missing value always rejects the operation.
polaris_partition_role() {
  role=$1
  require_fs=${2:-no}
  case "$role" in
    userdata)
      POLARIS_PARTUUID=CHANGE_ME_USERDATA_PARTUUID
      POLARIS_PARTLABEL=CHANGE_ME_USERDATA_GPT_LABEL
      POLARIS_PART_NUMBER=CHANGE_ME_USERDATA_PART_NUMBER
      POLARIS_PART_OFFSET=CHANGE_ME_USERDATA_START_SECTOR
      POLARIS_PART_BYTES=CHANGE_ME_USERDATA_BYTES
      POLARIS_FS_TYPE=ext4
      POLARIS_FS_LABEL=CHANGE_ME_USERDATA_FS_LABEL
      POLARIS_FS_UUID=CHANGE_ME_USERDATA_FS_UUID
      ;;
    esp)
      POLARIS_PARTUUID=CHANGE_ME_SYSTEM_PARTUUID
      POLARIS_PARTLABEL=system
      POLARIS_PART_NUMBER=CHANGE_ME_SYSTEM_PART_NUMBER
      POLARIS_PART_OFFSET=CHANGE_ME_SYSTEM_START_SECTOR
      POLARIS_PART_BYTES=CHANGE_ME_SYSTEM_BYTES
      POLARIS_FS_TYPE=vfat
      POLARIS_FS_LABEL=NIXOS_BOOT
      POLARIS_FS_UUID=CHANGE_ME_FAT_UUID
      ;;
    boot|recovery|misc)
      case "$role" in
        boot)
          POLARIS_PARTUUID=CHANGE_ME_BOOT_PARTUUID
          POLARIS_PARTLABEL=CHANGE_ME_BOOT_GPT_LABEL
          POLARIS_PART_NUMBER=CHANGE_ME_BOOT_PART_NUMBER
          POLARIS_PART_OFFSET=CHANGE_ME_BOOT_START_SECTOR
          POLARIS_PART_BYTES=CHANGE_ME_BOOT_BYTES
          ;;
        recovery)
          POLARIS_PARTUUID=CHANGE_ME_RECOVERY_PARTUUID
          POLARIS_PARTLABEL=CHANGE_ME_RECOVERY_GPT_LABEL
          POLARIS_PART_NUMBER=CHANGE_ME_RECOVERY_PART_NUMBER
          POLARIS_PART_OFFSET=CHANGE_ME_RECOVERY_START_SECTOR
          POLARIS_PART_BYTES=CHANGE_ME_RECOVERY_BYTES
          ;;
        misc)
          POLARIS_PARTUUID=CHANGE_ME_MISC_PARTUUID
          POLARIS_PARTLABEL=CHANGE_ME_MISC_GPT_LABEL
          POLARIS_PART_NUMBER=CHANGE_ME_MISC_PART_NUMBER
          POLARIS_PART_OFFSET=CHANGE_ME_MISC_START_SECTOR
          POLARIS_PART_BYTES=CHANGE_ME_MISC_BYTES
          ;;
      esac
      POLARIS_FS_TYPE=
      POLARIS_FS_LABEL=
      POLARIS_FS_UUID=
      ;;
    *) fail "Unknown Polaris storage role: $role" ;;
  esac

  case "$POLARIS_PARTUUID $POLARIS_PARTLABEL $POLARIS_PART_NUMBER $POLARIS_PART_OFFSET $POLARIS_PART_BYTES $POLARIS_FS_LABEL $POLARIS_FS_UUID" in
    *CHANGE_ME*) fail "Complete the $role storage contract before use" ;;
  esac
  POLARIS_TARGET=$(readlink -f "/dev/disk/by-partuuid/$POLARIS_PARTUUID")
  test -b "$POLARIS_TARGET" || fail "$role partition is not enumerated"
  test "$(blkid -p -s PART_ENTRY_UUID -o value "$POLARIS_TARGET" | tr A-F a-f)" = "$POLARIS_PARTUUID" || fail "$role GPT UUID mismatch"
  test "$(blkid -p -s PART_ENTRY_NAME -o value "$POLARIS_TARGET")" = "$POLARIS_PARTLABEL" || fail "$role GPT label mismatch"
  test "$(blkid -p -s PART_ENTRY_NUMBER -o value "$POLARIS_TARGET")" = "$POLARIS_PART_NUMBER" || fail "$role GPT number mismatch"
  test "$(blkid -p -s PART_ENTRY_OFFSET -o value "$POLARIS_TARGET")" = "$POLARIS_PART_OFFSET" || fail "$role GPT offset mismatch"
  test "$(blockdev --getsize64 "$POLARIS_TARGET")" = "$POLARIS_PART_BYTES" || fail "$role partition size mismatch"
  case "$(readlink -f "/sys/class/block/$(basename "$POLARIS_TARGET")")" in
    /sys/devices/platform/soc@0/1d84000.ufshc/*) ;;
    *) fail "$role partition is on the wrong controller" ;;
  esac
  if test -e "/dev/disk/by-partlabel/$POLARIS_PARTLABEL" || test -L "/dev/disk/by-partlabel/$POLARIS_PARTLABEL"; then
    test "$(readlink -f "/dev/disk/by-partlabel/$POLARIS_PARTLABEL")" = "$POLARIS_TARGET" || fail "$role GPT label and UUID disagree"
  fi
  if test "$require_fs" = yes; then
    test -n "$POLARIS_FS_TYPE" || fail "$role has no filesystem contract"
    test "$(blkid -p -s TYPE -o value "$POLARIS_TARGET")" = "$POLARIS_FS_TYPE" || fail "$role filesystem type mismatch"
    test "$(blkid -p -s LABEL -o value "$POLARIS_TARGET")" = "$POLARIS_FS_LABEL" || fail "$role filesystem label mismatch"
    test "$(blkid -p -s UUID -o value "$POLARIS_TARGET" | tr A-F a-f)" = "$POLARIS_FS_UUID" || fail "$role filesystem UUID mismatch"
  fi
  export POLARIS_TARGET POLARIS_PARTUUID POLARIS_PARTLABEL POLARIS_PART_NUMBER
  export POLARIS_PART_OFFSET POLARIS_PART_BYTES POLARIS_FS_TYPE POLARIS_FS_LABEL POLARIS_FS_UUID
}
