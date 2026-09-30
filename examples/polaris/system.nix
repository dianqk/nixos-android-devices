{ lib, ... }:
{
  imports = [
    ./baseline.nix
    ../desktop.nix
    ../usb-network.nix
  ];
  hardware.polaris.radio = {
    identityFile = "/var/lib/polaris-radio-identity/wifi-address";
    snapshotDirectory = "/var/lib/polaris-radio-snapshot";
  };
  environment.etc."sway/config".text = lib.mkAfter ''
    output DSI-1 scale 1
  '';
  environment.etc."xdg/foot/foot.ini".text = ''
    [main]
    font=monospace:size=24
  '';
}
