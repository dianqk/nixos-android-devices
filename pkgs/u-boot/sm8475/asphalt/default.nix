{
  bootActionProfile = "qcom-ab";
  # Permit the observed zero-metadata layout on these LUNs for B confirmation.
  # Valid GPTs remain supported and fully checked on other Asphalt units.
  bootActionConfirmationNonGptLunMask = 192; # bits 6 and 7
  bootActionAndroidNonGptLunMask = 192;
  bootActionChargerConfirmationPath = "/EFI/android-devices/charger.efi";
  deviceTree = "qcom/sm8475-lenovo-asphalt";
  patches = [
    ../patches/0001-sm8450-gcc.patch
    ../patches/0002-sm8450-pinctrl.patch
    ../patches/0003-sm8475-ufs-phy.patch
    ../patches/0004-sm8475-boot-dependencies.patch
    ../patches/0005-asphalt-eusb2-repeater.patch
    ../patches/0006-sm8475-ufs-overlay.patch
    ../patches/0007-sm8450-unipro-divider.patch
    ../patches/0008-sm8475-ufs-hs-series.patch
    ./patches/0001-asphalt-boot-dts.patch
    ./patches/0002-volume-up-pinctrl.patch
  ];
  chargerEnvironment = true;
  environment = ./asphalt.env;
  compressKernel = false;
  # Preserve the larger payload extent used for repeated ABL boots.
  # 3 MiB failed intermittently; this is an empirical workaround, not a
  # proven minimum threshold or a change to the ARM64 memory-size field.
  minimumKernelBytes = 41289792;
  android = {
    headerVersion = 2;
    dtbPlacement = "boot-image";
    dtbOffset = "0x01f00000";
    maximumBytes = 100663296;
  };
  config = ''
    # ARM64 Image text_offset = TEXT_BASE - Snapdragon's 0x80000000 base.
    # The generic PIE default (0) underflows this field for ABL's raw Image path.
    CONFIG_TEXT_BASE=0x80000000
    # Explicit PMIC reads/writes allow verification of the board's reboot reason.
    CONFIG_CMD_PMIC=y
    CONFIG_DEFAULT_DEVICE_TREE="qcom/sm8475-lenovo-asphalt"
    CONFIG_ENV_DEFAULT_ENV_TEXT_FILE="board/qualcomm/asphalt.env"
    # CONFIG_NO_FB_CLEAR is not set
    # Firmware is updated explicitly through the checked B-slot workflow.
    # CONFIG_EFI_RUNTIME_UPDATE_CAPSULE is not set
    # CONFIG_EFI_CAPSULE_ON_DISK is not set
    # CONFIG_EFI_CAPSULE_FIRMWARE_RAW is not set
  '';
}
