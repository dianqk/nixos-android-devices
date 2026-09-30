{
  fetchFromGitHub,
  lib,
  llvmPackages_23,
  openssl,
}:
{
  pname = "linux-sheng";
  version = "7.2.6";
  modDirVersion = "7.2.6";
  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "sm8550-mainline";
    # Pin the sheng-7.2.6 branch, which includes the WCN7850 MAC fix after the 7.2.6 tag.
    rev = "42f3b40c702abbc37c3a04c95af008cd283aeaf3";
    hash = "sha256-cll0sZv3fheM9PeleaK8lmdJQhj/rumMsVDwQ0842gM=";
  };
  configfile = ./config.aarch64;
  patches = [
    ./patches/local/0004-pdr-add-sheng-sensor-pd-lookup.patch
    ./patches/local/0007-sheng-use-per-device-bluetooth-address.patch
  ];
  dtbs = [ "qcom/sm8550-xiaomi-sheng.dtb" ];
  nativeBuildInputs = [
    llvmPackages_23.lld
    openssl.out
  ];
  extraMakeFlags = [
    "HOSTLDFLAGS=-fuse-ld=lld -Wl,-rpath,${lib.getLib openssl}/lib"
    "KCFLAGS=-Wno-error=unused-command-line-argument"
    "KCPPFLAGS=-Wno-error=unused-command-line-argument"
  ];
  preBuild = ''
    export LD_LIBRARY_PATH="${openssl.out}/lib"
  '';
  postConfigure = ''
    grep -q '^CONFIG_EXT4_FS=y$' build/.config
    grep -q '^CONFIG_BLK_DEV_INITRD=y$' build/.config
    grep -q '^CONFIG_RD_ZSTD=y$' build/.config
    grep -q '^CONFIG_NVMEM_REBOOT_MODE=y$' build/.config
    grep -q '^CONFIG_NETFILTER_XT_MATCH_PKTTYPE=y$' build/.config
    # A missing flash subdevice leaves the entire CAMSS async graph pending.
    grep -q '^CONFIG_V4L2_FLASH_LED_CLASS=m$' build/.config
    grep -q '^CONFIG_LEDS_QCOM_FLASH=m$' build/.config
    grep -q '^CONFIG_VIDEO_S5KJN1_SHENG=m$' build/.config
    grep -q '^CONFIG_VIDEO_OV32D40=m$' build/.config
    grep -q '^CONFIG_MODULE_COMPRESS_ZSTD=y$' build/.config
    ! grep -q '^CONFIG_MODULE_COMPRESS_XZ=y$' build/.config
    grep -q '^CONFIG_FW_LOADER_COMPRESS_ZSTD=y$' build/.config
  '';
}
