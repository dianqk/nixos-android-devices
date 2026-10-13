{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices.persistentImage;
  image = cfg.rootfs;
  systemLinkName =
    if image.systemLinkName == null then
      "${config.androidDevices.deviceName}-system"
    else
      image.systemLinkName;
  rootDevice = if image.device == null then "/dev/disk/by-label/${image.label}" else image.device;
  systemImage = androidPackages.mkRootfsImage {
    name = image.name;
    system = config.system.build.toplevel;
    inherit systemLinkName;
    maximumBytes = image.maximumBytes;
    inherit (image) label uuid padding;
  };
in
{
  options.androidDevices.persistentImage = {
    enable = lib.mkEnableOption "an installed mobile system with an ext4 root" // {
      default = config.androidDevices.enable && !config.androidDevices.recovery.enable;
    };
    rootfs = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "${config.androidDevices.deviceName}-rootfs";
        description = "Name of the optional ext4 image derivation.";
      };
      label = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9._-]{1,16}";
        default = "NIXOS";
        description = "Ext4 filesystem label; match the recovery storage contract.";
      };
      uuid = lib.mkOption {
        type = lib.types.str;
        description = "Ext4 UUID for building a rootfs image; choose or measure it for the target filesystem.";
      };
      padding = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 256 * 1024 * 1024;
        description = "Additional free space in bytes beyond the system closure in the ext4 image.";
      };
      maximumBytes = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
      };
      device = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      filesystem = lib.mkOption {
        type = lib.types.enum [ "ext4" ];
        default = "ext4";
      };
      systemLinkName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.androidDevices.enable;
        message = "androidDevices.persistentImage requires androidDevices.enable.";
      }
    ];

    system.build.mobileSystemImage = systemImage;
    fileSystems."/" = {
      device = lib.mkForce rootDevice;
      fsType = "ext4";
      autoResize = true;
      # Stop writing on filesystem errors instead of continuing on a failing disk.
      options = [
        "noatime"
        "errors=remount-ro"
      ];
    };
    boot.growPartition = lib.mkForce false;
    nix.settings.fsync-store-paths = true;
    networking.useDHCP = false;
    services.journald.settings.Journal.SystemMaxUse = "128M";

    boot.postBootCommands = ''
      if [ -f /nix-path-registration ]; then
        ${config.nix.package}/bin/nix-store --load-db < /nix-path-registration
        touch /etc/NIXOS
        ${config.nix.package}/bin/nix-env -p /nix/var/nix/profiles/system \
          --set /run/current-system
        rm -f /nix-path-registration
      fi
    '';

    environment.systemPackages = (
      with pkgs;
      [
        bashInteractive
        dtc
        e2fsprogs
        file
        htop
        iproute2
        kmod
        libgpiod
        procps
        strace
        usbutils
        util-linux
      ]
    );
  };
}
