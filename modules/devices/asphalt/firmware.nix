{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.hardware.asphalt;
  stock = androidPackages.devices.asphalt.firmware;
  wifi = androidPackages.devices.asphalt.wifi-firmware.override { inherit (cfg) wifiBoardFile; };
  audioTopology = androidPackages.devices.asphalt.audio-topology;
in
{
  options.hardware.asphalt.wifiBoardFile = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = "${androidPackages.devices.asphalt.firmware-source}/lenovo/tb320fc/wifi/board-2.bin";
    description = "WCN6855 board-2.bin; defaults to the included TB320FC board data.";
  };
  config = {
    androidDevices.initrdFirmware = [
      stock
      wifi
    ];
    hardware.enableRedistributableFirmware = false;
    hardware.firmware = lib.mkBefore [
      stock
      wifi
      audioTopology
    ];
  };
}
