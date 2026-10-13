{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.androidDevices.host;
  androidPackages = pkgs.androidDevicePackages or (import ../../pkgs { inherit pkgs; });
  usbId = lib.types.strMatching "[0-9a-fA-F]{4}:[0-9a-fA-F]{4}";
  matchId =
    id:
    let
      parts = lib.splitString ":" (lib.toLower id);
    in
    ''ATTR{idVendor}=="${builtins.head parts}", ATTR{idProduct}=="${builtins.elemAt parts 1}"'';
  networkType = lib.types.submodule {
    options = {
      mac = lib.mkOption {
        type = lib.types.strMatching "([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}";
        description = "Host-side gadget MAC, not the device-side MAC.";
      };
      uuid = lib.mkOption {
        type = lib.types.strMatching "[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}";
        description = "Stable NetworkManager connection UUID.";
      };
      address = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "[0-9.]+/[0-9]+");
        default = null;
        description = "Optional host IPv4/prefix; null uses the gadget's DHCP server.";
      };
    };
  };
in
{
  options.androidDevices.host = {
    enable = lib.mkEnableOption "Android/NixOS adaptation tools on the development host";
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Existing users granted adbusers and dialout access.";
    };
    imageTools.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    networkTools.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
    };
    adb = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
      };
      extraDeviceIds = lib.mkOption {
        type = lib.types.listOf usbId;
        default = [ ];
        description = "USB vendor:product IDs needing explicit adbusers access, including SSH sessions.";
      };
    };
    usb = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
      };
      networks = lib.mkOption {
        type = lib.types.attrsOf networkType;
        default = { };
        description = "Explicit local management connections; keys become connection names.";
      };
      consoleSerials = lib.mkOption {
        type = lib.types.listOf (lib.types.strMatching "[a-zA-Z0-9_.:-]+");
        default = [ ];
        description = "USB serial strings of debug consoles excluded from ModemManager probing.";
      };
      disableAutosuspend = lib.mkOption {
        type = lib.types.listOf usbId;
        default = [ ];
        description = "Opt-in problematic USB IDs: disable autosuspend and link power management.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages =
        with pkgs;
        [
          androidPackages.mobile-device
          android-tools
          openssh
          rsync
          picocom
          usbutils
          dtc
          file
          jq
          python3
          strace
          lsof
        ]
        ++ lib.optionals cfg.imageTools.enable [
          ubootTools
          binutils
          gptfdisk
          parted
          e2fsprogs
          dosfstools
          util-linux
          cpio
          lz4
          zstd
          xz
          unzip
        ]
        ++ lib.optionals cfg.networkTools.enable [
          iperf3
          ethtool
          tcpdump
        ]
        ++ cfg.extraPackages;
    })
    (lib.mkIf (cfg.enable || cfg.adb.enable || (cfg.usb.enable && cfg.users != [ ])) {
      users.groups.adbusers = { };
      users.users = lib.genAttrs cfg.users (_: {
        extraGroups = [
          "adbusers"
          "dialout"
        ];
      });
    })
    (lib.mkIf cfg.adb.enable {
      environment.systemPackages = [ pkgs.android-tools ];
      services.udev.extraRules = lib.concatMapStringsSep "\n" (
        id: ''SUBSYSTEM=="usb", ${matchId id}, MODE="0660", GROUP="adbusers", TAG+="uaccess"''
      ) cfg.adb.extraDeviceIds;
    })
    (lib.mkIf cfg.usb.enable {
      assertions = [
        {
          assertion = cfg.usb.networks == { } || config.networking.networkmanager.enable;
          message = "androidDevices.host.usb.networks requires NetworkManager on the host.";
        }
        {
          assertion =
            builtins.length (lib.unique (map (n: lib.toLower n.mac) (builtins.attrValues cfg.usb.networks)))
            == builtins.length (builtins.attrNames cfg.usb.networks);
          message = "androidDevices.host.usb.networks must have distinct host-side MACs.";
        }
        {
          assertion =
            builtins.length (lib.unique (map (n: lib.toLower n.uuid) (builtins.attrValues cfg.usb.networks)))
            == builtins.length (builtins.attrNames cfg.usb.networks);
          message = "androidDevices.host.usb.networks must have distinct connection UUIDs.";
        }
      ];
      networking.networkmanager.ensureProfiles.profiles = lib.mapAttrs (name: device: {
        connection = {
          id = name;
          inherit (device) uuid;
          type = "ethernet";
          autoconnect = true;
          autoconnect-priority = 100;
          mdns = 0;
          llmnr = 0;
        };
        ethernet = {
          mac-address = device.mac;
          cloned-mac-address = "preserve";
        };
        ipv4 = {
          method = if device.address == null then "auto" else "manual";
          never-default = true;
          ignore-auto-routes = true;
          ignore-auto-dns = true;
        }
        // lib.optionalAttrs (device.address != null) { address1 = device.address; };
        ipv6.method = "disabled";
        proxy.method = 0;
      }) cfg.usb.networks;
      services.udev.extraRules = lib.concatStringsSep "\n" (
        (map (
          serial: ''SUBSYSTEM=="usb", ATTR{serial}=="${serial}", ENV{ID_MM_DEVICE_IGNORE}="1"''
        ) cfg.usb.consoleSerials)
        ++ (map (
          id:
          ''ACTION=="add", SUBSYSTEM=="usb", ${matchId id}, TEST=="power/control", ATTR{power/control}="on"''
        ) cfg.usb.disableAutosuspend)
      );
      boot.kernelParams =
        lib.optional (cfg.usb.disableAutosuspend != [ ])
          "usbcore.quirks=${
            lib.concatMapStringsSep "," (id: "${lib.toLower id}:k") cfg.usb.disableAutosuspend
          }";
      services.tlp.settings = lib.mkIf (cfg.usb.disableAutosuspend != [ ]) {
        USB_DENYLIST = lib.concatStringsSep " " (map lib.toLower cfg.usb.disableAutosuspend);
      };
    })
  ];
}
