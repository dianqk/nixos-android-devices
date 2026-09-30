{
  baseKernel,
  lib,
  llvmPackages_23,
  openssl,
}:
{
  pname = "linux-polaris";
  inherit (baseKernel) version modDirVersion src;
  configfile = ./kernel.config;
  configOverrides =
    import ../../qualcomm-trim.nix { inherit lib; }
    // import ./radio-trim.nix { inherit lib; }
    // {
      QCOM_IPA = lib.kernel.yes;
      VIDEO_IMX363 = lib.kernel.module;
      VIDEO_OV5675 = lib.kernel.module;
    };
  patches = import ./series.nix;
  dtbs = [ "qcom/sdm845-xiaomi-polaris.dtb" ];
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
    grep -q '^CONFIG_SCSI_UFS_QCOM=y$' build/.config
    grep -q '^CONFIG_USB_DWC3=y$' build/.config
    grep -q '^CONFIG_USB_DWC3_QCOM=y$' build/.config
    grep -q '^CONFIG_USB_CONFIGFS_F_FS=y$' build/.config
    grep -q '^CONFIG_RD_ZSTD=y$' build/.config
    grep -q '^CONFIG_MODULE_COMPRESS_ZSTD=y$' build/.config
    ! grep -q '^CONFIG_MODULE_COMPRESS_XZ=y$' build/.config
    grep -q '^CONFIG_QCOM_Q6V5_MSS=y$' build/.config
    grep -q '^CONFIG_QCOM_IPA=y$' build/.config
    grep -q '^CONFIG_BATTERY_PMI8998_FG=y$' build/.config
    grep -q '^CONFIG_CHARGER_QCOM_SMB2=y$' build/.config
    grep -q '^CONFIG_DRM_PANEL_NOVATEK_NT35596S=y$' build/.config
    grep -q '^CONFIG_SND_SOC_TAS2559=m$' build/.config
    grep -q '^CONFIG_ETHERNET=y$' build/.config
    grep -q '^CONFIG_NET_VENDOR_QUALCOMM=y$' build/.config
    grep -q '^CONFIG_RMNET=m$' build/.config
    grep -q '^CONFIG_USB_USBNET=m$' build/.config
    grep -q '^CONFIG_USB_F_RNDIS=y$' build/.config
    grep -q '^CONFIG_NETFILTER_XT_MATCH_PKTTYPE=y$' build/.config
    grep -q '^CONFIG_ATH10K_SNOC=y$' build/.config
    grep -q '^CONFIG_VIDEO_QCOM_VENUS=m$' build/.config
    grep -q '^CONFIG_VIDEO_QCOM_CAMSS=m$' build/.config
    grep -q '^CONFIG_I2C_QCOM_CCI=m$' build/.config
    grep -q '^CONFIG_VIDEO_IMX363=m$' build/.config
    grep -q '^CONFIG_VIDEO_OV5675=m$' build/.config
  '';
}
