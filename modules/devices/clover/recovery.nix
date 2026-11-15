{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cloverFirmware = androidPackages.devices.clover.firmware;
  # Without measurements each role is the unique stock GPT name on the
  # built-in eMMC; measured fields, when set, must also match.
  role = label: extra: lib.mapAttrs (_: lib.mkDefault) ({ inherit label; } // extra);
in
{
  config = lib.mkMerge [
    {
      androidDevices.recovery.daemon = {
        slotModel = "single";
        # Linux DT; the U-Boot DT names the board without the LTE suffix.
        compatible = "xiaomi,clover-lte";
        firmwareCompatible = "xiaomi,clover";
        controller = "c0c4000.mmc";
        miscBytes = 1048576;
        # Clover requests recovery through the BCB and the recovery reboot argument.
        bootRequest = "bcb";
        recoveryRebootArgument = "recovery";
        roles = {
          root = role "userdata" { };
          # The physical system partition, within a plausible size range.
          esp = role "system" {
            minBytes = 536870912;
            maxBytes = 8589934592;
          };
          # Stock Clover boot, recovery and misc sizes.
          firmware = role "boot" { bytes = 67108864; };
          recovery = role "recovery" { bytes = 67108864; };
          misc = role "misc" { bytes = 1048576; };
        };
      };
    }
    (lib.mkIf config.androidDevices.recovery.enable {
      # The initrd rides in the recovery FIT, which ABL loads as the ramdisk
      # of the U-Boot image and refuses above 35 MiB (its fastboot watchdog
      # then resets the tablet). zstd -6 is 38.6 MB; xz is 25.5 MB.
      boot.initrd.compressor = lib.mkForce "xz";
      boot.initrd.compressorArgs = lib.mkForce [
        "--check=crc32"
        "-9e"
        "-T0"
      ];
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
