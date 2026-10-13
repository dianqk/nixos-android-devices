{
  config,
  lib,
  androidPackages,
  ...
}:
{
  options.hardware.polaris.sensors.enable = lib.mkEnableOption "Polaris SLPI sensors";
  config = lib.mkIf config.hardware.polaris.sensors.enable {
    androidDevices.sensors = {
      enable = true;
      rpcDomain = "sdsp";
      dataPackage = androidPackages.devices.polaris.sensors;
      dependencies = [ "polaris-pd-mapper.service" ];
    };
  };
}
