{ config, lib, ... }:
let
  cfg = config.hardware.aurora;
in
{
  options.hardware.aurora.sensors.enable = lib.mkOption {
    type = lib.types.bool;
    default = !config.androidDevices.recovery.enable;
    description = "Aurora SSC sensors using the matching Android 16 DSP data.";
  };
  config = lib.mkIf cfg.sensors.enable {
    androidDevices.sensors = {
      enable = true;
      rpcDomain = "adsp";
      dataPackage = cfg.firmwarePackage.sensors;
      configPaths = [
        "/vendor/etc/sensors"
        "/system/vendor/etc/sensors"
        "/odm/etc/sensors"
      ];
      # SSC reports Android device axes; the common backend normalizes these.
      mountMatrix = "1, 0, 0; 0, 1, 0; 0, 0, 1";
    };
  };
}
