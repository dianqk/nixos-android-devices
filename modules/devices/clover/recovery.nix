{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cloverFirmware = androidPackages.devices.clover.firmware;
  # Writes and installation need this tablet's measured partitions.
  measured = label: {
    label = lib.mkDefault label;
    requireMeasured = lib.mkDefault true;
  };
in
{
  config = lib.mkMerge [
    {
      androidDevices.recovery.daemon = {
        slotModel = "single";
        # Linux DT; the U-Boot DT names the board without the LTE suffix.
        compatible = "xiaomi,clover-lte";
        firmwareCompatible = "xiaomi,clover";
        controller = "c0c4000.sdhci";
        miscBytes = 1048576;
        # Clover requests recovery through the BCB and the recovery reboot argument.
        bootRequest = "bcb";
        recoveryRebootArgument = "recovery";
        roles = {
          root = measured "userdata";
          # The physical system partition: the unique "system" on the eMMC,
          # within a plausible size range unless measured.
          esp = {
            label = lib.mkDefault "system";
            minBytes = lib.mkDefault 536870912;
            maxBytes = lib.mkDefault 8589934592;
          };
          firmware = measured "boot";
          recovery = measured "recovery";
          misc = measured "misc";
        };
      };
    }
    (lib.mkIf config.androidDevices.recovery.enable {
      androidDevices.initrdFirmware = [
        pkgs.wireless-regdb
        cloverFirmware
      ];
      androidDevices.recovery = {
        screenPackage = lib.mkDefault (
          androidPackages.mkRecoveryScreen {
            device = "clover";
            features = [
              "refresh-panel"
              "recovery-daemon"
            ];
          }
        );
        extendedStorageTools = true;
      };
    })
  ];
}
