{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices;
  asphalt = config.hardware.asphalt;
  plannerPython = pkgs.python3Minimal;
  recoveryTools = androidPackages.devices.asphalt.mkRecoveryTools {
    rootLabel = config.androidDevices.persistentImage.rootfs.label;
    espSizeBytes = config.androidDevices.boot.uefi.espSizeBytes;
    minimumRootBytes = config.androidDevices.recovery.minimumRootBytes;
    inherit (asphalt) systemHostName;
  };

in
{
  options.hardware.asphalt.systemHostName = lib.mkOption {
    type = lib.types.strMatching "[a-z0-9][a-z0-9-]*";
    default = "asphalt";
    description = "Installed Y700 system host name accepted by recovery.";
  };
  config = lib.mkMerge [
    (lib.mkIf cfg.recovery.enable {
      boot.kernelParams = [ "cpufreq.off=1" ];
      # The initrd collector does not discover Python or its standard library
      # from the generated planner's shebang.
      boot.initrd.systemd.storePaths = [ plannerPython ];
      androidDevices.recovery = {
        helpFile = lib.mkDefault ../../../devices/asphalt/recovery-help.txt;
        tools = lib.mkDefault recoveryTools;
        screenPackage = lib.mkDefault (
          androidPackages.mkRecoveryScreen {
            device = "asphalt";
            features = [
              "ab-partitions"
              "backlight-control"
            ];
          }
        );
        extendedStorageTools = true;
      };
    })
    (lib.mkIf (cfg.enable && cfg.role == "system") {
      assertions = [
        {
          assertion = config.networking.hostName == asphalt.systemHostName;
          message = "Set hardware.asphalt.systemHostName to the installed host name.";
        }
      ];
      system.systemBuilderCommands = ''
        ln -s ${config.system.build.mobileBootImage} $out/asphalt-boot.img
      '';
    })
  ];
}
