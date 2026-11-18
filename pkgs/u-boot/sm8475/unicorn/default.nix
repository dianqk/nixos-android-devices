{
  bootActionProfile = "qcom-ab";
  deviceTree = "qcom/sm8475-xiaomi-unicorn";
  patches = [
    ../patches/0001-sm8450-gcc.patch
    ../patches/0002-sm8450-pinctrl.patch
    ../patches/0003-sm8475-ufs-phy.patch
    ../patches/0004-sm8475-boot-dependencies.patch
    ../patches/0005-asphalt-eusb2-repeater.patch
    ../patches/0006-sm8475-ufs-overlay.patch
    ../patches/0007-sm8450-unipro-divider.patch
    ../patches/0008-sm8475-ufs-hs-series.patch
    ./patches/0001-unicorn-boot-dts.patch
    ./patches/0002-dwc3-peripheral-handoff.patch
  ];
  environment = ./unicorn.env;
  # Use ABL's raw ARM64 path and reserve a full payload extent, including
  # U-Boot's runtime/BSS space. Device acceptance is recorded in the guide.
  compressKernel = false;
  minimumKernelBytes = 41289792;
  android = {
    headerVersion = 2;
    dtbPlacement = "boot-image";
    dtbOffset = "0x01f00000";
    maximumBytes = 201326592;
  };
  config = ''
    # ARM64 text_offset is TEXT_BASE minus Snapdragon's 0x80000000 RAM base.
    # The generic PIE default underflows; match the working Linux offset zero.
    CONFIG_TEXT_BASE=0x80000000
    CONFIG_DEFAULT_DEVICE_TREE="qcom/sm8475-xiaomi-unicorn"
    CONFIG_ENV_DEFAULT_ENV_TEXT_FILE="board/qualcomm/unicorn.env"
    CONFIG_CMD_PMIC=y
    CONFIG_RESET_TO_RETRY=y
    # CONFIG_PANIC_HANG is not set
    # CONFIG_FASTBOOT_FLASH is not set
    # CONFIG_FASTBOOT_OEM_RUN is not set
    # CONFIG_EFI_RUNTIME_UPDATE_CAPSULE is not set
    # CONFIG_EFI_CAPSULE_ON_DISK is not set
    # CONFIG_EFI_CAPSULE_FIRMWARE_RAW is not set
  '';
}
