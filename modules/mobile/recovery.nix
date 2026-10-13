{
  config,
  lib,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices.recovery;
  deviceName = config.androidDevices.deviceName;
  daemon = cfg.daemon;
  path = [
    "androidDevices"
    "recovery"
  ];
  role = lib.types.submodule {
    options = {
      label = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9._-]+";
        description = "GPT partition name; it must be unique among all block devices.";
      };
      partuuid = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.strMatching "[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}"
        );
        default = null;
        description = "Measured GPT partition UUID.";
      };
      number = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "Measured GPT entry number.";
      };
      offset = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
        description = "Measured start in 512-byte units (blkid PART_ENTRY_OFFSET).";
      };
      bytes = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "Measured partition size in bytes.";
      };
      minBytes = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "Smallest accepted partition size.";
      };
      maxBytes = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "Largest accepted partition size.";
      };
      fsLabel = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Expected (or, for prepared FAT boot, created) filesystem label.";
      };
      fsUuid = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Expected filesystem UUID, also used when formatting.";
      };
      requireMeasured = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Refuse this role until partuuid and bytes are measured.";
      };
    };
  };
  roleJSON = r: {
    inherit (r)
      label
      partuuid
      number
      offset
      bytes
      ;
    min_bytes = r.minBytes;
    max_bytes = r.maxBytes;
    fs_label = r.fsLabel;
    fs_uuid = r.fsUuid;
    require_measured = r.requireMeasured;
  };
  rolesJSON = builtins.toJSON (lib.mapAttrs (_: roleJSON) daemon.roles);
  removed =
    name: message:
    lib.mkRemovedOptionModule (path ++ [ name ]) message;
in
{
  imports = [
    (removed "initialInstallAdapter" "The Rust recovery daemon performs first installation; describe storage with androidDevices.recovery.daemon.roles.")
    (removed "helpFile" "The Rust recovery client provides `recovery help`.")
    (removed "tools" "Board shell tools were replaced by the Rust recovery daemon.")
    (removed "extraTargetConfig" "Board shell tools were replaced by the Rust recovery daemon.")
    (removed "bootPartitionLabel" "Describe the FAT boot partition with androidDevices.recovery.daemon.roles.esp.")
  ];
  options.androidDevices.recovery = {
    enable = lib.mkEnableOption "the shared RAM-only mobile recovery environment";
    minimal = lib.mkEnableOption "a console-only RAM recovery without storage tools or screen UI";
    daemon = {
      slotModel = lib.mkOption {
        type = lib.types.enum [
          "ab"
          "single"
        ];
        description = ''
          Storage model of the Rust recovery daemon. `ab`: B-only Android A/B
          layout with `linux`/`linux-boot` in the userdata allocation. `single`:
          one slot with explicit `roles`.
        '';
      };
      compatible = lib.mkOption {
        type = lib.types.str;
        description = "Expected root device-tree compatible of the running kernel and recovery images.";
      };
      firmwareCompatible = lib.mkOption {
        type = lib.types.str;
        default = daemon.compatible;
        defaultText = lib.literalExpression "config.androidDevices.recovery.daemon.compatible";
        description = "Root compatible required in firmware (U-Boot) images.";
      };
      controller = lib.mkOption {
        type = lib.types.str;
        description = "Expected internal storage controller sysfs component.";
      };
      slotMetadata = lib.mkOption {
        type = lib.types.enum [
          "qcom-gpt"
          "boot-hints"
          "none"
        ];
        default = "none";
        description = "Explicit on-disk A/B metadata ABI used by the recovery gate; `none` for single-slot devices.";
      };
      miscBytes = lib.mkOption {
        type = lib.types.enum [
          1048576
          4194304
        ];
        description = "Expected complete misc partition capacity for BCB transactions.";
      };
      recoveryAvb = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Require the complete 100 MiB recovery image with its unsigned AVB hash footer.";
      };
      bootRequest = lib.mkOption {
        type = lib.types.enum [
          "argument"
          "bcb"
        ];
        default = "argument";
        description = ''
          How `reboot-recovery` requests recovery: only the reboot argument, or
          a transactional `boot-recovery` BCB command in misc (which
          `reboot-system` and `reboot-bootloader` then clear).
        '';
      };
      recoveryRebootArgument = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "recovery";
        description = "Reboot argument for `reboot-recovery`, or null for a plain reboot.";
      };
      roles = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = lib.genAttrs [ "root" "esp" "firmware" "recovery" "misc" ] (
              name:
              lib.mkOption {
                type = role;
                description = "Single-slot ${name} storage role.";
              }
            );
          }
        );
        default = null;
        description = ''
          Single-slot storage roles: ext4 root, FAT boot (ESP), firmware,
          recovery and misc partitions. A role with only a label is the unique
          GPT name on the controller; measured fields must also match. The
          installed system carries the same roles and recovery refuses a system
          with different ones.
        '';
      };
      ufsSafeMode = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Controller sysfs directory whose UFS clock gating and scaling are disabled before storage access.";
      };
      deployRequirements = {
        macFiles = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Installed files that must hold one MAC address before an offline deployment.";
        };
        checksumDirectories = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Installed directories whose SHA256SUMS must verify before an offline deployment.";
        };
      };
    };
    screenPackage = lib.mkOption {
      type = lib.types.package;
      description = "Recovery screen package selected by the device module.";
    };
    targetHostName = lib.mkOption {
      type = lib.types.strMatching "[a-z0-9][a-z0-9-]*";
      description = "Installed system host name accepted by the recovery tools.";
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
  config = lib.mkMerge [
    # The installed system carries the storage contract its recovery checks.
    (lib.mkIf
      (
        config.androidDevices.enable
        && config.androidDevices.role == "system"
        && daemon.roles != null
      )
      {
        system.systemBuilderCommands = ''
          ln -s ${androidPackages.packaging.writeText "mobile-storage-roles.json" rolesJSON} $out/mobile-storage-roles.json
        '';
      }
    )
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.minimal || cfg.extendedStorageTools;
          message = "Full recovery needs the extended storage tools.";
        }
        {
          assertion =
            cfg.minimal
            || (
              if daemon.slotModel == "single" then
                daemon.roles != null && daemon.slotMetadata == "none" && !daemon.recoveryAvb
              else
                daemon.roles == null && daemon.slotMetadata != "none" && daemon.ufsSafeMode == null
            );
          message = "Single-slot recovery needs daemon roles and no A/B metadata; A/B recovery uses fixed partition names and slot metadata.";
        }
        {
          assertion = config.androidDevices.enable;
          message = "androidDevices.recovery requires androidDevices.enable.";
        }
        {
          assertion =
            cfg.minimal
            || lib.all config.androidDevices.kernelPackage.config.isYes [
              "VT"
              "FRAMEBUFFER_CONSOLE"
              "DRM_FBDEV_EMULATION"
            ];
          message = "The recovery display requires built-in VT, framebuffer console and DRM fbdev emulation.";
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
        initrdBin = lib.optional (!cfg.minimal) config.system.build.mobileRecoveryUtils;
        contents = {
          "/etc/mobile-ram-recovery".text = deviceName;
        }
        // lib.optionalAttrs (!cfg.minimal) {
          "/etc/mobile-recovery-protocol".text = "1";
          "/etc/mobile-recovery.json".text = builtins.toJSON {
            identity = deviceName;
            inherit (daemon) compatible controller;
            slot_model = daemon.slotModel;
            firmware_compatible = daemon.firmwareCompatible;
            slot_metadata = daemon.slotMetadata;
            misc_bytes = daemon.miscBytes;
            recovery_avb = daemon.recoveryAvb;
            boot_request = daemon.bootRequest;
            recovery_reboot_argument = daemon.recoveryRebootArgument;
            roles = if daemon.roles == null then null else builtins.fromJSON rolesJSON;
            ufs_safe_mode = daemon.ufsSafeMode;
            deploy_requirements = {
              mac_files = daemon.deployRequirements.macFiles;
              checksum_dirs = daemon.deployRequirements.checksumDirectories;
            };
            hostname = cfg.targetHostName;
            root_label = config.androidDevices.persistentImage.rootfs.label;
            esp_bytes =
              if config.androidDevices.boot.uefi.espSizeBytes == null then
                0
              else
                config.androidDevices.boot.uefi.espSizeBytes;
            minimum_root_bytes = cfg.minimumRootBytes;
          };
        };
        services.mobile-recovery-daemon = lib.mkIf (!cfg.minimal) {
          description = "Own recovery operations and task state";
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
            ExecStart = "/bin/mobile-recovery-daemon";
            # Chroot bind mounts must not propagate into other services' mount
            # namespaces and retain the target filesystem after daemon cleanup.
            PrivateMounts = true;
            KillMode = "control-group";
            Restart = "no";
            TimeoutStopSec = 30;
            UMask = "0077";
          };
        };
        services.mobile-recovery-screen = lib.mkIf (!cfg.minimal) {
          description = "Independent mobile VT/fbcon recovery menu";
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
            ExecStart = "/bin/mobile-recovery-screen";
            Restart = "on-failure";
            RestartSec = 3;
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
      system.build.mobileRecoveryUtils = lib.mkIf (!cfg.minimal) (
        androidPackages.mkRecoveryUtils {
          inherit (cfg) screenPackage;
          extended = cfg.extendedStorageTools;
        }
      );
    })
  ];
}
