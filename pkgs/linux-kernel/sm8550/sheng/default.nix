{
  baseKernel,
  lib,
  llvmPackages_23,
  openssl,
}:
{
  pname = "linux-sheng";
  inherit (baseKernel) version modDirVersion src;
  configfile = ./config.aarch64;
  # Linux 7.3 adds Maili pinctrl with a Qualcomm-wide default; Sheng has no Maili TLMM.
  configOverrides = with lib.kernel; { PINCTRL_MAILI = no; };
  patches = import ./series.nix;
  dtbs = [ "qcom/sm8550-xiaomi-sheng.dtb" ];
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
    grep -q '^CONFIG_VIDEO_OV02B1B=m$' build/.config
    grep -q '^CONFIG_DRM_PANEL_NOVATEK_NT36532E=y$' build/.config
    grep -q '^CONFIG_TOUCHSCREEN_NT36532E_SPI=m$' build/.config
    grep -q '^CONFIG_TYPEC_MUX_PS5169=y$' build/.config
    grep -q '^CONFIG_ATH12K=m$' build/.config
    grep -q '^CONFIG_FPC1553=m$' build/.config
    grep -q '^CONFIG_MODULE_COMPRESS_ZSTD=y$' build/.config
    ! grep -q '^CONFIG_MODULE_COMPRESS_XZ=y$' build/.config
    grep -q '^CONFIG_FW_LOADER_COMPRESS_ZSTD=y$' build/.config
  '';
}
