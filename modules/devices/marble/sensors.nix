{
  config,
  lib,
  ...
}:
let
  cfg = config.hardware.marble;
in
{
  options.hardware.marble.sensors.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      SLPI (SSC) sensors through sdsprpcd, libssc and iio-sensor-proxy
      (androidDevices.sensors), for screen orientation. The SSC registry
      defaults come from the stock sensor configuration in the firmware
      package; the registry state (including calibration the SLPI writes)
      persists under androidDevices.sensors.stateDirectory.
    '';
  };
  config = lib.mkIf cfg.sensors.enable {
    assertions = [
      {
        assertion = cfg.firmwarePackage.hasSensorRegistry or false;
        message = "hardware.marble.sensors needs a firmware package with the SSC registry (stock /vendor/etc/sensors configuration); see docs/marble/README.md#sensors.";
      }
    ];
    androidDevices.sensors = {
      enable = true;
      rpcDomain = "sdsp";
      dataPackage = cfg.firmwarePackage.sensors;
      # SSC samples are in Android device axes; the shared SSC backend
      # normalizes them for the orientation classifier. No residual
      # mounting correction until the four orientations say otherwise.
      mountMatrix = "1, 0, 0; 0, 1, 0; 0, 0, 1";
    };
    # The in-kernel locator describes the SLPI sensor PD (SM8475 uses the
    # SM8350 domain list).
    boot.kernelModules = lib.mkIf (!config.androidDevices.recovery.enable) [ "qcom_pd_mapper" ];
  };
}
