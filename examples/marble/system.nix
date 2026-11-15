# Console system with USB networking. The Marble module installs the unfree
# marble-firmware package (GPU, video, Wi-Fi, Bluetooth, ADSP and SLPI; see
# docs/marble/firmware.md); modem and audio are not set up.
{ ... }:
{
  imports = [
    ../console.nix
    ../usb-network.nix
  ];
  # There is no verified suspend on Marble yet.
  systemd.sleep.settings.Sleep.AllowSuspend = "no";
}
