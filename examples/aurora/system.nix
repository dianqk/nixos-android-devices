{ ... }:
{
  imports = [
    ../desktop.nix
    ../usb-network.nix
  ];
  androidDevices.usbSerial = "aurora-example";
  # Conservative setting: preserve ABL votes; rail ownership is not verified.
  boot.kernelParams = [
    "clk_ignore_unused"
    "pd_ignore_unused"
    "fbcon=font:TER16x32"
  ];
  example.desktop.scale = "3";
  networking.networkmanager.enable = true;
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
  };
}
