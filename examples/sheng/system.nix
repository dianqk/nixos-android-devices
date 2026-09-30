{ lib, ... }:
{
  imports = [
    ./baseline.nix
    ../desktop.nix
    ../usb-network.nix
  ];
  networking.networkmanager.enable = true;
  environment.etc."sway/config".text = lib.mkAfter ''
    output DSI-1 transform normal scale 2
  '';
  environment.etc."xdg/foot/foot.ini".text = ''
    [main]
    font=monospace:size=11
  '';

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
    priority = 100;
  };

}
