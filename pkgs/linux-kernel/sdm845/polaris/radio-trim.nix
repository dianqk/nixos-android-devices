{ lib }:

# Polaris uses the Qualcomm WCN3990 through ath10k SNOC. Keep the Atheros
# family and disable unrelated WLAN controller families; USB networking is
# separate and remains available.
with lib.kernel;
{
  WLAN_VENDOR_ADMTEK = no;
  WLAN_VENDOR_ATMEL = no;
  WLAN_VENDOR_BROADCOM = no;
  WLAN_VENDOR_INTEL = no;
  WLAN_VENDOR_INTERSIL = no;
  WLAN_VENDOR_MARVELL = no;
  WLAN_VENDOR_MEDIATEK = no;
  WLAN_VENDOR_MICROCHIP = no;
  WLAN_VENDOR_MORSEMICRO = no;
  WLAN_VENDOR_NXP = no;
  WLAN_VENDOR_PURELIFI = no;
  WLAN_VENDOR_RALINK = no;
  WLAN_VENDOR_REALTEK = no;
  WLAN_VENDOR_RSI = no;
  WLAN_VENDOR_SILABS = no;
  WLAN_VENDOR_ST = no;
  WLAN_VENDOR_TI = no;
  WLAN_VENDOR_ZYDAS = no;
  WLAN_VENDOR_QUANTENNA = no;
}
