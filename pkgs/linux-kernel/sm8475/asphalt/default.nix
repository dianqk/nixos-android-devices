{
  baseKernel,
  lib,
  llvmPackages_23,
  openssl,
}:
{
  pname = "linux-asphalt";
  inherit (baseKernel) version modDirVersion src;
  configfile = ./kernel.config;
  patches = import ./series.nix;
  configOverrides = with lib.kernel; {
    SM_CAMCC_8450 = yes;
    I2C_QCOM_CCI = yes;
    V4L_PLATFORM_DRIVERS = yes;
    VIDEO_QCOM_CAMSS = yes;
    VIDEO_ASPHALT_SENSORS = yes;
    REGULATOR_WL2864C = yes;
  };
  dtbs = [ "qcom/sm8475-lenovo-asphalt.dtb" ];
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
    grep -q '^CONFIG_BLK_DEV_INITRD=y$' build/.config
    grep -q '^CONFIG_RD_ZSTD=y$' build/.config
    grep -q '^CONFIG_PINCTRL_SM8475=y$' build/.config
    grep -q '^CONFIG_I2C_QCOM_GENI=y$' build/.config
    grep -q '^CONFIG_PHY_SNPS_EUSB2=y$' build/.config
    grep -q '^CONFIG_PHY_QCOM_I2C_EUSB2_REPEATER=y$' build/.config
    grep -q '^CONFIG_USB_DWC3=y$' build/.config
    grep -q '^CONFIG_USB_DWC3_QCOM=y$' build/.config
    grep -q '^CONFIG_USB_ROLE_SWITCH=y$' build/.config
    grep -q '^CONFIG_PHY_QCOM_QMP_USB=y$' build/.config
    grep -q '^CONFIG_USB_CONFIGFS_F_FS=y$' build/.config
    grep -q '^CONFIG_QCOM_Q6V5_PAS=m$' build/.config
    grep -q '^CONFIG_QRTR_SMD=y$' build/.config
    grep -q '^CONFIG_QCOM_PMIC_GLINK=m$' build/.config
    grep -q '^CONFIG_UCSI_PMIC_GLINK=m$' build/.config
    grep -q '^CONFIG_SND_SOC_SC8280XP=m$' build/.config
    grep -q '^CONFIG_SND_SOC_CS35L45_I2C=m$' build/.config
    grep -q '^CONFIG_SCSI_UFS_QCOM=y$' build/.config
    grep -q '^CONFIG_SM_DISPCC_8450=y$' build/.config
    grep -q '^CONFIG_SM_VIDEOCC_8450=y$' build/.config
    grep -q '^CONFIG_VIDEO_QCOM_IRIS=y$' build/.config
    grep -q '^CONFIG_DRM_MSM=y$' build/.config
    grep -q '^CONFIG_DRM_MSM_DP=y$' build/.config
    grep -q '^CONFIG_PHY_QCOM_QMP_COMBO=y$' build/.config
    grep -q '^CONFIG_TYPEC_MUX_FSA4480=m$' build/.config
    grep -q '^CONFIG_TYPEC_DP_ALTMODE=m$' build/.config
    grep -q '^CONFIG_DRM_PANEL_NOVATEK_NT36523=y$' build/.config
    grep -q '^CONFIG_BACKLIGHT_KTZ8866=y$' build/.config
    grep -q '^CONFIG_KEYBOARD_GPIO=y$' build/.config
    grep -q '^CONFIG_INPUT_PM8941_PWRKEY=y$' build/.config
    grep -q '^CONFIG_SPI_QCOM_GENI=y$' build/.config
    grep -q '^CONFIG_TOUCHSCREEN_NOVATEK_NT36523N_SPI=y$' build/.config
    grep -q '^CONFIG_POWER_SEQUENCING_QCOM_WCN=y$' build/.config
    grep -q '^CONFIG_PCI_PWRCTRL_PWRSEQ=y$' build/.config
    grep -q '^CONFIG_ATH11K_PCI=y$' build/.config
    grep -q '^CONFIG_BT=y$' build/.config
    grep -q '^CONFIG_BT_HCIUART_SERDEV=y$' build/.config
    grep -q '^CONFIG_BT_HCIUART_QCA=y$' build/.config
    grep -q '^CONFIG_PHY_QCOM_QMP_PCIE=y$' build/.config
    grep -q '^CONFIG_MODULE_COMPRESS_ZSTD=y$' build/.config
    ! grep -q '^CONFIG_MODULE_COMPRESS_XZ=y$' build/.config
    grep -q '^CONFIG_CC_IS_CLANG=y$' build/.config
    grep -q '^CONFIG_LD_IS_LLD=y$' build/.config
  '';
}
