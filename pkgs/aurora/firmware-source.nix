{ mkFirmwareArchive }:
# Xiaomi 14 Ultra runtime firmware, stock OS3.0.308.0.WNACNXM (Android 16):
# adsp, audio, bluetooth, gpu, modem, sensors, touch, video and wlan, each
# with its own SHA256SUMS.
mkFirmwareArchive {
  name = "aurora-firmware-source";
  url = "https://github.com/dianqk/nixos-android-devices/releases/download/firmware/aurora-firmware-OS3.0.308.0.WNACNXM-20261024.tar.zst";
  hash = "sha256-72cH/jrNqUFpFVqXO8UADslEcOsbOjtcvD4s622cCP8=";
}
