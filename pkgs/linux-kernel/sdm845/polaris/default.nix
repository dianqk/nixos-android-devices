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
    grep -q '^CONFIG_SCSI_UFS_QCOM=y$' "$buildRoot"/.config
    grep -q '^CONFIG_USB_DWC3=y$' "$buildRoot"/.config
    grep -q '^CONFIG_USB_DWC3_QCOM=y$' "$buildRoot"/.config
    grep -q '^CONFIG_USB_CONFIGFS_F_FS=y$' "$buildRoot"/.config
    grep -q '^CONFIG_RD_ZSTD=y$' "$buildRoot"/.config
    grep -q '^CONFIG_MODULE_COMPRESS_ZSTD=y$' "$buildRoot"/.config
    ! grep -q '^CONFIG_MODULE_COMPRESS_XZ=y$' "$buildRoot"/.config
    grep -q '^CONFIG_QCOM_Q6V5_MSS=y$' "$buildRoot"/.config
    grep -q '^CONFIG_QCOM_IPA=y$' "$buildRoot"/.config
    grep -q '^CONFIG_BATTERY_PMI8998_FG=y$' "$buildRoot"/.config
    grep -q '^CONFIG_CHARGER_QCOM_SMB2=y$' "$buildRoot"/.config
    grep -q '^CONFIG_DRM_PANEL_NOVATEK_NT35596S=y$' "$buildRoot"/.config
    grep -q '^CONFIG_SND_SOC_TAS2559=m$' "$buildRoot"/.config
    grep -q '^CONFIG_ETHERNET=y$' "$buildRoot"/.config
    grep -q '^CONFIG_NET_VENDOR_QUALCOMM=y$' "$buildRoot"/.config
    grep -q '^CONFIG_RMNET=m$' "$buildRoot"/.config
    grep -q '^CONFIG_USB_USBNET=m$' "$buildRoot"/.config
    grep -q '^CONFIG_USB_F_RNDIS=y$' "$buildRoot"/.config
    grep -q '^CONFIG_NETFILTER_XT_MATCH_PKTTYPE=y$' "$buildRoot"/.config
    grep -q '^CONFIG_ATH10K_SNOC=y$' "$buildRoot"/.config
    grep -q '^CONFIG_VIDEO_QCOM_VENUS=m$' "$buildRoot"/.config
    grep -q '^CONFIG_VIDEO_QCOM_CAMSS=m$' "$buildRoot"/.config
    grep -q '^CONFIG_I2C_QCOM_CCI=m$' "$buildRoot"/.config
    grep -q '^CONFIG_VIDEO_IMX363=m$' "$buildRoot"/.config
    grep -q '^CONFIG_VIDEO_OV5675=m$' "$buildRoot"/.config
  '';
}
