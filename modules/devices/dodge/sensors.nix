{ config, lib, ... }:
let
  cfg = config.hardware.dodge;
in
{
  options.hardware.dodge.sensors.enable = lib.mkOption {
    type = lib.types.bool;
    default = !config.androidDevices.recovery.enable;
    description = "Dodge SSC sensors using the matching OEM registry defaults.";
  };
  config = lib.mkIf cfg.sensors.enable {
    androidDevices.sensors = {
      enable = true;
      rpcDomain = "adsp";
      rpcDevice = "fastrpc-adsp-secure";
      dataPackage = cfg.firmwarePackage.sensors;
      configPaths = [
        "/vendor/etc/sensors"
        "/system/vendor/etc/sensors"
        "/odm/etc/sensor"
      ];
      mountMatrix = "1, 0, 0; 0, 1, 0; 0, 0, 1";
    };
  };
}
