{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices;
  polaris = config.hardware.polaris;
  roles =
    if polaris.storageRolesFile == null then
      androidPackages.packaging.writeText "polaris-storage-roles-auto" ''
        POLARIS_DEFAULT_ROOT_LABEL=${lib.escapeShellArg cfg.persistentImage.rootfs.label}
        ${builtins.readFile ../../../devices/polaris/storage-roles-auto.sh}
      ''
    else
      polaris.storageRolesFile;
  recoveryTools = androidPackages.devices.polaris.mkRecoveryTools {
    inherit (polaris) systemHostName requireRadioIdentity;
  };
  systemUpdater = androidPackages.devices.polaris.mkSystemUpdater {
    inherit roles;
    inherit (polaris) systemHostName;
  };
  bootInstaller = androidPackages.devices.polaris.mkBootInstaller { inherit roles; };

in
{
  options.hardware.polaris = {
    storageRolesFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional exact per-phone storage contract. By default, resolve unique
        stock GPT names on the built-in UFS and check filesystem types and labels.
      '';
    };
    requireRadioIdentity = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Require verified radio identity and calibration files before offline deployment.";
    };
    systemHostName = lib.mkOption {
      type = lib.types.strMatching "[a-z0-9][a-z0-9-]*";
      default = "polaris";
      description = "Installed NixOS host name accepted by the Polaris recovery deployer.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.recovery.enable {
      boot.kernelParams = [ "irqchip.gicv3_pseudo_nmi=1" ];
      androidDevices.recovery = {
        helpFile = lib.mkDefault ../../../devices/polaris/recovery-help.txt;
        tools = lib.mkDefault recoveryTools;
        screenPackage = lib.mkDefault (
          androidPackages.mkRecoveryScreen {
            device = "polaris";
            features = [ "refresh-panel" ];
          }
        );
      };
      boot.initrd.systemd.contents."/etc/polaris-storage-roles".source = roles;
    })
    (lib.mkIf (cfg.enable && cfg.role == "system") {
      assertions = [
        {
          assertion = config.networking.hostName == polaris.systemHostName;
          message = "Set hardware.polaris.systemHostName to the installed host name.";
        }
      ];
      system.systemBuilderCommands = ''
        ln -s ${config.system.build.mobileBootImage} $out/polaris-boot.img
        ln -s ${bootInstaller}/bin/polaris-install-boot $out/polaris-install-boot
        ln -s ${roles} $out/polaris-storage-roles
        ln -s ${systemUpdater}/bin/polaris-update-system $out/polaris-update-system
      '';
    })
  ];
}
