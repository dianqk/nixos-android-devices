{
  bootActionProfile = "qcom-ab";
  deviceTree = "qcom/sm8550-xiaomi-sheng";
  patches = [
    ../patches/0001-pm8550b-repeater.patch
    ../patches/0002-snps-repeater-lifecycle.patch
    ../patches/0003-sm8550-unipro-clock.patch
    ../patches/0004-usb-cfg-noc-clock.patch
    ../patches/0005-unipro-divider.patch
    ./patches/0001-sheng-boot-dts.patch
    ./patches/0002-usb2-pipe-clock.patch
    ./patches/0003-sheng-abl-framebuffer.patch
  ];
  environment = ./sheng.env;
  android = {
    tagsOffset = "0x01e00000";
    maximumBytes = 201326592;
  };
  config = ''
    # The ARM64 header subtracts Snapdragon's 0x80000000 RAM base.
    # Generic PIE TEXT_BASE=0 otherwise wraps the advertised text_offset.
    CONFIG_TEXT_BASE=0x80000000
    # Explicit PMIC diagnostics support the PMK8550 reboot-reason path.
    CONFIG_CMD_PMIC=y
    CONFIG_DEFAULT_DEVICE_TREE="qcom/sm8550-xiaomi-sheng"
    CONFIG_ENV_DEFAULT_ENV_TEXT_FILE="board/qualcomm/sheng.env"
    # Skip the initial clear; console text and EFI can still write the framebuffer.
    CONFIG_NO_FB_CLEAR=y
    # Updates must preserve slot A and target B explicitly.
    # CONFIG_EFI_RUNTIME_UPDATE_CAPSULE is not set
    # CONFIG_EFI_CAPSULE_ON_DISK is not set
    # CONFIG_EFI_CAPSULE_FIRMWARE_RAW is not set
    # CONFIG_FASTBOOT_FLASH is not set
  '';
}
