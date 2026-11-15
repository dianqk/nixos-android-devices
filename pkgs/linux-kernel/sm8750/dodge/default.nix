{
  baseKernel,
  lib,
  llvmPackages_23,
  openssl,
}:
{
  pname = "linux-dodge";
  inherit (baseKernel) version modDirVersion src;
  # Shared peripheral baseline, with common reductions and SM8750 selections.
  configfile = ../../sm8550/sheng/config.aarch64;
  patches = import ./series.nix;
  configOverrides = with lib.kernel; {
    CHARGER_NU1669 = yes;
    EFI = yes;
    EFI_STUB = yes;
    BLK_DEV_INITRD = yes;
    RD_GZIP = yes;
    RD_ZSTD = yes;
    DEVTMPFS = yes;
    DEVTMPFS_MOUNT = yes;
    ARM_PSCI_FW = yes;
    ARM_SCMI_PROTOCOL = yes;
    ARM_SCMI_TRANSPORT_SMC = yes;
    ARM_SCMI_TRANSPORT_MAILBOX = yes;
    QCOM_CPUCP_MBOX = yes;
    ARM_SCMI_PERF_DOMAIN = yes;
    ARM_SCMI_POWER_DOMAIN = yes;
    QCOM_CLK_RPMH = yes;
    QCOM_AOSS_QMP = yes;
    INTERCONNECT_QCOM_BCM_VOTER = yes;
    QCOM_SCM = yes;
    GUNYAH_WATCHDOG = yes;
    # Native hotplug ownership allows the root port to enter D3.
    HOTPLUG_PCI_PCIE = yes;
    FONTS = yes;
    FONT_TER16x32 = yes;
    SM_DISPCC_8750 = yes;
    SM_GPUCC_8750 = yes;
    SM_CAMCC_8750 = module;
    PHY_QCOM_MIPI_CSI2 = module;
    VIDEO_IMX615 = module;
    SM_VIDEOCC_8750 = module;
    CRYPTO_DEV_QCE = module;
    DRM_PANEL_ONEPLUS_DODGE = yes;
    TOUCHSCREEN_SYNA_TCM2 = module;
    SND_SOC_AW882308 = module;
    PINCTRL_LPASS_LPI = module;
    PINCTRL_SM8650_LPASS_LPI = module;
    QCOM_COMMAND_DB = yes;
    QCOM_SMEM = yes;
    QCOM_RPMH = yes;
    QCOM_RPMHPD = yes;
    REGULATOR_QCOM_RPMH = yes;
    PINCTRL_QCOM_SPMI_PMIC = yes;
    ARM_SMMU = yes;
    ARM_SMMU_QCOM = yes;
    USB_DWC3 = yes;
    USB_DWC3_QCOM = yes;
    USB_DWC3_DUAL_ROLE = yes;
    PHY_QCOM_M31_EUSB = yes;
    PHY_QCOM_EUSB2_REPEATER = yes;
    USB_CONFIGFS = yes;
    USB_CONFIGFS_ACM = yes;
    USB_F_ACM = yes;
    USB_U_SERIAL = yes;
  };
  dtbs = [
    "qcom/sm8750-oneplus-dodge.dtb"
    "qcom/sm8750-oneplus-dodge-recovery.dtb"
  ];
  nativeBuildInputs = [
    llvmPackages_23.lld
    openssl.out
  ];
  extraMakeFlags = [
    "HOSTLDFLAGS=-fuse-ld=lld -Wl,-rpath,${lib.getLib openssl}/lib"
    "DTC_FLAGS=-@"
  ];
  preBuild = ''
    export LD_LIBRARY_PATH="${openssl.out}/lib"
  '';
}
