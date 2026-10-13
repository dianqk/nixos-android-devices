{
  config,
  lib,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices;
  asphalt = config.hardware.asphalt;

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
      androidDevices.recovery = {
        daemon = {
          slotModel = "ab";
          compatible = "lenovo,asphalt";
          controller = "1d84000.ufshc";
          # A fastboot "reboot recovery" boot passes no slot hint; read the
          # Qualcomm A/B GPT attributes instead. Any hint is still cross-checked.
          slotMetadata = "qcom-gpt";
          miscBytes = 1048576;
        };
        screenPackage = lib.mkDefault (
          androidPackages.mkRecoveryScreen {
            device = "asphalt";
            features = [
              "ab-partitions"
              "recovery-daemon"
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
