{
  config,
  lib,
  androidPackages,
  pkgs,
  ...
}:
let
  mobile = config.androidDevices;
  cfg = mobile.initrdUsb;
  identity = builtins.hashString "sha256" mobile.usbSerial;
  mac =
    prefix:
    lib.concatStringsSep ":" (
      [ prefix ] ++ builtins.genList (i: builtins.substring (i * 2) 2 identity) 5
    );
  address = builtins.head (lib.splitString "/" cfg.address);
  gadget = "/sys/kernel/config/usb_gadget/recovery";
  setup = androidPackages.packaging.writeShellScript "mobile-initrd-usb" ''
    set -eu
    g=${gadget}
    role=/sys/class/usb_role/${cfg.roleSwitch}/role
    if test -e "$role"; then printf device > "$role"; fi
    for attempt in $(seq 1 200); do
      test ! -e /sys/class/udc/${mobile.usbController} || break
      sleep 0.1
    done
    test -e /sys/class/udc/${mobile.usbController}
    mkdir -p "$g"
    if test -n "$(cat "$g/UDC")"; then printf '\n' > "$g/UDC"; fi
    printf 0x${mobile.usb.vendorId} > "$g/idVendor"
    printf 0x4e11 > "$g/idProduct"
    printf 0xEF > "$g/bDeviceClass"
    printf 0x02 > "$g/bDeviceSubClass"
    printf 0x01 > "$g/bDeviceProtocol"
    mkdir -p "$g/strings/0x409" "$g/configs/c.1/strings/0x409"
    printf NixOS > "$g/strings/0x409/manufacturer"
    printf '%s' ${lib.escapeShellArg "${mobile.deviceName} RAM recovery"} > "$g/strings/0x409/product"
    printf '%s' ${lib.escapeShellArg mobile.usbSerial} > "$g/strings/0x409/serialnumber"
    printf recovery > "$g/configs/c.1/strings/0x409/configuration"
    ${lib.optionalString cfg.acm.enable ''
      mkdir -p "$g/functions/acm.console"
      test -L "$g/configs/c.1/acm" || ln -s "$g/functions/acm.console" "$g/configs/c.1/acm"
    ''}
    ${lib.optionalString cfg.network.enable ''
      mkdir -p "$g/functions/ncm.usb0"
      if ! test -L "$g/configs/c.1/ncm"; then
        printf 'usb%%d' > "$g/functions/ncm.usb0/ifname"
        printf '${mac "02"}' > "$g/functions/ncm.usb0/dev_addr"
        printf '${mac "06"}' > "$g/functions/ncm.usb0/host_addr"
        ln -s "$g/functions/ncm.usb0" "$g/configs/c.1/ncm"
      fi
    ''}
    printf '%s' ${lib.escapeShellArg mobile.usbController} > "$g/UDC"
  '';
  teardown = androidPackages.packaging.writeShellScript "mobile-initrd-usb-stop" ''
    set -eu
    g=${gadget}
    test -d "$g" || exit 0
    if test -n "$(cat "$g/UDC")"; then printf '\n' > "$g/UDC"; fi
    rm -f "$g/configs/c.1/acm" "$g/configs/c.1/ncm"
    for f in acm.console ncm.usb0; do
      test ! -d "$g/functions/$f" || rmdir "$g/functions/$f"
    done
    rmdir "$g/configs/c.1/strings/0x409" "$g/configs/c.1" "$g/strings/0x409" "$g"
  '';
  console = androidPackages.packaging.writeShellScript "mobile-recovery-console" ''
    export PATH=/bin:/sbin
    export TERM=vt100
    echo 'NixOS RAM recovery. No disk is mounted automatically.'
    if test -f /run/mobile-recovery/ssh_host_ed25519_key.pub; then
      ${pkgs.openssh}/bin/ssh-keygen -lf /run/mobile-recovery/ssh_host_ed25519_key.pub
    fi
    exec /bin/bash -i
  '';
in
{
  options.androidDevices.initrdUsb = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = mobile.recovery.enable && mobile.usb.enable;
      description = "Independent ACM/NCM management in RAM recovery or early boot.";
    };
    acm.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Physical USB root console without a password, for recovery/development.";
    };
    network.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "USB NCM Ethernet, DHCP server and OpenSSH; independent of the ACM console.";
    };
    roleSwitch = lib.mkOption {
      type = lib.types.str;
      default = mobile.usb.signaller.roleSwitch;
      description = "Kernel role-switch basename; reused from the board USB configuration.";
    };
    address = lib.mkOption {
      type = lib.types.str;
      default = mobile.usb.signaller.address;
      description = "USB IPv4 address/prefix; choose a distinct subnet for simultaneous devices.";
    };
    ssh.requirePublicKey = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Require an authorized SSH public key instead of the default passwordless recovery login.";
    };
    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Authorized SSH public keys used when ssh.requirePublicKey is true.";
    };
  };
  config = lib.mkIf (mobile.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.acm.enable || cfg.network.enable;
        message = "initrdUsb needs ACM or NCM enabled; both may be enabled together.";
      }
      {
        assertion = mobile.usb.enable && config.boot.initrd.systemd.enable;
        message = "initrdUsb requires androidDevices.usb.enable and a systemd initrd.";
      }
      {
        assertion = !(config.boot.initrd.systemd.services ? mobile-usb-gadget);
        message = "initrdUsb owns the initrd USB controller; other gadget services must be disabled.";
      }
      {
        assertion = !cfg.network.enable || !config.boot.initrd.network.ssh.enable;
        message = "initrdUsb provides its own SSH server; disable boot.initrd.network.ssh to avoid competing listeners.";
      }
    ]
    ++
      map
        (symbol: {
          assertion = mobile.kernelPackage.config.isYes symbol;
          message = "initrdUsb requires built-in CONFIG_${symbol}=y in the device kernel.";
        })
        (
          [ "USB_CONFIGFS" ]
          ++ lib.optional cfg.acm.enable "USB_CONFIGFS_ACM"
          ++ lib.optional cfg.network.enable "USB_CONFIGFS_NCM"
        );
    boot.initrd.systemd = {
      users.root.shell = "/bin/bash";
      users.sshd = {
        uid = 498;
        group = "sshd";
        shell = "/bin/false";
      };
      groups.sshd.gid = 498;
      initrdBin = [ pkgs.openssh ];
      storePaths = [
        setup
        teardown
        console
        "${pkgs.openssh}/libexec/sshd-auth"
        "${pkgs.openssh}/libexec/sshd-session"
      ];
      mounts = [
        {
          what = "configfs";
          where = "/sys/kernel/config";
          type = "configfs";
          unitConfig.DefaultDependencies = false;
        }
      ];
      network = lib.mkIf cfg.network.enable {
        enable = true;
        networks."10-recovery-usb" = {
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
            PersistLeases = "runtime";
            EmitRouter = false;
            EmitDNS = false;
            EmitNTP = false;
          };
        };
      };
      contents."/etc/ssh/recovery_authorized_keys".text =
        lib.concatStringsSep "\n" cfg.authorizedKeys + "\n";
      contents."/etc/ssh/recovery_sshd_config".text = ''
        Port 22
        ListenAddress ${address}
        HostKey /run/mobile-recovery/ssh_host_ed25519_key
        AuthorizedKeysFile /run/mobile-recovery/authorized_keys
        PermitRootLogin ${if cfg.ssh.requirePublicKey then "prohibit-password" else "yes"}
        PasswordAuthentication ${if cfg.ssh.requirePublicKey then "no" else "yes"}
        PermitEmptyPasswords ${if cfg.ssh.requirePublicKey then "no" else "yes"}
        PubkeyAuthentication ${if cfg.ssh.requirePublicKey then "yes" else "no"}
        KbdInteractiveAuthentication no
        UsePAM no
        UseDNS no
        AllowUsers root
        Subsystem sftp internal-sftp
        AllowTcpForwarding yes
        AllowStreamLocalForwarding yes
        PermitTunnel no
        PrintMotd no
      '';
      services.systemd-networkd = lib.mkIf cfg.network.enable {
        wantedBy = [ (if mobile.recovery.enable then "mobile-recovery.target" else "initrd.target") ];
      };
      services.mobile-initrd-usb = {
        wantedBy = [ (if mobile.recovery.enable then "mobile-recovery.target" else "initrd.target") ];
        requires = [ "sys-kernel-config.mount" ];
        after = [
          "sys-kernel-config.mount"
          "systemd-udev-trigger.service"
        ];
        before = [ "initrd-switch-root.target" ];
        conflicts = [ "initrd-switch-root.target" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = setup;
          ExecStop = teardown;
        };
      };
      services.mobile-recovery-console = lib.mkIf cfg.acm.enable {
        wantedBy = [ (if mobile.recovery.enable then "mobile-recovery.target" else "initrd.target") ];
        after = [ "mobile-initrd-usb.service" ];
        before = [ "initrd-switch-root.target" ];
        conflicts = [ "initrd-switch-root.target" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          ExecStart = "${pkgs.busybox}/bin/getty -L -n -l ${console} 115200 ttyGS0 vt100";
          Restart = "always";
          RestartSec = 2;
          StandardInput = "null";
        };
      };
      services.mobile-recovery-sshd = lib.mkIf cfg.network.enable {
        wantedBy = [ (if mobile.recovery.enable then "mobile-recovery.target" else "initrd.target") ];
        requires = [ "systemd-networkd.service" ];
        after = [ "systemd-networkd.service" ];
        before = [ "initrd-switch-root.target" ];
        conflicts = [ "initrd-switch-root.target" ];
        unitConfig.DefaultDependencies = false;
        preStart = ''
          set -eu
          mkdir -p /run/sshd /var/empty /run/mobile-recovery
          chmod 0700 /run/mobile-recovery
          if ! test -f /run/mobile-recovery/ssh_host_ed25519_key; then
            ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -f /run/mobile-recovery/ssh_host_ed25519_key
          fi
          if ! test -e /run/mobile-recovery/authorized_keys; then
            cat /etc/ssh/recovery_authorized_keys > /run/mobile-recovery/authorized_keys
            chmod 0600 /run/mobile-recovery/authorized_keys
          fi
        '';
        serviceConfig = {
          ExecStart = "${pkgs.openssh}/bin/sshd -D -e -f /etc/ssh/recovery_sshd_config";
          Restart = "always";
          RestartSec = 2;
          KillMode = "control-group";
        };
      };
    };
  };
}
