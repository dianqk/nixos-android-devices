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
  persistentKey = cfg.ssh.hostKeyStorage.enable && cfg.network.enable;
  identity = builtins.hashString "sha256" mobile.usbSerial;
  mac =
    prefix:
    lib.concatStringsSep ":" (
      [ prefix ] ++ builtins.genList (i: builtins.substring (i * 2) 2 identity) 5
    );
  address = builtins.head (lib.splitString "/" cfg.address);
  gadget = "/sys/kernel/config/usb_gadget/recovery";
  phase = if mobile.recovery.enable then "RAM recovery" else "early boot";
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
    printf '%s' ${lib.escapeShellArg "${mobile.deviceName} ${phase}"} > "$g/strings/0x409/product"
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
    echo ${
      lib.escapeShellArg (
        if mobile.recovery.enable then
          "NixOS RAM recovery. SSH identity may briefly access the Linux root; no target remains mounted."
        else
          "NixOS early boot. This console closes when the installed system starts."
      )
    }
    if test -f /run/mobile-recovery/ssh-host-key-state; then
      printf "SSH identity: "
      cat /run/mobile-recovery/ssh-host-key-state
    fi
    if test -f /run/mobile-recovery/ssh_host_ed25519_key.pub; then
      ${pkgs.openssh}/bin/ssh-keygen -lf /run/mobile-recovery/ssh_host_ed25519_key.pub
    fi
    ${
      if mobile.recovery.enable && !mobile.recovery.minimal then
        "exec /bin/recovery shell"
      else
        "exec /bin/bash -i"
    }
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
    ssh.hostKeyStorage = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = mobile.recovery.enable && !mobile.recovery.minimal;
        description = "Reuse or create a recovery-only SSH host key on the verified Linux ext4 root; fall back to RAM on unavailable storage.";
      };
      compatible = lib.mkOption {
        type = lib.types.str;
        default = mobile.recovery.daemon.compatible;
        description = "Required device-tree compatible before accessing host-key storage.";
      };
      controller = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9._-]+";
        default = mobile.recovery.daemon.controller;
        description = "Required internal storage controller sysfs component; never select storage by device family.";
      };
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
        assertion =
          !persistentKey
          || (
            mobile.recovery.enable && !mobile.recovery.minimal && mobile.persistentImage.rootfs.device != null
          );
        message = "Persistent recovery SSH identity requires full RAM recovery and an explicit root device.";
      }

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
          # Match the identity set by this gadget, not a kernel-assigned name.
          matchConfig.MACAddress = mac "02";
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
      contents."/etc/recovery-host-key.json" = lib.mkIf persistentKey {
        text = builtins.toJSON {
          identity = mobile.deviceName;
          inherit (cfg.ssh.hostKeyStorage) compatible controller;
          root_device = mobile.persistentImage.rootfs.device;
          root_label = mobile.persistentImage.rootfs.label;
        };
      };
      services.mobile-recovery-host-key = lib.mkIf persistentKey {
        description = "Prepare recovery SSH identity with optional Linux-root persistence";
        wantedBy = [ "mobile-recovery.target" ];
        after = [ "systemd-udev-trigger.service" ];
        before = [
          "mobile-recovery-sshd.service"
          "mobile-recovery-console.service"
          "mobile-recovery-daemon.service"
          "mobile-recovery-screen.service"
        ];
        unitConfig.DefaultDependencies = false;
        environment.PATH = "/bin:/sbin";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "/bin/mobile-recovery-host-key";
          PrivateMounts = true;
          TimeoutStartSec = 15;
          UMask = "0077";
          RemainAfterExit = true;
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
          # Interactive Bash ignores SIGTERM. Hang up the console before
          # releasing its gadget and switching to the installed root.
          KillSignal = "SIGHUP";
          TimeoutStopSec = 5;
        };
      };
      services.mobile-recovery-sshd = lib.mkIf cfg.network.enable {
        wantedBy = [ (if mobile.recovery.enable then "mobile-recovery.target" else "initrd.target") ];
        requires = [
          "systemd-networkd.service"
          "mobile-initrd-usb.service"
        ];
        after = [
          "systemd-networkd.service"
          "mobile-initrd-usb.service"
        ];
        before = [ "initrd-switch-root.target" ];
        conflicts = [ "initrd-switch-root.target" ];
        unitConfig.DefaultDependencies = false;
        preStart = ''
          set -eu
          # Starting networkd does not mean its static address is installed yet.
          # Keep sshd bound to the USB address, and wait for that exact address.
          has_address() {
            ${pkgs.busybox}/bin/ip -4 address show dev usb0 2>/dev/null |
              ${pkgs.busybox}/bin/grep -Fq ${lib.escapeShellArg "inet ${cfg.address} "}
          }
          for attempt in $(seq 1 200); do
            has_address && break
            sleep 0.1
          done
          has_address
          mkdir -p /run/sshd /var/empty /run/mobile-recovery
          chmod 0700 /run/mobile-recovery
          if ! test -f /run/mobile-recovery/ssh_host_ed25519_key; then
            printf 'temporary\n' > /run/mobile-recovery/ssh-host-key-state
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
