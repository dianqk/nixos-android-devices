{ mkFirmwareArchive }:
# OnePlus 13 Linux firmware, UCM and SSC runtime data. No per-handset persist data.
mkFirmwareArchive {
  name = "dodge-firmware-source";
  url = "https://github.com/dianqk/nixos-android-devices/releases/download/firmware/dodge-firmware-LineageOS-24.0-5dd12b17e7-20261115.tar.zst";
  hash = "sha256-fSvVlMF3fjhWRpVHeJt+i8/cBWy58gXsumZY42Zp5y4=";
}
