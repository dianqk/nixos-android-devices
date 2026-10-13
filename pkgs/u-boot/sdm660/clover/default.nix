{
  bootActionProfile = "pon";
  deviceTree = "qcom/sdm660-xiaomi-clover";
  patches = [
    ../patches/0000-gdsc-flags.patch
    ../patches/0000-gdsc-poll.patch
    ../patches/0001-sdm660-gcc.patch
    ./patches/0001-clover-dts.patch
    ./patches/0002-clover-upstream-dt.patch
    ./patches/0003-clover-boot-constraints.patch
  ];
  environment = ./clover.env;
  android.secondOffset = "0x00f00000";
  config = ''
    CONFIG_DEFAULT_DEVICE_TREE="qcom/sdm660-xiaomi-clover"
    CONFIG_ENV_DEFAULT_ENV_TEXT_FILE="board/qualcomm/clover.env"
    # CONFIG_NO_FB_CLEAR is not set
    # Firmware updates remain an explicit checked operation.
    # CONFIG_EFI_RUNTIME_UPDATE_CAPSULE is not set
    # CONFIG_EFI_CAPSULE_ON_DISK is not set
    # CONFIG_EFI_CAPSULE_FIRMWARE_RAW is not set
  '';
}
