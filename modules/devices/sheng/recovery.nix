{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.hardware.sheng;
  recoveryTools = androidPackages.devices.sheng.mkRecoveryTools {
    rootLabel = config.androidDevices.persistentImage.rootfs.label;
    espSizeBytes = config.androidDevices.boot.uefi.espSizeBytes;
    minimumRootBytes = config.androidDevices.recovery.minimumRootBytes;
    inherit (cfg) systemHostName;
  };

in
{
  config = lib.mkIf config.androidDevices.recovery.enable {
    # Stock vbmeta chains recovery even for normal B-slot boots. Keep that
    # chain parseable without changing vbmeta or the preserved Android slot.
    androidDevices.boot.android = {
      maximumBytes = lib.mkForce 104857600;
      avbFooter = {
        partitionName = "recovery";
        partitionSize = 104857600;
      };
    };
    androidDevices.recovery = {
      helpFile = lib.mkDefault ../../../devices/sheng/recovery-help.txt;
      tools = lib.mkDefault recoveryTools;
      screenPackage = lib.mkDefault (
        androidPackages.mkRecoveryScreen {
          device = "sheng";
          features = [ "ab-partitions" ];
        }
      );
      extendedStorageTools = true;
    };
  };
}
