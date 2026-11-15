{
  # Stock ABL on slot B loads this header-v4 image: gzip(u-boot.bin) with
  # the board DTB appended after the gzip stream, no ramdisk. ABL matches
  # the appended DTB's msm-id/board-id; u-boot.bin also carries the same
  # DTB as its control tree and takes RAM banks from the DTB ABL passes.
  #
  # ABL uses Qualcomm GPT slot flags; slot B's XBL is UFS boot LUN 2
  # (xbl_b on LUN 2) and boot_b lives on LUN 4. After loading
  # /EFI/BOOT/BOOTAA64.EFI from the linux-boot ESP, U-Boot sets only
  # boot_b's successful bit (both GPT copies of LUN 4), so ABL stops
  # counting down B's retries. Every enabled LUN carries a GPT (LUN 0-5),
  # so no zero-metadata exception is configured. No charger entry yet.
  bootActionProfile = "qcom-ab";
  deviceTree = "qcom/sm8475-xiaomi-marble";
  patches = [
    ./patches/0001-mach-snapdragon-fix-reserved-memory-carveout.patch
    ./patches/0002-mach-snapdragon-move-memory-parsing-to-its-own-file.patch
    ./patches/0003-clk-qcom-sm8450-add-GCC-clock-driver-for-SM8450-SM84.patch
    ./patches/0004-clk-stub-add-SM8450-RPMh-clock-controller.patch
    ./patches/0005-pinctrl-qcom-sm8450-add-TLMM-driver-for-SM8450-SM847.patch
    ./patches/0006-gpio-qcom_spmi_gpio-add-PM8350-PM8350B-and-PM8350C.patch
    ./patches/0007-power-regulator-qcom-rpmh-add-PM8350-regulators.patch
    ./patches/0008-phy-qcom-qmp-ufs-add-SM8475-support.patch
    ./patches/0009-phy-qcom-snps-eusb2-bring-up-NXP-PTN3222-repeater.patch
    ./patches/0010-usb-gadget-f_acm-add-option-not-to-wait-for-host-con.patch
    ./patches/0011-mach-snapdragon-add-support-for-SM8450-and-SM8475-pl.patch
    ./patches/0012-arm64-dts-qcom-add-Device-Tree-for-Xiaomi-Poco-F5-ma.patch
    ./patches/0013-board-qualcomm-marble-add-board-config-and-boot-envi.patch
    ./patches/0014-mach-snapdragon-select-the-DSI-panel-variant-ABL-rep.patch
  ];
  environment = ./marble.env;
  payload = "u-boot.bin";
  appendDeviceTree = true;
  emptyRamdisk = true;
  android = {
    headerVersion = 4;
    osVersion = "16.0.0";
    osPatchLevel = "2026-08";
    # boot_b capacity (192 MiB) from the device GPT.
    maximumBytes = 201326592;
  };
  config = ''
    CONFIG_DEFAULT_DEVICE_TREE="qcom/sm8475-xiaomi-marble"
    CONFIG_ENV_DEFAULT_ENV_TEXT_FILE="board/qualcomm/marble.env"
    CONFIG_USB_GADGET=y
    CONFIG_USB_GADGET_DOWNLOAD=y
    CONFIG_USB_FUNCTION_ACM=y
    CONFIG_CMD_READ=y
    CONFIG_OF_LIBFDT_OVERLAY=y
    CONFIG_CMD_PMIC=y
    CONFIG_BUTTON_CMD=y
    # The Fastboot flash backend is MMC; never point it at internal UFS.
    # CONFIG_FASTBOOT_FLASH is not set
    # Firmware is replaced only through the checked B-slot workflow.
    # CONFIG_EFI_RUNTIME_UPDATE_CAPSULE is not set
    # CONFIG_EFI_CAPSULE_ON_DISK is not set
    # CONFIG_EFI_CAPSULE_FIRMWARE_RAW is not set
  '';
}
