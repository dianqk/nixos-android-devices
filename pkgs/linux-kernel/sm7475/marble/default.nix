{
  baseKernel,
  lib,
  llvmPackages_23,
  openssl,
}:
{
  pname = "linux-marble";
  inherit (baseKernel) version modDirVersion src;
  # Same SoC family as the Y700 2023 (SM8475); its baseline keeps the shared
  # peripheral selection. Board differences are the overrides below.
  configfile = ../../sm8475/asphalt/kernel.config;
  patches = import ./series.nix;
  configOverrides = with lib.kernel; {
    # The RAM recovery carries no kernel modules: everything needed for the
    # console, storage and USB gadget is built in.
    PHY_NXP_PTN3222 = yes;
    TOUCHSCREEN_GOODIX_BERLIN_CORE = yes;
    TOUCHSCREEN_GOODIX_BERLIN_SPI = yes;
    # Both M16T panel variants; U-Boot selects one in the DTB from ABL's
    # msm_drm.dsi_display0.
    DRM_PANEL_XIAOMI_M16T_36_02_0A = yes;
    DRM_PANEL_XIAOMI_M16T_36_0D_0B = yes;
    INPUT_QCOM_SPMI_HAPTICS = module;
    SND_SOC_AW88261 = module;
    # Microphones: WCD9385 over SoundWire through the LPASS RX/TX/VA
    # macros (VA only supplies their fsgen clock; no DMICs).
    SOUNDWIRE_QCOM = module;
    SND_SOC_WCD938X_SDW = module;
    SND_SOC_LPASS_RX_MACRO = module;
    SND_SOC_LPASS_TX_MACRO = module;
    SND_SOC_LPASS_VA_MACRO = module;
    # WSA/WSA2 macros: the LPASS codec macro votes (PRM clocks 0x314-0x317)
    # match iLtanaka's working 7.2.8 configuration.
    SND_SOC_LPASS_WSA_MACRO = module;
    QCOM_IPA = module;
    # Camera clock controller: the board DT has camcc consumers (CCI, the
    # IMX355 node). Without a driver, fw_devlink keeps the rpmhpd and GCC
    # sync_state() pending and rpmhpd holds every rail at its highest
    # corner, so CX never collapses in suspend. Built in as on Asphalt.
    SM_CAMCC_8450 = yes;
    # Cameras: CAMSS and the four sensor drivers as modules (the CCI is
    # already a module).
    MEDIA_CAMERA_SUPPORT = yes;
    V4L_PLATFORM_DRIVERS = yes;
    VIDEO_CAMERA_SENSOR = yes;
    VIDEO_QCOM_CAMSS = module;
    VIDEO_IMX355 = module;
    VIDEO_GC02M1 = module;
    VIDEO_S5K3P9 = module;
    VIDEO_OV64B40 = module;
    # /sys/power/pm_test, pm_wakeup_irq and pm_print_times for the suspend
    # bring-up (staged no-sleep tests, wake IRQ reporting).
    PM_DEBUG = yes;
    PM_SLEEP_DEBUG = yes;
    # Legible console on the 1080x2400 panel.
    FONTS = yes;
    FONT_TER16x32 = yes;
  };
  dtbs = [ "qcom/sm8475-xiaomi-marble.dtb" ];
  nativeBuildInputs = [
    llvmPackages_23.lld
    openssl.out
  ];
  extraMakeFlags = [
    "HOSTLDFLAGS=-fuse-ld=lld -Wl,-rpath,${lib.getLib openssl}/lib"
  ];
  preBuild = ''
    export LD_LIBRARY_PATH="${openssl.out}/lib"
  '';
  postConfigure = ''
    for symbol in BLK_DEV_INITRD RD_ZSTD DEVTMPFS PINCTRL_SM8475 SM_GCC_8450 \
      SM_DISPCC_8450 SM_GPUCC_8450 INTERCONNECT_QCOM_SM8450 \
      INTERCONNECT_QCOM_OSM_L3 SCSI_UFSHCD SCSI_UFS_QCOM PHY_QCOM_QMP_UFS \
      SCSI BLK_DEV_SD PHY_SNPS_EUSB2 PHY_NXP_PTN3222 USB_DWC3 USB_DWC3_QCOM \
      USB_ROLE_SWITCH USB_CONFIGFS USB_CONFIGFS_ACM USB_CONFIGFS_NCM \
      DRM_SIMPLEDRM DRM_MSM DRM_PANEL_XIAOMI_M16T_36_02_0A \
      DRM_PANEL_XIAOMI_M16T_36_0D_0B \
      BACKLIGHT_CLASS_DEVICE FRAMEBUFFER_CONSOLE FONT_TER16x32 \
      SPI_QCOM_GENI TOUCHSCREEN_GOODIX_BERLIN_SPI KEYBOARD_GPIO \
      INPUT_PM8941_PWRKEY PINCTRL_QCOM_SPMI_PMIC PSTORE PSTORE_RAM \
      EXT4_FS VFAT_FS ARM_QCOM_CPUFREQ_HW SM_CAMCC_8450 PM_DEBUG PM_SLEEP_DEBUG CC_IS_CLANG LD_IS_LLD; do
      grep -q "^CONFIG_$symbol=y$" "$buildRoot"/.config
    done
    grep -q '^CONFIG_INPUT_QCOM_SPMI_HAPTICS=m$' "$buildRoot"/.config
    # PMK8350 RTC alarm (0079) for RTC wake.
    grep -q '^CONFIG_RTC_DRV_PM8XXX=m$' "$buildRoot"/.config
    for symbol in SND_SOC_AW88261 SOUNDWIRE_QCOM SND_SOC_WCD938X_SDW \
      SND_SOC_LPASS_RX_MACRO SND_SOC_LPASS_TX_MACRO SND_SOC_LPASS_VA_MACRO \
      SND_SOC_LPASS_WSA_MACRO \
      SND_SOC_SC8280XP SND_SOC_QDSP6_APM_LPASS_DAI SND_SOC_QDSP6_PRM_LPASS_CLOCKS; do
      grep -q "^CONFIG_$symbol=m$" "$buildRoot"/.config
    done
    for symbol in I2C_QCOM_CCI VIDEO_QCOM_CAMSS VIDEO_IMX355 VIDEO_GC02M1 \
      VIDEO_S5K3P9 VIDEO_OV64B40; do
      grep -q "^CONFIG_$symbol=m$" "$buildRoot"/.config
    done
  '';
}
