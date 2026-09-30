{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  androidDevices = config.androidDevices;
  cfg = androidDevices.usb.signaller;
  enabled = androidDevices.enable && androidDevices.usb.enable && !androidDevices.recovery.enable;
  package = cfg.package;
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
    </busconfig>
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
      # Start only when ttyGS0 appears; do not make boot wait for a USB host.
      # The standard serial-getty template retains the consumer's login policy.
      services.udev.extraRules = lib.mkIf androidDevices.usb.acm.enable ''
        SUBSYSTEM=="tty", KERNEL=="ttyGS0", TAG+="systemd", ENV{SYSTEMD_WANTS}+="serial-getty@ttyGS0.service"
      '';
      environment.systemPackages = [ package ];
      services.dbus.enable = true;
      environment.etc."usb-signaller/usb-signaller.toml".text = ''
        [main]
        default_mode = "developer_mode"
      '';
      # Queries are public. Mode changes are privileged because they can disconnect
      # the management transport. Do not install upstream's unrestricted set_mode rule.
      services.dbus.packages = [ dbusPolicy ];
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
