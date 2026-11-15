{ mkFirmwareArchive }:
# Xiaomi Redmi Note 12 Turbo / POCO F5 runtime firmware, stock HyperOS
# OS3.0.4.0.VMRMIXM: adsp, audio, bluetooth, cdsp, dsp, gpu, modem, sensors
# (stock /vendor/etc/sensors defaults), slpi, video and wlan, each with its
# own SHA256SUMS.
mkFirmwareArchive {
  name = "marble-firmware-source";
  url = "https://github.com/dianqk/nixos-android-devices/releases/download/firmware/marble-firmware-OS3.0.4.0.VMRMIXM-20261025.tar.zst";
  hash = "sha256-+gwYrQNpaM+eRbDMJCdbXJvBBz9ERksci/O0One7mEo=";
}
