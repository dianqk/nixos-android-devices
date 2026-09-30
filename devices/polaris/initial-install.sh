# Device adapter for mobile-install-initial. Sourced only in RAM recovery.
. /bin/recovery
recovery_gate() { reboot_gate; }
initial_devices() {
  ufs
  polaris_partition_role userdata yes; root_device=$POLARIS_TARGET
  polaris_partition_role esp yes; esp_device=$POLARIS_TARGET
  test "$POLARIS_PARTLABEL" = system || fail 'Expected physical system as FAT boot'
  polaris_partition_role boot; boot_device=$POLARIS_TARGET
}
initial_check_system() {
  chroot "$ROOT" "$initial_system/sw/bin/test" -f "$initial_system/polaris-storage-roles" || fail 'System storage contract is missing'
  recovery_hash=$(sha256sum /etc/polaris-storage-roles | cut -d ' ' -f 1)
  system_hash=$(chroot "$ROOT" "$initial_system/sw/bin/sha256sum" \
    "$initial_system/polaris-storage-roles" | cut -d ' ' -f 1)
  test "$system_hash" = "$recovery_hash" || fail 'System and recovery storage contracts differ'
}
