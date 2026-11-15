{ mkFirmwareArchive }:
# Lenovo TB320FC runtime firmware, stock ZUI 17.0.339 vendor
# (TB320FC_ROW_OPEN_USER_Q00031.0_V_ZUI_17.0.339_ST_251219): lenovo/tb320fc
# and the WCN6855 files under oneplus/negroni.
mkFirmwareArchive {
  name = "asphalt-firmware-source";
  url = "https://github.com/dianqk/nixos-android-devices/releases/download/firmware/asphalt-firmware-ZUI-17.0.339-20261115.tar.zst";
  hash = "sha256-yApc2gTqgI6PcjVIfdrMOkehflqRGJ1mkiirm0zb/Go=";
}
