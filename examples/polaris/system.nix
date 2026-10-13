{ ... }:
{
  imports = [
    ./baseline.nix
    ../desktop.nix
    ../usb-network.nix
  ];
  example.desktop = {
    scale = "1";
  };
  hardware.polaris.sensors.enable = true;
  hardware.polaris.radio = {
    identityFile = "/var/lib/polaris-radio-identity/wifi-address";
    snapshotDirectory = "/var/lib/polaris-radio-snapshot";
  };
  environment.etc."xdg/foot/foot.ini".text = ''
    [main]
    font=monospace:size=24
  '';
}
