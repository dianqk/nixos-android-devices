{
  baseKernel,
  lib,
  llvmPackages_23,
  openssl,
}:
{
  pname = "linux-clover";
  inherit (baseKernel) version modDirVersion src;
  configfile = ./kernel.config;
  # Linux 7.3 defaults Maili pinctrl on for Qualcomm; Clover has no Maili TLMM.
  configOverrides = { PINCTRL_MAILI = lib.kernel.no; };
  patches = import ./series.nix;
  dtbs = [ "qcom/sdm660-xiaomi-clover.dtb" ];
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
    grep -q '^CONFIG_MMC_SDHCI_MSM=y$' build/.config
    grep -q '^CONFIG_USB_DWC3=y$' build/.config
    grep -q '^CONFIG_USB_CONFIGFS_F_FS=y$' build/.config
    grep -q '^CONFIG_RD_ZSTD=y$' build/.config
    grep -q '^CONFIG_MODULE_COMPRESS_ZSTD=y$' build/.config
    ! grep -q '^CONFIG_MODULE_COMPRESS_XZ=y$' build/.config
    grep -q '^CONFIG_DRM_MSM=y$' build/.config
    grep -q '^CONFIG_DRM_PANEL_NOVATEK_NT51021=y$' build/.config
    grep -q '^CONFIG_QCOM_MDT_LOADER=y$' build/.config
    grep -q '^CONFIG_QCOM_UBWC_CONFIG=y$' build/.config
  '';
}
