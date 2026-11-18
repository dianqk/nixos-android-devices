{
  config,
  lib,
  pkgs,
  androidPackages,
  utils,
  ...
}:
let
  androidDevices = config.androidDevices;
  cfg = androidDevices.usb.signaller;
  enabled = androidDevices.enable && androidDevices.usb.enable && !androidDevices.recovery.enable;
  extended =
    cfg.followRole
    || cfg.mtp.enable
    || cfg.tethering.enable
    || cfg.hidTouch.enable
    || cfg.massStorage.enable
    || cfg.uvc.enable;
  package = cfg.package;
  waitForHost = androidPackages.packaging.writeShellScript "acm-wait-host" (
    builtins.readFile ./acm-wait-host.sh
  );
  dbusPolicy = androidPackages.packaging.writeTextDir "share/dbus-1/system.d/com.meego.usb_moded.conf" ''
    <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
      "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
    <busconfig>
      <policy context="default">
        <deny own="com.meego.usb_moded"/>
        <deny send_destination="com.meego.usb_moded"/>
        <allow send_destination="com.meego.usb_moded" send_interface="org.freedesktop.DBus.Introspectable"/>
        <allow send_destination="com.meego.usb_moded" send_interface="com.meego.usb_moded" send_member="mode_request"/>
        <allow send_destination="com.meego.usb_moded" send_interface="com.meego.usb_moded" send_member="get_modes"/>
        <allow send_destination="com.meego.usb_moded" send_interface="com.meego.usb_moded" send_member="get_status"/>
      </policy>
      <policy user="root">
        <allow own="com.meego.usb_moded"/>
        <allow send_destination="com.meego.usb_moded"/>
      </policy>
    ${
      lib.optionalString (cfg.controlGroup != null) ''
        <policy group="${cfg.controlGroup}">
          <allow send_destination="com.meego.usb_moded" send_interface="com.meego.usb_moded" send_member="set_mode"/>
        </policy>
      ''
    }</busconfig>
  '';
  address = builtins.head (lib.splitString "/" cfg.address);
  modeService = description: {
    inherit description;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/true";
    };
  };
  identity = builtins.hashString "sha256" androidDevices.usbSerial;
  mac =
    prefix:
    lib.concatStringsSep ":" (
      [ prefix ] ++ builtins.genList (i: builtins.substring (i * 2) 2 identity) 5
    );
in
{
  imports = [ ./usb-gadgets.nix ];
  options.androidDevices.usb.signaller = {
    package = lib.mkOption {
      type = lib.types.package;
      default =
        if extended then
          androidPackages.usb-signaller.override { withExtendedModes = true; }
        else
          androidPackages.usb-signaller;
      description = "USB manager package; extended modes select the serialized backend by default.";
    };
    roleSwitch = lib.mkOption {
      type = lib.types.str;
      default = "${androidDevices.usbController}-role-switch";
      description = "Kernel USB role switch belonging to the selected controller.";
    };
    followRole = lib.mkEnableOption "follow firmware-negotiated Type-C roles instead of forcing peripheral at startup";
    typecPort = lib.mkOption {
      type = lib.types.strMatching "port[0-9]+";
      default = "port0";
      description = "Type-C port associated with this controller; never auto-select another port.";
    };
    mtp = {
      enable = lib.mkEnableOption "MTP FunctionFS backend";
      user = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "[a-z_][a-z0-9_-]*");
        default = null;
        description = "Existing unprivileged user running the MTP responder.";
      };
      directories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Explicit directories to export. Never export /, an entire home or system partitions.";
      };
    };
    tethering.enable = lib.mkEnableOption "NCM internet sharing using networkd, DNS and restricted nftables forwarding";
    address = lib.mkOption {
      type = lib.types.str;
      default = "172.16.42.1/24";
      description = "Device IPv4 address/prefix on the local USB management network.";
    };
    manageRole = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether mode changes may write the USB data role. Disable this when
        an external Type-C port manager owns role selection. Gadget modes
        remain configured, ready for the port manager to select device role.
      '';
    };
    hostMode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether usb-signaller offers and applies `host_mode`. Disable it on a
        device whose Type-C port manager (TCPM) owns the USB data role, so
        that host mode only follows the partner and PD data-role swaps.
      '';
    };
    chargerSupply = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "qcom-battmgr-usb";
      description = ''
        Power supply whose USB type the charger firmware reports. When set,
        usb-signaller waits (up to 15 s) for the charger to report a USB
        type before it connects the gadget, so the gadget's D+ pull-up does
        not disturb charger detection (a charging port is otherwise detected
        as a standard port with a 100 mA input limit). `null` connects at
        once.
      '';
    };
    controlGroup = lib.mkOption {
      # A POSIX-style group name; it is interpolated into the D-Bus XML policy.
      type = lib.types.nullOr (lib.types.strMatching "[a-z_][a-z0-9_-]*");
      default = null;
      example = "usb-mode";
      description = ''
        System group whose members may call usb-signaller's `set_mode` over the
        system bus without elevation. The group is created when set. Members can
        switch to charging-only or host mode, disconnecting the USB management
        transport without any prompt. `null` keeps mode changes root-only.
      '';
    };
  };
  options.androidDevices.usb.acm.enable =
    lib.mkEnableOption "an ACM login console alongside NCM in usb-signaller developer mode";
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !androidDevices.usb.acm.enable || enabled;
          message = "androidDevices.usb.acm requires USB on an installed system.";
        }
      ];
    }
    (lib.mkIf enabled {
      assertions = [
        {
          assertion = !extended || cfg.manageRole;
          message = "Extended USB modes currently require usb.signaller.manageRole=true.";
        }
        {
          assertion = cfg.manageRole || !cfg.hostMode;
          message = "USB signaller hostMode requires manageRole; external port managers select host role.";
        }
        {
          assertion =
            !cfg.mtp.enable
            || (
              cfg.mtp.user != null
              && cfg.mtp.user != "root"
              && builtins.hasAttr cfg.mtp.user config.users.users
              && cfg.mtp.directories != [ ]
              && lib.all (
                dir:
                lib.hasPrefix "/" dir
                && !(lib.hasInfix "//" dir)
                && !(lib.hasSuffix "/" dir)
                && !(lib.hasInfix "\"" dir)
                && !(lib.hasInfix "\n" dir)
                && !(lib.hasInfix "\r" dir)
                && !(lib.hasInfix ".." dir)
                && !(lib.hasInfix "\\" dir)
                && !(builtins.elem (lib.removeSuffix "/" dir) [
                  ""
                  "/home"
                  "/root"
                  "/etc"
                  "/nix"
                  "/var"
                  "/dev"
                  "/sys"
                  "/proc"
                  config.users.users.${cfg.mtp.user}.home
                ])
              ) cfg.mtp.directories
            );
          message = "MTP requires an existing non-root user and explicit shared subdirectories, without config metacharacters.";
        }
        {
          assertion = !cfg.mtp.enable || androidDevices.kernelPackage.config.isYes "USB_CONFIGFS_F_FS";
          message = "MTP requires USB_CONFIGFS_F_FS=y.";
        }
        {
          assertion = !cfg.mtp.enable || androidDevices.kernelPackage.config.isYes "POSIX_MQUEUE";
          message = "uMTP-Responder requires POSIX_MQUEUE=y for its message queues.";
        }
        {
          assertion = !cfg.tethering.enable || config.networking.nftables.enable;
          message = "USB tethering requires nftables.";
        }
        {
          assertion =
            !androidDevices.usb.acm.enable || androidDevices.kernelPackage.config.isYes "USB_CONFIGFS_ACM";
          message = "The ACM console requires built-in USB_CONFIGFS_ACM support.";
        }
      ];
      # The daemon starts the waiter only after preparing ACM, and stops it
      # before any role/configfs changes. udev must not race that ownership.
      systemd.services."serial-getty@ttyGS0" = lib.mkIf androidDevices.usb.acm.enable {
        overrideStrategy = "asDropin";
        after = [ "usb-signaller.service" ];
        partOf = [ "usb-signaller.service" ];
        path = [ pkgs.coreutils ];
        serviceConfig = {
          # The main process waits in the background. Keep the inherited getty
          # ordering: Type=simple marks this service started before the wait.
          Type = "simple";
          StandardInput = "null";
          StandardOutput = "journal";
          StandardError = "journal";
          TTYReset = false;
          TTYVHangup = false;
          TTYVTDisallocate = false;
          ExecStart = [
            ""
            "${waitForHost} /sys/class/udc/${androidDevices.usbController}/state ${
              lib.last (lib.toList config.systemd.services."serial-getty@".serviceConfig.ExecStart)
            }"
          ];
        };
      };
      # NixOS names both drop-ins overrides.conf. The instance shadows the
      # template's file, so include its evaluated settings before our overrides.
      systemd.units."serial-getty@ttyGS0.service".text = lib.mkIf androidDevices.usb.acm.enable (
        lib.mkForce (
          config.systemd.units."serial-getty@.service".text
          + "\n"
          + (utils.systemdUtils.lib.serviceToUnit (
            config.systemd.services."serial-getty@ttyGS0" // { name = "serial-getty@ttyGS0.service"; }
          )).text
        )
      );
      environment.systemPackages = [ package ];
      services.dbus.enable = true;
      environment.etc."usb-signaller/usb-signaller.toml".text = ''
        [main]
        default_mode = "developer_mode"
      '';
      # Queries are public. Mode changes are privileged because they can disconnect
      # the management transport. Do not install upstream's unrestricted set_mode rule.
      # The optional control group receives only set_mode, not ownership or other methods.
      services.dbus.packages = [ dbusPolicy ];
      users.groups = lib.mkIf (cfg.controlGroup != null) { ${cfg.controlGroup} = { }; };
      # networkd owns only USB; NetworkManager may continue to manage Wi-Fi.
      systemd.network.enable = true;
      # Match the gadget identity so a host-mode USB Ethernet adapter named
      # usb0 can still be managed by NetworkManager.
      networking.networkmanager.unmanaged = [ "mac:${mac "02"}" ];
      systemd.network.networks."10-mobile-usb" = {
        matchConfig = {
          Name = "usb0";
          MACAddress = mac "02";
        };
        address = [ cfg.address ];
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          ConfigureWithoutCarrier = true;
          DHCPServer = true;
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        };
        dhcpServerConfig = {
          PoolOffset = 2;
          PoolSize = 1;
          EmitRouter = false;
          EmitDNS = false;
          EmitNTP = false;
        };
      };
      networking.firewall.interfaces.usb0 = {
        allowedUDPPorts = [ 67 ] ++ lib.optional cfg.tethering.enable 53;
        allowedTCPPorts = config.services.openssh.ports ++ lib.optional cfg.tethering.enable 53;
      };
      # networkd starts before local file systems. On the first boot of a
      # fresh root, /var/lib/systemd/network gets its systemd-network owner
      # only from the system tmpfiles run; until then persistent storage
      # (and so the USB DHCP server) fails with "Permission denied".
      systemd.services.systemd-networkd-persistent-storage.after = [
        "systemd-tmpfiles-setup.service"
      ];
      systemd.services.usb-signaller-developer-mode = {
        description = "Configure the local NCM management network";
        requires = [ "systemd-networkd.service" ];
        after = [ "systemd-networkd.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.systemd}/bin/networkctl reload";
        };
      };
      # Define stop targets even when a backend is disabled. Only enabled
      # backends appear in get_modes; none of these units start at boot.
      systemd.services.usb-signaller-mtp-mode =
        if !cfg.mtp.enable then
          modeService "Disabled MTP backend"
        else
          {
            description = "MTP for explicitly shared directories";
            requires = [ "usb-signaller-mtp-mount.service" ];
            after = [ "usb-signaller-mtp-mount.service" ];
            serviceConfig = {
              Type = "simple";
              User = cfg.mtp.user;
              ExecStart = "${androidPackages.umtp-responder}/bin/umtprd -conf /etc/usb-signaller/umtprd.conf";
              Restart = "no";
              TimeoutStopSec = 2;
              UMask = "0077";
              ProtectSystem = "strict";
              ProtectHome = "tmpfs";
              BindPaths = cfg.mtp.directories;
              ReadWritePaths = cfg.mtp.directories ++ [ "/dev/usb-signaller-mtp" ];
              PrivateTmp = true;
              PrivateIPC = true;
              NoNewPrivileges = true;
              CapabilityBoundingSet = [ ];
              RestrictAddressFamilies = [ "AF_UNIX" ];
            };
          };
      systemd.services.usb-signaller-mtp-mount =
        if !cfg.mtp.enable then
          modeService "Disabled MTP mount"
        else
          {
            description = "FunctionFS mount owned by usb-signaller";
            path = [
              pkgs.coreutils
              pkgs.util-linux
            ];
            script = ''
              set -eu
              mkdir -p /dev/usb-signaller-mtp
              mount -t functionfs -o mode=0700,uid=$(id -u ${lib.escapeShellArg cfg.mtp.user}),gid=$(id -g ${lib.escapeShellArg cfg.mtp.user}) mtp /dev/usb-signaller-mtp
            '';
            postStop = ''
              if mountpoint -q /dev/usb-signaller-mtp; then
                test "$(findmnt -n -o FSTYPE,SOURCE --mountpoint /dev/usb-signaller-mtp)" = "functionfs mtp"
                umount /dev/usb-signaller-mtp
              fi
              if test -d /dev/usb-signaller-mtp; then rmdir /dev/usb-signaller-mtp; fi
            '';
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              TimeoutStartSec = 3;
              TimeoutStopSec = 3;
            };
          };
      environment.etc."usb-signaller/umtprd.conf" = lib.mkIf cfg.mtp.enable {
        text = ''
          loop_on_disconnect 1
          usb_functionfs_mode 1
          manufacturer "Linux Foundation"
          product "${androidDevices.deviceName} MTP"
          serial "${androidDevices.usbSerial}"
          interface "MTP"
          usb_vendor_id 0x1d6b
          usb_product_id 0x0105
          usb_dev_path "/dev/usb-signaller-mtp/ep0"
          usb_epin_path "/dev/usb-signaller-mtp/ep1"
          usb_epout_path "/dev/usb-signaller-mtp/ep2"
          usb_epint_path "/dev/usb-signaller-mtp/ep3"
          ${lib.concatImapStringsSep "\n" (
            i: dir: ''storage "${dir}" "USB Share ${toString i}" "rw"''
          ) cfg.mtp.directories}
        '';
      };
      systemd.tmpfiles.rules = lib.optionals cfg.mtp.enable (
        map (dir: "d ${builtins.toJSON dir} 0700 ${cfg.mtp.user} - -") cfg.mtp.directories
      );
      networking.nftables.enable = lib.mkIf cfg.tethering.enable (lib.mkDefault true);
      # This chain also blocks forwarding in developer mode when another service
      # has enabled ip_forward. Only this service populates the upstream set.
      networking.nftables.tables.mobile_usb = lib.mkIf cfg.tethering.enable {
        family = "inet";
        content = ''
          set uplink { type ifname; }
          set private_v4 { type ipv4_addr; flags interval; elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/3 }; }
          chain forward {
            type filter hook forward priority -20; policy accept;
            iifname "usb0" oifname @uplink ip saddr ${cfg.address} ip daddr != @private_v4 ct state { new, established, related } accept
            iifname @uplink oifname "usb0" ip daddr ${cfg.address} ct state { established, related } accept
            iifname "usb0" drop
            oifname "usb0" drop
          }
          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            iifname "usb0" oifname @uplink ip saddr ${cfg.address} masquerade
          }
        '';
      };
      networking.firewall.extraForwardRules = lib.mkIf cfg.tethering.enable ''
        # The earlier mobile_usb chain has already dropped all disallowed USB flows.
        iifname "usb0" accept
        oifname "usb0" ct state { established, related } accept
      '';
      systemd.services.usb-signaller-tethering-mode =
        if !cfg.tethering.enable then
          modeService "Disabled USB sharing backend"
        else
          {
            description = "Restricted USB internet sharing";
            bindsTo = [ "usb-signaller-tethering-dns.service" ];
            requires = [
              "systemd-networkd.service"
              "nftables.service"
              "usb-signaller-tethering-dns.service"
            ];
            after = [
              "systemd-networkd.service"
              "nftables.service"
              "usb-signaller-tethering-dns.service"
            ];
            path = [
              pkgs.iproute2
              pkgs.nftables
              pkgs.systemd
            ];
            serviceConfig = {
              Type = "simple";
              ExecStart = "${pkgs.python3}/bin/python3 ${./usb-tethering.py} ${cfg.address} --mac ${mac "02"}";
              Restart = "no";
              ExecStopPost = "${pkgs.python3}/bin/python3 ${./usb-tethering.py} ${cfg.address} --cleanup";
              TimeoutStopSec = 10;
            };
          };
      systemd.services.usb-signaller-tethering-dns = lib.mkIf cfg.tethering.enable {
        description = "DNS on the USB sharing link";
        partOf = [ "usb-signaller-tethering-mode.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.dnsmasq}/bin/dnsmasq --keep-in-foreground --conf-file=/dev/null --interface=usb0 --except-interface=lo --bind-dynamic --listen-address=${address} --no-hosts --resolv-file=/etc/resolv.conf --user=nobody --pid-file=";
          Restart = "no";
          TimeoutStopSec = 2;
        };
      };
      systemd.services.usb-signaller = {
        description = "USB gadget and role manager";
        wantedBy = [ "multi-user.target" ];
        unitConfig = lib.mkIf extended {
          StartLimitIntervalSec = 60;
          StartLimitBurst = 3;
        };
        requires = [
          "sys-kernel-config.mount"
          "dbus.service"
        ];
        after = [
          "sys-kernel-config.mount"
          "dbus.service"
          "systemd-udev-trigger.service"
        ];
        path = [ pkgs.coreutils ] ++ lib.optional (cfg.chargerSupply != null) pkgs.gnugrep;
        environment = {
          USB_SIGNALLER_SERIAL = androidDevices.usbSerial;
          USB_SIGNALLER_UDC = androidDevices.usbController;
          USB_SIGNALLER_ROLE_SWITCH = cfg.roleSwitch;
          USB_SIGNALLER_MANAGE_ROLE = if cfg.manageRole then "1" else "0";
          USB_SIGNALLER_DEV_ADDR = mac "02";
          USB_SIGNALLER_HOST_ADDR = mac "06";
          USB_SIGNALLER_IFNAME = "usb%%d"; # systemd expands %% to a literal %.
          USB_SIGNALLER_MODES = lib.concatStringsSep "," (
            [
              "developer_mode"
              "charging_only"
            ]
            ++ lib.optional cfg.hostMode "host_mode"
            ++ lib.optional cfg.mtp.enable "mtp_ffs_mode"
            ++ lib.optional cfg.tethering.enable "tethering_mode"
            ++ lib.optional cfg.hidTouch.enable "hid_touch_mode"
            ++ lib.optional cfg.massStorage.enable "mass_storage_mode"
            ++ lib.optional cfg.uvc.enable "uvc_mode"
          );
          USB_SIGNALLER_FOLLOW_ROLE = if cfg.followRole then "1" else "0";
          USB_SIGNALLER_TYPEC_PORT = cfg.typecPort;
          USB_SIGNALLER_ACM = if androidDevices.usb.acm.enable then "1" else "0";
          USB_SIGNALLER_ACM_SERVICE = lib.mkIf androidDevices.usb.acm.enable "serial-getty@ttyGS0.service";
        };
        preStart =
          lib.optionalString (cfg.chargerSupply != null) ''
            # Let charger detection finish before the gadget pulls D+ up.
            type=/sys/class/power_supply/${lib.escapeShellArg cfg.chargerSupply}/usb_type
            for attempt in $(seq 1 150); do
              reported=$(grep -o '\[[^]]*\]' "$type" 2>/dev/null || true)
              if test -n "$reported" && test "$reported" != "[Unknown]"; then
                echo "charger reports $reported"
                sleep 1
                break
              fi
              sleep 0.1
            done
          ''
          + ''
            for attempt in $(seq 1 100); do
              if test -e /sys/class/udc/${lib.escapeShellArg androidDevices.usbController} ||
                 test -e /sys/class/usb_role/${lib.escapeShellArg cfg.roleSwitch}/role; then
                exit 0
              fi
              sleep 0.1
            done
            echo 'USB controller/role switch is not available' >&2
            exit 1
          '';
        serviceConfig = {
          Type = "dbus";
          BusName = "com.meego.usb_moded";
          ExecStart = "${package}/bin/usb-signaller";
          ExecStopPost = lib.mkIf extended "${package}/bin/usb-signaller --cleanup";
          # Initialization errors are exposed by get_status. Bound retries only
          # cover daemon failures, never repeatedly failing hardware transitions.
          Restart = if extended then "on-failure" else "always";
          RestartSec = 2;
          TimeoutStartSec = 30;
          TimeoutStopSec = lib.mkIf extended 45;
          RuntimeDirectory = lib.mkIf extended "usb-signaller";
          RuntimeDirectoryPreserve = lib.mkIf extended "restart";
        };
      };
    })
  ];
}
