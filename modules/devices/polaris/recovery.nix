{
  config,
  lib,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices;
  polaris = config.hardware.polaris;
  # Without measurements each role is the unique stock GPT name on the built-in UFS.
  role = label: extra: lib.mapAttrs (_: lib.mkDefault) ({ inherit label; } // extra);
in
{
  imports = [
    (lib.mkAliasOptionModule
      [ "hardware" "polaris" "storageRoles" ]
      [ "androidDevices" "recovery" "daemon" "roles" ]
    )
    (lib.mkRemovedOptionModule [ "hardware" "polaris" "storageRolesFile" ] ''
      The Rust recovery daemon reads structured roles. Move measured values to
      hardware.polaris.storageRoles.<root|esp|firmware|recovery|misc>.{partuuid,number,offset,bytes,fsLabel,fsUuid};
      without measurements each role is found by its stock GPT name.
    '')
  ];
  options.hardware.polaris = {
    requireRadioIdentity = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Require verified radio identity and calibration files before offline deployment.";
    };
    systemHostName = lib.mkOption {
      type = lib.types.strMatching "[a-z0-9][a-z0-9-]*";
      default = "polaris";
      description = "Installed NixOS host name accepted by the Polaris recovery.";
    };
  };

  config = lib.mkMerge [
    {
      androidDevices.recovery.daemon = {
        slotModel = "single";
        compatible = "xiaomi,polaris";
        controller = "1d84000.ufshc";
        miscBytes = 4194304;
        # Polaris requests recovery through the BCB and reboots normally.
        bootRequest = "bcb";
        recoveryRebootArgument = null;
        ufsSafeMode = "/sys/bus/platform/devices/1d84000.ufshc";
        roles = {
          root = role "userdata" { };
          esp = role "system" { fsLabel = "NIXOS_BOOT"; };
          firmware = role "boot" { };
          recovery = role "recovery" { };
          misc = role "misc" { bytes = 4194304; };
        };
        deployRequirements = lib.mkIf polaris.requireRadioIdentity {
          macFiles = [
            "/var/lib/polaris-radio-identity/wifi-address"
            "/var/lib/polaris-radio-identity/bluetooth-address"
          ];
          checksumDirectories = [ "/var/lib/polaris-radio-snapshot" ];
        };
      };
    }
    (lib.mkIf cfg.recovery.enable {
      boot.kernelParams = [ "irqchip.gicv3_pseudo_nmi=1" ];
      androidDevices.recovery = {
        extendedStorageTools = true;
        screenPackage = lib.mkDefault (
          androidPackages.mkRecoveryScreen {
            device = "polaris";
            features = [
              "refresh-panel"
              "recovery-daemon"
            ];
          }
        );
      };
    })
    (lib.mkIf (cfg.enable && cfg.role == "system") {
      assertions = [
        {
          assertion = config.networking.hostName == polaris.systemHostName;
          message = "Set hardware.polaris.systemHostName to the installed host name.";
        }
      ];
    })
  ];
}
