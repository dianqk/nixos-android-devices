{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.hardware.clover;
  cloverFirmware = androidPackages.devices.clover.firmware;
  recoveryTools = androidPackages.devices.clover.mkRecoveryTools {
    rootLabel = config.androidDevices.persistentImage.rootfs.label;
    inherit (cfg)
      systemHostName
      rootUUID
      storageRolesFile
      ;
  };

in
{
  config = lib.mkIf config.androidDevices.recovery.enable {
    androidDevices.initrdFirmware = [
      pkgs.wireless-regdb
      cloverFirmware
    ];
    androidDevices.recovery = {
      helpFile = lib.mkDefault ../../../devices/clover/recovery-help.txt;
      tools = lib.mkDefault recoveryTools;
      screenPackage = lib.mkDefault (
        androidPackages.mkRecoveryScreen {
          device = "clover";
          features = [ "refresh-panel" ];
        }
      );
      extendedStorageTools = true;
    };
  };
}
