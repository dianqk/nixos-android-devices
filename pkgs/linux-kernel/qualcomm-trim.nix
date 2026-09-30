{ lib }:

# Optional reductions shared by the Qualcomm mobile kernel packages. Only
# include driver families that none of these SoCs use internally. The actual
# WLAN controller choice and any board Ethernet MAC remain device decisions.
let
  # External/server Ethernet controllers. Keep the Qualcomm, Synopsys,
  # Cadence, STMicro and Microchip menus for SoC or board integration, and
  # leave CONFIG_ETHERNET enabled for RMNET and future wired peripherals.
  externalEthernetVendors = [
    "3COM"
    "ADAPTEC"
    "ALACRITECH"
    "ALIBABA"
    "AMAZON"
    "AMD"
    "AQUANTIA"
    "BROADCOM"
    "CHELSIO"
    "CISCO"
    "EMULEX"
    "GOOGLE"
    "HISILICON"
    "HUAWEI"
    "INTEL"
    "MARVELL"
    "MEDIATEK"
    "MELLANOX"
    "MICROSOFT"
    "NETRONOME"
    "NVIDIA"
    "QLOGIC"
    "REALTEK"
    "SOLARFLARE"
    "TEHUTI"
    "WANGXUN"
  ];
in
with lib.kernel;
{
  MEDIA_ANALOG_TV_SUPPORT = no;
  MEDIA_DIGITAL_TV_SUPPORT = no;
  MEDIA_SDR_SUPPORT = no;
  DRM_AMDGPU = no;
  DRM_RADEON = no;
  DRM_NOUVEAU = no;
}
// lib.genAttrs (map (vendor: "NET_VENDOR_${vendor}") externalEthernetVendors) (_: no)
