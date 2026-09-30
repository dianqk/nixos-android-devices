# Use the measured per-tablet eMMC contract, including its boot role.
CLOVER_STORAGE_ROLES=/bin/clover-storage-roles
CLOVER_PARTITION_CHECK=/bin/clover-check-partition
CLOVER_ROOT_LABEL=$TARGET_ROOT_LABEL

. /bin/clover-storage
initial_devices() {
  verify_gpt
  clover_partition_role userdata yes; root_device=$CLOVER_TARGET
  clover_partition_role system no; esp_device=$CLOVER_TARGET
  clover_partition_role boot no; boot_device=$CLOVER_TARGET
}
initial_check_system() { :; }
