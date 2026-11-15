# SM7475 (Snapdragon 7+ Gen 2) U-Boot configuration. The platform drivers
# come from the board's imported series (SM8450/SM8475 "cape" clocks,
# pinctrl, UFS PHY and memory handling); see marble/README.md.
''
  CONFIG_CLK_QCOM_SM8450=y
  CONFIG_PINCTRL_QCOM_SM8450=y
  # Use the /memory banks ABL fills in for the fitted RAM variant.
  CONFIG_QCOM_PREFER_PREVBL_MEMORY=y
  # ARM64 Image text_offset for ABL's raw Image path (PIE TEXT_BASE 0).
  CONFIG_LNX_KRNL_IMG_TEXT_OFFSET_BASE=0x0
  CONFIG_EFI_LOADER=y
  CONFIG_CMD_BOOTEFI=y
  CONFIG_CMD_PART=y
  CONFIG_CMD_FAT=y
  CONFIG_FS_FAT=y
  CONFIG_FS_FAT_HANDLE_SECTOR_SIZE_MISMATCH=y
''
