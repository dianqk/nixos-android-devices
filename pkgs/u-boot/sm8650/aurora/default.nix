{
  # ABL uses Qualcomm GPT slot flags and UFS boot LUN 2 for slot B.
  # Confirm B only after loading the configured EFI executable from the ESP.
  bootActionProfile = "qcom-ab";
  bootActionChargerConfirmationPath = "/EFI/android-devices/charger.efi";
  chargerEnvironment = true;
  deviceTree = "qcom/sm8650-xiaomi-aurora";
  patches = [
    ../../sm8550/patches/0001-pm8550b-repeater.patch
    ../../sm8550/patches/0002-snps-repeater-lifecycle.patch
    ./patches/0001-aurora-boot-dts.patch
    ./patches/0002-sm8650-boot-clocks.patch
    ./patches/0003-ufs-opp-table.patch
    ./patches/0004-fdt-copy-destination.patch
    ./patches/0005-aurora-abl-framebuffer.patch
    ./patches/0006-aurora-buttons.patch
  ];
  environment = ./aurora.env;
  android = {
    tagsOffset = "0x01e00000";
    osVersion = "14.0.0";
    osPatchLevel = "2026-02-01";
    maximumBytes = 104857600;
  };
  config = ''
    CONFIG_TEXT_BASE=0x80000000
    CONFIG_DEFAULT_DEVICE_TREE="qcom/sm8650-xiaomi-aurora"
    CONFIG_ENV_DEFAULT_ENV_TEXT_FILE="board/qualcomm/aurora.env"
    CONFIG_OF_LIBFDT_OVERLAY=y
    CONFIG_CMD_BOOTI=y
    CONFIG_CMD_PMIC=y
    CONFIG_NO_FB_CLEAR=y
    # Reset on panic; do not require physical access to leave a firmware panic.
    # CONFIG_PANIC_HANG is not set
    # CONFIG_EFI_RUNTIME_UPDATE_CAPSULE is not set
    # CONFIG_EFI_CAPSULE_ON_DISK is not set
    # CONFIG_EFI_CAPSULE_FIRMWARE_RAW is not set
    # CONFIG_FASTBOOT_FLASH is not set
    CONFIG_BUTTON_CMD=y
  '';
}
