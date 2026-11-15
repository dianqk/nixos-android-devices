{ mkFirmwareArchive }:
# Xiaomi Mi MIX 2S payloads selected from MollySophia/firmware-xiaomi-polaris
# at d88ffb2ee182d07567bf280fc4a8493f975ae977; no per-handset calibration.
mkFirmwareArchive {
  name = "polaris-firmware-source";
  url = "https://github.com/dianqk/nixos-android-devices/releases/download/firmware/polaris-firmware-d88ffb2-20261115.tar.zst";
  hash = "sha256-r7fJA7UL+LVszTgtjVhACyGsQ+lnFKLK+84Ksq3zmq4=";
}
