{ ... }:
{
  imports = [
    ./baseline.nix
    ../desktop.nix
    ../usb-network.nix
  ];
  example.desktop = {
    scale = "2";
  };
  networking.networkmanager.enable = true;
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
