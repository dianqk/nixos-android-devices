{ mkFirmwareArchive }:
# Xiaomi Mi Pad 4 LTE WCN3990 board data from setotau/firmware-xiaomi-clover
# at c850ad5d11315e690df8244670241e3d5a8436dc.
mkFirmwareArchive {
  name = "clover-firmware-source";
  url = "https://github.com/dianqk/nixos-android-devices/releases/download/firmware/clover-firmware-c850ad5-20261115.tar.zst";
  hash = "sha256-W5Tm8mrAsrkIb+D0MKickcA7QPwdCyfV1+TK5+WbdQw=";
}
