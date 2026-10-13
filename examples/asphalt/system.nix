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
  hardware.asphalt.sensors.enable = true;
  environment.etc."xdg/foot/foot.ini".text = ''
    [main]
    font=monospace:size=11
  '';
}
