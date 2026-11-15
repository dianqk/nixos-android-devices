{ mkFirmwareArchive }:
# Selected Xiaomi Pad 6S Pro payloads from code002-2/sheng-firmware at
# 14a4d70b0759bd0746264dc145f2d51a5a94902c and ianchb/sheng-firmware at
# 053da477a5c338ac28d7c1c869e8c3ff7ca24d11; no per-handset calibration.
mkFirmwareArchive {
  name = "sheng-firmware-source";
  url = "https://github.com/dianqk/nixos-android-devices/releases/download/firmware/sheng-firmware-14a4d70-20261115.tar.zst";
  hash = "sha256-TqsaX/LmPiCpUP8AIOQA9ROVCfNisSSTM2ekE2uKTRk=";
}
