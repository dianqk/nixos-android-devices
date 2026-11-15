{
  standaloneBootImage = false; # Raw/ELF embedding inputs only; never a standalone flash role.
  bootChoiceContext = true;
  bootActionProfile = "qcom-reason"; # no legacy slot switch or confirmation writes
  deviceTree = "qcom/sm8750-oneplus-dodge";
  patches = [
    ./patches/0001-dodge-ram-console.patch
    ./patches/0002-sm8750-ufs-phy.patch
    ./patches/0003-sm8750-tlmm.patch
    ./patches/0004-dodge-ufs-efi.patch
    ./patches/0005-efi-fdt-probe.patch
    ./patches/0006-dodge-pmk8550.patch
    ./patches/0007-dodge-usb-shutdown.patch
    ./patches/0008-dodge-inherited-framebuffer.patch
    ./patches/0009-dodge-usb-supplies.patch
    ./patches/0010-rpmh-ftsmps525-upper-range.patch
    ./patches/0011-rpmh-parent-initial-voltage.patch
    ./patches/0012-dodge-map-loader-initrd.patch
    ./patches/0013-dodge-loadable-transfer-buffer.patch
    ./patches/0014-dodge-boot-menu-keys.patch
    ./patches/0015-dodge-reserve-rmtfs.patch
    ./patches/0016-boot-choice-context.patch
    ./patches/0017-boot-choice-durable-io.patch
    ./patches/0018-efi-file-open-errors.patch
  ];
  extraFirmwareFiles = [
    "lib/efi_loader/helloworld.efi"
    "lib/efi_loader/dodge_probe.efi"
    "lib/efi_loader/fdt_probe.efi"
    "u-boot.sym"
    "u-boot"
    "u-boot.map"
  ];
  environment = ./dodge.env;
  payload = "u-boot.bin";
  config = ''
    CONFIG_QCOM_DODGE=y
    CONFIG_EFI_BOOT_CHOICE_CONTEXT=y
    CONFIG_CMD_PMIC=y
    CONFIG_CMD_CACHE=y
    CONFIG_LOG_DEFAULT_LEVEL=6
    CONFIG_SCSI=y
    # CONFIG_SCSI_READ_ONLY is not set
    CONFIG_UFS=y
    CONFIG_UFS_QCOM=y
    CONFIG_UFS_REQUIRE_LEGACY=y
    CONFIG_CMD_UFS=y
    CONFIG_CMD_SCSI=y
    CONFIG_PINCTRL_QCOM_SM8750=y
    CONFIG_EFI_LOADER=y
    CONFIG_EFI_BINARY_EXEC=y
    CONFIG_CMD_BOOTEFI=y
    CONFIG_BOOTEFI_HELLO_COMPILE=y
    CONFIG_EFI_DODGE_PROBE_COMPILE=y
    CONFIG_LMB_LIMIT_DMA_BELOW_RAM_TOP=y
    CONFIG_USB_FUNCTION_FASTBOOT=y
    CONFIG_FASTBOOT_BUF_ADDR=0xc0000000
    CONFIG_FASTBOOT_BUF_SIZE=0x4000000
    CONFIG_SYS_DEVICE_NULLDEV=y
    CONFIG_CMD_HASH=y
    CONFIG_HASH_VERIFY=y
    CONFIG_SHA256=y
    # CONFIG_EFI_BOOTMGR is not set
    # CONFIG_EFI_VARIABLE_FILE_STORE is not set
    # CONFIG_EFI_VARIABLE_SF_STORE is not set
    # CONFIG_EFI_LOADER_BOUNCE_BUFFER is not set
    # CONFIG_FASTBOOT_UUU_SUPPORT is not set
    # CONFIG_FASTBOOT_OEM_RUN is not set
    # CONFIG_FASTBOOT_CMD_OEM_CONSOLE is not set
    # CONFIG_CMD_GPT is not set
    # CONFIG_CMD_PART_CLONE is not set
    # CONFIG_CMD_NVEDIT_EFI is not set
    CONFIG_FAT_WRITE=y
    CONFIG_EFI_BOOT_CHOICE_DURABLE_IO=y

    CONFIG_DEFAULT_DEVICE_TREE="qcom/sm8750-oneplus-dodge"
    CONFIG_TEXT_BASE=0x80000000
    CONFIG_OF_SEPARATE=y
    CONFIG_NR_DRAM_BANKS=64
    CONFIG_SYS_MALLOC_LEN=0x1000000
    CONFIG_CLK_QCOM_SM8750=y
    CONFIG_PHY_QCOM_M31_EUSB2=y
    CONFIG_ENV_DEFAULT_ENV_TEXT_FILE="board/qualcomm/dodge.env"
    CONFIG_BOOTDELAY=5
    CONFIG_USE_PREBOOT=y
    # CONFIG_BOOT_RETRY is not set
    # CONFIG_RETRY_BOOTCMD is not set
    # CONFIG_PANIC_HANG is not set
    # CONFIG_FASTBOOT_FLASH is not set
    # CONFIG_CMD_DFU is not set
    # CONFIG_DFU is not set
    # CONFIG_CMD_USB_MASS_STORAGE is not set
    # CONFIG_CMD_MMC is not set
    # CONFIG_MMC is not set
    # CONFIG_EFI_CAPSULE_ON_DISK is not set
    # CONFIG_EFI_CAPSULE_FIRMWARE_RAW is not set
    # CONFIG_EFI_RUNTIME_UPDATE_CAPSULE is not set
    CONFIG_VIDEO=y
    CONFIG_VIDEO_SIMPLE=y
    CONFIG_CONSOLE_NORMAL=y
    CONFIG_VIDEO_BPP32=y
    CONFIG_VIDEO_FONT_16X32=y
    CONFIG_SYS_WHITE_ON_BLACK=y
    # CONFIG_VIDEO_FONT_8X16 is not set
    # CONFIG_VIDEO_LOGO is not set
    CONFIG_BUTTON_GPIO=y
    CONFIG_BUTTON_QCOM_PMIC=y
    CONFIG_BUTTON_KEYBOARD=y
    CONFIG_BUTTON_REMAP_PHONE_KEYS=y
    CONFIG_DM_KEYBOARD=y
    # CONFIG_SYSRESET_QCOM_PSHOLD is not set
  '';
}
