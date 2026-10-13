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
  identity = builtins.hashString "sha256" androidDevices.usbSerial;
  mac =
    prefix:
    lib.concatStringsSep ":" (
      [ prefix ] ++ builtins.genList (i: builtins.substring (i * 2) 2 identity) 5
    );
in
{
  options.androidDevices.usb.signaller = {
    package = lib.mkPackageOption androidPackages "usb-signaller" { pkgsText = "androidPackages"; };
    roleSwitch = lib.mkOption {
      type = lib.types.str;
      default = "${androidDevices.usbController}-role-switch";
      description = "Kernel USB role switch belonging to the selected controller.";
    };
    address = lib.mkOption {
      type = lib.types.str;
      default = "172.16.42.1/24";
      description = "Device IPv4 address/prefix on the local USB management network.";
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
          assertion =
            !androidDevices.usb.acm.enable || androidDevices.kernelPackage.config.isYes "USB_CONFIGFS_ACM";
          message = "The ACM console requires built-in USB_CONFIGFS_ACM support.";
        }
      ];
      # Device arrival starts the waiter; getty itself starts after enumeration.
      services.udev.extraRules = lib.mkIf androidDevices.usb.acm.enable ''
        SUBSYSTEM=="tty", KERNEL=="ttyGS0", TAG+="systemd", ENV{SYSTEMD_WANTS}+="serial-getty@ttyGS0.service"
      '';
      systemd.services."serial-getty@ttyGS0" = lib.mkIf androidDevices.usb.acm.enable {
        overrideStrategy = "asDropin";
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
      networking.networkmanager.unmanaged = [ "interface-name:usb0" ];
      systemd.network.networks."10-mobile-usb" = {
        matchConfig.Name = "usb0";
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
        allowedUDPPorts = [ 67 ];
        allowedTCPPorts = config.services.openssh.ports;
      };
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
      systemd.services.usb-signaller = {
        description = "USB gadget and role manager";
        wantedBy = [ "multi-user.target" ];
        requires = [
          "sys-kernel-config.mount"
          "dbus.service"
        ];
        after = [
          "sys-kernel-config.mount"
          "dbus.service"
          "systemd-udev-trigger.service"
        ];
        path = [ pkgs.coreutils ];
        environment = {
          USB_SIGNALLER_SERIAL = androidDevices.usbSerial;
          USB_SIGNALLER_UDC = androidDevices.usbController;
          USB_SIGNALLER_ROLE_SWITCH = cfg.roleSwitch;
          USB_SIGNALLER_DEV_ADDR = mac "02";
          USB_SIGNALLER_HOST_ADDR = mac "06";
          USB_SIGNALLER_IFNAME = "usb%%d"; # systemd expands %% to a literal %.
          # Only advertise implemented services. MTP/tethering need separate policy.
          USB_SIGNALLER_MODES = "developer_mode,charging_only,host_mode";
          USB_SIGNALLER_ACM = if androidDevices.usb.acm.enable then "1" else "0";
        };
        preStart = ''
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
          # Losing the acquired bus name can be classified as a clean stop by
          # systemd even when gadget initialization failed. Retry either case.
          Restart = "always";
          RestartSec = 2;
          TimeoutStartSec = 30;
        };
      };
    })
  ];
}
