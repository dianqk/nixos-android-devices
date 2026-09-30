{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices.recovery;
  deviceName = config.androidDevices.deviceName;
in
{
  options.androidDevices.recovery = {
    enable = lib.mkEnableOption "the shared RAM-only mobile recovery environment";
    initialInstallAdapter = lib.mkOption {
      type = lib.types.path;
      description = "Board storage adapter for shared first installation into a prepared empty root and FAT boot filesystem.";
    };
    helpFile = lib.mkOption { type = lib.types.path; };
    tools = lib.mkOption { type = lib.types.package; };
    screenPackage = lib.mkOption {
      type = lib.types.package;
      description = "Recovery screen package selected by the device module.";
    };
    targetHostName = lib.mkOption {
      type = lib.types.strMatching "[a-z0-9][a-z0-9-]*";
      description = "Installed system host name accepted by the recovery tools.";
    };
    bootPartitionLabel = lib.mkOption {
      type = lib.types.str;
      description = "GPT partition label accepted by recovery for the FAT boot partition.";
    };
    extraTargetConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional shell assignments for the board's recovery storage adapter.";
    };
    minimumRootBytes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 17179869184;
      description = "Minimum Linux root partition size accepted by recovery storage tools; choose enough room for the intended closure and updates.";
    };
    extendedStorageTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Include GPT, MMC and compression tools.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.androidDevices.enable;
        message = "androidDevices.recovery requires androidDevices.enable.";
      }
    ];
    androidDevices.role = "recovery";
    boot.kernelParams = [ "consoleblank=0" ];
    # This configuration never reaches stage 2, but NixOS still requires a
    # root filesystem while evaluating its system closure.
    fileSystems."/" = lib.mkDefault {
      device = "none";
      fsType = "tmpfs";
    };
    boot.initrd.systemd = {
      initrdBin = [ config.system.build.mobileRecoveryUtils ];
      contents = {
        "/etc/mobile-initial-install-adapter".source = cfg.initialInstallAdapter;
        "/etc/mobile-recovery-target".text = ''
          TARGET_HOSTNAME=${lib.escapeShellArg cfg.targetHostName}
          MOBILE_ESP_BYTES=${
            toString (
              if config.androidDevices.boot.uefi.espSizeBytes == null then
                0
              else
                config.androidDevices.boot.uefi.espSizeBytes
            )
          }
          MOBILE_MINIMUM_ROOT_BYTES=${toString cfg.minimumRootBytes}
          TARGET_ROOT_LABEL=${lib.escapeShellArg config.androidDevices.persistentImage.rootfs.label}
          TARGET_ESP_LABEL=${lib.escapeShellArg cfg.bootPartitionLabel}
          ${cfg.extraTargetConfig}
        '';
        "/etc/mobile-recovery-font.ttf".source =
          "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf";
        "/etc/recovery-help".source = cfg.helpFile;
        "/etc/mobile-ram-recovery".text = deviceName;
      };
      services.mobile-recovery-screen = {
        description = "Independent mobile framebuffer recovery menu";
        wantedBy = [ "mobile-recovery.target" ];
        after = [
          "systemd-udev-trigger.service"
          "tmp.mount"
        ];
        requires = [ "tmp.mount" ];
        unitConfig = {
          DefaultDependencies = false;
          IgnoreOnIsolate = true;
        };
        serviceConfig = {
          ExecStart = "/bin/mobile-recovery-screen /etc/mobile-recovery-font.ttf";
          Restart = "on-failure";
          RestartSec = 3;
        };
      };
      services.mobile-recovery-store = {
        description = "Serve the manually mounted installed Nix store over the recovery socket";
        after = [ "tmp.mount" ];
        requires = [ "tmp.mount" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          ExecStart = "/bin/mobile-recovery-store";
          Restart = "no";
        };
      };
      services.mobile-recovery-ready = {
        wantedBy = [ "mobile-recovery.target" ];
        requires = lib.optional config.androidDevices.initrdUsb.enable "mobile-initrd-usb.service";
        after = lib.optional config.androidDevices.initrdUsb.enable "mobile-initrd-usb.service";
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = "echo 'RAM recovery ready' > /run/recovery-ready";
      };
    };
    system.build.mobileRecoveryUtils = androidPackages.mkRecoveryUtils {
      recoveryTools = cfg.tools;
      inherit (cfg) screenPackage;
      extended = cfg.extendedStorageTools;
    };
  };
}
