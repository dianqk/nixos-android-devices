#!/bin/sh
# shellcheck disable=SC1090
. "${CLOVER_PARTITION_CHECK:?Clover partition validator is required}"
# Copy outside this repository and replace each CHANGE_ME field with values
# measured on the target Clover LTE tablet. The caller provides fail().
clover_partition_role() {
  role=$1
  require_fs=${2:-no}
  case "$role" in
    userdata)
      CLOVER_PARTUUID=CHANGE_ME_USERDATA_PARTUUID
      CLOVER_PART_NUMBER=CHANGE_ME_USERDATA_NUMBER
      CLOVER_PART_OFFSET=CHANGE_ME_USERDATA_START_SECTOR
      CLOVER_PART_BYTES=CHANGE_ME_USERDATA_BYTES
      ;;
    system)
      CLOVER_PARTUUID=CHANGE_ME_SYSTEM_PARTUUID
      CLOVER_PART_NUMBER=CHANGE_ME_SYSTEM_NUMBER
      CLOVER_PART_OFFSET=CHANGE_ME_SYSTEM_START_SECTOR
      CLOVER_PART_BYTES=CHANGE_ME_SYSTEM_BYTES
      ;;
    boot)
      CLOVER_PARTUUID=CHANGE_ME_BOOT_PARTUUID
      CLOVER_PART_NUMBER=CHANGE_ME_BOOT_NUMBER
      CLOVER_PART_OFFSET=CHANGE_ME_BOOT_START_SECTOR
      CLOVER_PART_BYTES=CHANGE_ME_BOOT_BYTES
      ;;
    recovery)
      CLOVER_PARTUUID=CHANGE_ME_RECOVERY_PARTUUID
      CLOVER_PART_NUMBER=CHANGE_ME_RECOVERY_NUMBER
      CLOVER_PART_OFFSET=CHANGE_ME_RECOVERY_START_SECTOR
      CLOVER_PART_BYTES=CHANGE_ME_RECOVERY_BYTES
      ;;
    misc)
      CLOVER_PARTUUID=CHANGE_ME_MISC_PARTUUID
      CLOVER_PART_NUMBER=CHANGE_ME_MISC_NUMBER
      CLOVER_PART_OFFSET=CHANGE_ME_MISC_START_SECTOR
      CLOVER_PART_BYTES=CHANGE_ME_MISC_BYTES
      ;;
    *) fail "Unknown Clover partition role: $role" ;;
  esac
  case "$CLOVER_PARTUUID $CLOVER_PART_NUMBER $CLOVER_PART_OFFSET $CLOVER_PART_BYTES" in
    *CHANGE_ME*) fail "Complete the $role storage contract before use" ;;
  esac
  clover_check_partition "$role" "$require_fs"
}
