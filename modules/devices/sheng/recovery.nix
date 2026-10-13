{
  config,
  lib,
  androidPackages,
  ...
}:
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
      daemon = {
        slotModel = "ab";
        compatible = "xiaomi,sheng";
        controller = "1d84000.ufshc";
        slotMetadata = "boot-hints";
        miscBytes = 4194304;
        recoveryAvb = true;
      };
      screenPackage = lib.mkDefault (
        androidPackages.mkRecoveryScreen {
          device = "sheng";
          features = [
            "ab-partitions"
            "recovery-daemon"
          ];
        }
      );
      extendedStorageTools = true;
    };
  };
}
