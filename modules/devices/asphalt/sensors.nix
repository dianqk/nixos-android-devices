{
  config,
  lib,
  androidPackages,
  ...
}:
{
  options.hardware.asphalt.sensors.enable = lib.mkEnableOption "Asphalt SLPI sensors";
  config = lib.mkIf config.hardware.asphalt.sensors.enable {
    androidDevices.sensors = {
      enable = true;
      rpcDomain = "sdsp";
      dataPackage = androidPackages.devices.asphalt.sensors;
    };
    # SM8450's in-kernel locator already describes the SLPI sensor PD.
    boot.kernelModules = lib.mkIf (!config.androidDevices.recovery.enable) [ "qcom_pd_mapper" ];
  };
}
