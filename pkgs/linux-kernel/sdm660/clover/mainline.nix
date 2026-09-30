{
  fetchFromGitHub,
  lib,
  llvmPackages_23,
  openssl,
}:
let
  source = fetchFromGitHub {
    owner = "sdm660-mainline";
    repo = "linux";
    rev = "e47d622cb6d2440a9eacdc8bb2df32c037bec7b8";
    hash = "sha256-BgZqJHnIeBoUaz90WdPjxtNvyWEbEzfmXt9r8/lwWRU=";
  };
in
{
  pname = "linux-clover";
  version = "7.2.3";
  modDirVersion = "7.2.3";
  src = source;
  configfile = ./kernel.config;
  patches = [ ./patches/local/wcn3990-vht-cap.patch ];
  dtbs = [ "qcom/sdm660-xiaomi-clover.dtb" ];
  nativeBuildInputs = [
    llvmPackages_23.lld
    openssl.out
  ];
  extraMakeFlags = [
    "HOSTLDFLAGS=-fuse-ld=lld -Wl,-rpath,${lib.getLib openssl}/lib"
  ];
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
