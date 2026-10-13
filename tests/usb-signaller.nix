{ flake }:
flake.inputs.nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
  buildSystem:
  let
    lib = flake.inputs.nixpkgs.lib;
    env = flake.lib.mkBuildEnvironment {
      inherit buildSystem;
      # The desktop examples explicitly enable proprietary OEM sensor data.
      config.allowUnfreePredicate =
        package:
        builtins.elem (lib.getName package) [
          "asphalt-sensors"
          "asphalt-sensors-zstd"
          "polaris-sensors"
          "polaris-sensors-zstd"
        ];
    };
    devices = {
      polaris = {
        example = "system";
        controller = "a600000.usb";
        subnet = "42";
      };
      asphalt = {
        example = "system";
        controller = "a600000.usb";
        subnet = "43";
      };
      clover = {
        example = "system";
        controller = "a800000.usb";
        subnet = "44";
      };
      sheng = {
        example = "system";
        controller = "a600000.usb";
        subnet = "45";
      };
    };
  in
  lib.mapAttrs (
    device: expected:
    let
      make = modules: (env.nixosSystem { modules = [ flake.nixosModules.${device} ] ++ modules; }).config;
      example = name: flake.outPath + "/examples/${device}/${name}.nix";
      normal = make [ (example expected.example) ];
      defaults = make [ { androidDevices.usbSerial = "${device}-defaults"; } ];
      withoutAcm = make [
        (example expected.example)
        { androidDevices.usb.acm.enable = lib.mkForce false; }
      ];
      consumer = make [
        {
          androidDevices.usb.acm.enable = true;
          services.getty = {
            autologinUser = "diagnostic";
            loginOptions = "--preserve-environment";
            extraArgs = [ "--noissue" ];
          };
          systemd.services."serial-getty@" = {
            environment.ACM_TEMPLATE_PROBE = "retained";
            serviceConfig.Nice = 5;
          };
        }
      ];
      recovery = make [ (example "recovery") ];
      invalid = make [
        (example expected.example)
        { androidDevices.usb.enable = false; }
      ];
      disabled = make [ { androidDevices.usb.enable = false; } ];
      kernel = normal.androidDevices.kernelPackage;
    in
    assert !defaults.androidDevices.usb.acm.enable;
    assert defaults.systemd.services.usb-signaller.environment.USB_SIGNALLER_ACM == "0";
    assert !defaults.androidDevices.initrdUsb.enable;
    assert !(defaults.boot.initrd.systemd.services ? mobile-initrd-usb);
    assert lib.all (mount: mount.type != "functionfs") defaults.systemd.mounts;
    assert lib.all (mount: mount.type != "functionfs") defaults.boot.initrd.systemd.mounts;
    assert lib.hasInfix "developer_mode"
      defaults.environment.etc."usb-signaller/usb-signaller.toml".text;
    assert !(disabled.systemd.services ? usb-signaller);
    assert normal.androidDevices.usb.acm.enable;
    assert normal.systemd.services.usb-signaller.environment.USB_SIGNALLER_ACM == "1";
    assert withoutAcm.systemd.services.usb-signaller.environment.USB_SIGNALLER_ACM == "0";
    assert lib.hasInfix "serial-getty@ttyGS0.service" normal.services.udev.extraRules;
    assert !(lib.hasInfix "serial-getty@ttyGS0.service" withoutAcm.services.udev.extraRules);
    assert !(withoutAcm.systemd.services ? "serial-getty@ttyGS0");
    assert normal.systemd.services."serial-getty@ttyGS0".overrideStrategy == "asDropin";
    assert normal.systemd.services."serial-getty@ttyGS0".serviceConfig.Type == "simple";
    assert normal.systemd.services."serial-getty@ttyGS0".serviceConfig.StandardInput == "null";
    assert normal.systemd.services."serial-getty@ttyGS0".serviceConfig.StandardOutput == "journal";
    assert !normal.systemd.services."serial-getty@ttyGS0".serviceConfig.TTYReset;
    assert !normal.systemd.services."serial-getty@ttyGS0".serviceConfig.TTYVHangup;
    assert !normal.systemd.services."serial-getty@ttyGS0".serviceConfig.TTYVTDisallocate;
    assert normal.systemd.services."serial-getty@ttyGS0".preStart == "";
    assert normal.systemd.services."serial-getty@ttyGS0".wantedBy == [ ];
    assert lib.hasInfix "/sys/class/udc/${expected.controller}/state" (
      lib.last normal.systemd.services."serial-getty@ttyGS0".serviceConfig.ExecStart
    );
    assert normal.services.getty.autologinUser == null;
    assert
      !(lib.hasInfix "--autologin" (
        lib.last normal.systemd.services."serial-getty@ttyGS0".serviceConfig.ExecStart
      ));
    assert lib.hasInfix "--autologin demo" (
      lib.last normal.systemd.services."getty@tty1".serviceConfig.ExecStart
    );
    assert lib.hasPrefix normal.systemd.units."serial-getty@.service".text
      normal.systemd.units."serial-getty@ttyGS0.service".text;
    assert lib.hasPrefix normal.systemd.units."getty@.service".text
      normal.systemd.units."getty@tty1.service".text;
    assert lib.hasInfix ''Environment="TTY=%I"'' normal.systemd.units."getty@tty1.service".text;
    assert lib.hasInfix "ExecStartPre=" normal.systemd.units."getty@tty1.service".text;
    assert lib.hasInfix ''Environment="ACM_TEMPLATE_PROBE=retained"''
      consumer.systemd.units."serial-getty@ttyGS0.service".text;
    assert lib.hasInfix "Nice=5" consumer.systemd.units."serial-getty@ttyGS0.service".text;
    assert lib.hasInfix "--autologin diagnostic" (
      lib.last consumer.systemd.services."serial-getty@ttyGS0".serviceConfig.ExecStart
    );
    assert lib.hasInfix "--login-options --preserve-environment" (
      lib.last consumer.systemd.services."serial-getty@ttyGS0".serviceConfig.ExecStart
    );
    assert lib.hasInfix "--noissue" (
      lib.last consumer.systemd.services."serial-getty@ttyGS0".serviceConfig.ExecStart
    );
    assert normal.androidDevices.kernelPackage.config.isYes "USB_CONFIGFS_ACM";
    assert lib.all (a: a.assertion) normal.assertions;
    assert lib.all (a: a.assertion) recovery.assertions;
    assert !(lib.all (a: a.assertion) invalid.assertions);
    # Basic device-mode transport is required; Type-C/Host/VBUS is independent.
    assert lib.all (key: kernel.config.isYes key) [
      "CONFIGFS_FS"
      "USB_GADGET"
      "USB_LIBCOMPOSITE"
      "USB_CONFIGFS"
      "USB_CONFIGFS_NCM"
      "USB_DWC3"
      "USB_DWC3_DUAL_ROLE"
    ];
    assert !(normal.systemd.services ? mobile-usb-gadget);
    assert normal.systemd.services.usb-signaller.serviceConfig.Type == "dbus";
    assert normal.systemd.services.usb-signaller.environment.USB_SIGNALLER_UDC == expected.controller;
    assert
      normal.systemd.services.usb-signaller.environment.USB_SIGNALLER_SERIAL == "${device}-example";
    # Linux gether_set_ifname requires exactly one %d; systemd consumes %%.
    assert normal.systemd.services.usb-signaller.environment.USB_SIGNALLER_IFNAME == "usb%%d";
    assert
      normal.systemd.network.networks."10-mobile-usb".address == [ "172.16.${expected.subnet}.1/24" ];
    assert normal.systemd.network.networks."10-mobile-usb".dhcpServerConfig.EmitRouter == false;
    assert normal.systemd.network.networks."10-mobile-usb".dhcpServerConfig.EmitDNS == false;
    assert normal.services.openssh.enable;
    assert !normal.services.openssh.settings.PasswordAuthentication;
    assert !normal.services.openssh.settings.KbdInteractiveAuthentication;
    assert
      recovery.androidDevices.initrdUsb.acm.enable && recovery.androidDevices.initrdUsb.network.enable;
    assert recovery.boot.initrd.systemd.services ? mobile-initrd-usb;
    assert recovery.boot.initrd.systemd.services ? mobile-recovery-console;
    assert recovery.boot.initrd.systemd.services ? mobile-recovery-sshd;
    assert lib.all (mount: mount.type != "functionfs") recovery.boot.initrd.systemd.mounts;
    assert !(recovery.systemd.services ? usb-signaller);
    assert !(recovery.boot.initrd.systemd.services ? usb-signaller);
    {
      system = normal.system.build.toplevel.drvPath;
      recovery = recovery.system.build.mobileBootImage.drvPath;
      kernel = kernel.drvPath;
      controller = expected.controller;
      address = normal.androidDevices.usb.signaller.address;
      package = flake.packages.${buildSystem}.usb-signaller.drvPath;
    }
  ) devices
)
