{ lib, ... }:
{
  imports = [
    ./baseline.nix
    ../desktop.nix
    ../usb-network.nix
  ];
  environment.etc."xdg/foot/foot.ini".text = ''
    [main]
    font=monospace:size=11
  '';
}
