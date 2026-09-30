# Validate the prepared Linux layout; only boot_b is ever selected.
SHENG_ROOT_LABEL=$TARGET_ROOT_LABEL
. /bin/sheng-storage
initial_devices() {
  sheng_slot_gate
  linux_partition; root_device=$linux_target
  check_ufs_partition linux-boot; esp_device=$partition
  test "$(blkid -p -s PART_ENTRY_TYPE -o value "$esp_device" | tr A-F a-f)" = \
    c12a7328-f81f-11d2-ba4b-00a0c93ec93b || fail 'Expected standard ESP GPT type'
  test "${MOBILE_ESP_BYTES:-1073741824}" = 0 ||
    test "$(blockdev --getsize64 "$esp_device")" = "${MOBILE_ESP_BYTES:-1073741824}" || fail 'ESP size mismatch'
  check_ufs_partition boot_b; boot_device=$partition
}
initial_check_system() { :; }
