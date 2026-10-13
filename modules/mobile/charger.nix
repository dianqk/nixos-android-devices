{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices;
  charge = cfg.charger;
  enabled = cfg.enable && charge.enable && !cfg.recovery.enable;
  host = androidPackages.buildPackages;
  pack = androidPackages.packaging;
  firmware = pack.runCommand "${cfg.deviceName}-charger-firmware" { } ''
    mkdir -p $out/lib/firmware
    ${lib.concatMapStringsSep "\n" (package: ''
      cp -rL --no-preserve=mode ${package}/lib/firmware/. $out/lib/firmware/
    '') charge.firmware}
  '';
  modules = host.makeModulesClosure {
    kernel = lib.getOutput "modules" config.boot.kernelPackages.kernel;
    inherit firmware;
    rootModules = charge.kernelModules;
    allowMissing = false;
  };
  diagnostics = pack.writeScript "charger-diagnostics" ''
    #!${pkgs.busybox}/bin/sh
    export PATH=${lib.makeBinPath [ pkgs.busybox ]}
    set -eu
    mount -t configfs configfs /sys/kernel/config
    g=/sys/kernel/config/usb_gadget/charger
    mkdir -p "$g"
    echo 0x1d6b > "$g/idVendor"
    echo 0x0104 > "$g/idProduct"
    mkdir -p "$g/strings/0x409" "$g/configs/c.1/strings/0x409" "$g/functions/acm.log"
    echo NixOS > "$g/strings/0x409/manufacturer"
    echo 'Charging diagnostics' > "$g/strings/0x409/product"
    printf '%s' ${lib.escapeShellArg cfg.usbSerial} > "$g/strings/0x409/serialnumber"
    echo diagnostics > "$g/configs/c.1/strings/0x409/configuration"
    ln -s "$g/functions/acm.log" "$g/configs/c.1/acm"
    for attempt in $(seq 1 200); do
      test ! -e /sys/class/udc/${cfg.usbController} || break
      sleep 0.1
    done
    printf '%s' ${lib.escapeShellArg cfg.usbController} > "$g/UDC"
    # Read-only output, no shell or command interpreter. Never a kernel console.
    exec cat /dev/kmsg > /dev/ttyGS0
  '';
  # Explicit module loading includes dynamic GLINK children, without udev or
  # the normal initrd's root-device/switch-root services.
  init = pack.writeScript "mobile-charger-init" ''
    #!${pkgs.busybox}/bin/sh
    export PATH=${
      lib.makeBinPath [
        pkgs.kmod
        pkgs.busybox
      ]
    }
    fail() {
      echo "Charging environment stopped; powering off" > /dev/console
      ${lib.optionalString charge.diagnostics ''echo "mobile-charger-init: stopped; powering off" > /dev/kmsg''}
      poweroff -f
      while :; do sleep 1; poweroff -f; done
    }
    trap fail EXIT HUP INT TERM
    mkdir -p /proc /sys /dev /run /tmp
    mount -t proc proc /proc || fail
    mount -t sysfs sysfs /sys || fail
    mount -t devtmpfs devtmpfs /dev || fail
    exec </dev/console >/dev/console 2>&1 || fail
    mount -t tmpfs -o mode=0755 tmpfs /run || fail
    mount -t tmpfs -o mode=1777 tmpfs /tmp || fail
    ${lib.optionalString charge.diagnostics ''
      export CHARGER_DEBUG=1
      exec 2>/dev/kmsg
      ${diagnostics} &
      echo "mobile-charger-init: mounted RAM filesystems" >&2
      # Diagnostic builds allow the host to enumerate before an early module or
      # application failure can power off. Production boots do not wait here.
      for attempt in $(seq 1 30); do
        if test "$(cat /sys/class/udc/${cfg.usbController}/state 2>/dev/null)" = configured; then
          sleep 0.2
          break
        fi
        sleep 0.1
      done
    ''}
    for module in ${lib.escapeShellArgs charge.kernelModules}; do
      ${lib.optionalString charge.diagnostics ''echo "mobile-charger-init: loading $module" >&2''}
      modprobe "$module" || fail
    done
    ${charge.package}/bin/mobile-charger ${
      lib.escapeShellArgs [
        charge.batteryPath
        charge.inputPath
        charge.inputName
        charge.framebuffer
        charge.backlightPath
        charge.statePath
        (toString charge.display.widthMm)
        (toString charge.display.heightMm)
        (toString charge.display.fontWidth)
      ]
    }
    fail
  '';
  initrd = host.makeInitrd {
    name = "${cfg.deviceName}-charger-initrd";
    compressor = "zstd";
    compressorArgs = [
      "-T0"
      "-6"
    ];
    contents = [
      {
        object = init;
        symlink = "/init";
      }
      {
        object = "${modules}/lib/modules";
        symlink = "/lib/modules";
      }
      {
        object = "${firmware}/lib/firmware";
        symlink = "/lib/firmware";
      }
    ];
  };
  cmdline = pack.writeText "charger-cmdline" (
    lib.concatStringsSep " " (
      charge.kernelParams
      ++ lib.optional charge.diagnostics "printk.devkmsg=on"
      ++ [
        "android_charger=1"
        "rdinit=/init"
        "console=tty2"
        "loglevel=3"
        "consoleblank=0"
        "panic=0"
      ]
    )
  );
  osRelease = pack.writeText "charger-os-release" ''
    ID=mobile-charger
    PRETTY_NAME="Off-mode charging"
  '';
  image =
    pack.runCommand "${cfg.deviceName}-charger.efi"
      {
        nativeBuildInputs = [ host.systemdUkify ];
        passthru = {
          inherit
            initrd
            modules
            firmware
            cmdline
            ;
        };
      }
      ''
        ukify build --efi-arch=aa64 \
          --stub=${config.systemd.package}/lib/systemd/boot/efi/linuxaa64.efi.stub \
          --linux=${config.system.build.kernel}/Image \
          --initrd=${initrd}/initrd --devicetree=${charge.deviceTree} \
          --cmdline=@${cmdline} --os-release=@${osRelease} \
          --uname=${config.boot.kernelPackages.kernel.modDirVersion} --output=$out
      '';
in
{
  options.androidDevices.charger = {
    enable = lib.mkEnableOption "a dedicated off-mode charging EFI image";
    package = lib.mkOption {
      type = lib.types.package;
      default = androidPackages.mobile-charger;
      description = "VT charging controller used by the RAM-only environment.";
    };
    diagnostics = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Expose read-only kernel and charger logs over USB ACM for board validation; no shell and no kernel console.";
    };
    firmware = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Complete board firmware packages required during charging.";
    };
    kernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Explicit modules including dynamic remoteproc/GLINK child drivers; dependencies are collected automatically.";
    };
    kernelParams = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Board parameters for charging, independent of normal root/desktop parameters.";
    };
    deviceTree = lib.mkOption {
      type = lib.types.path;
      description = "Resolved charging device tree, including any board-specific disabled peripherals.";
    };
    batteryPath = lib.mkOption {
      type = lib.types.str;
      description = "Exact battery power_supply sysfs directory.";
    };
    inputPath = lib.mkOption {
      type = lib.types.str;
      description = "Exact measured USB input power_supply directory (not a PD contract provider).";
    };
    statePath = lib.mkOption {
      type = lib.types.str;
      default = charge.batteryPath;
      defaultText = lib.literalExpression "config.androidDevices.charger.batteryPath";
      description = "Power-supply provider of charging status and health; may differ from the capacity provider.";
    };
    display = {
      widthMm = lib.mkOption {
        type = lib.types.ints.between 0 2000;
        default = 0;
        description = "Physical panel width override in mm; set both dimensions, or leave both zero for framebuffer metadata.";
      };
      heightMm = lib.mkOption {
        type = lib.types.ints.between 0 2000;
        default = 0;
        description = "Physical panel height override in mm; zero uses framebuffer metadata.";
      };
      fontWidth = lib.mkOption {
        type = lib.types.enum [
          0
          8
          16
          24
          32
          40
          48
          56
          64
        ];
        default = 0;
        description = "Bitmap font width in pixels (height is twice the width); zero selects a readable size that fits the panel.";
      };
    };
    inputName = lib.mkOption {
      type = lib.types.str;
      description = "evdev device name for the physical power key.";
    };
    framebuffer = lib.mkOption {
      type = lib.types.str;
      description = "Framebuffer driver ID, independent of fb device numbering.";
    };
    backlightPath = lib.mkOption {
      type = lib.types.str;
      description = "Panel backlight sysfs directory.";
    };
  };
  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = (charge.display.widthMm == 0) == (charge.display.heightMm == 0);
        message = "Charging panel physical dimensions must be supplied as a pair.";
      }
      {
        assertion = lib.all cfg.kernelPackage.config.isYes [
          "VT"
          "FRAMEBUFFER_CONSOLE"
          "DRM_FBDEV_EMULATION"
        ];
        message = "The charging display requires built-in VT, framebuffer console and DRM fbdev emulation.";
      }
      {
        assertion =
          !charge.diagnostics
          || (cfg.usbController != null && cfg.kernelPackage.config.isYes "USB_CONFIGFS_ACM");
        message = "Charger USB diagnostics require an explicit controller and built-in CONFIG_USB_CONFIGFS_ACM.";
      }
      {
        assertion = pkgs.stdenv.hostPlatform.isAarch64;
        message = "The mobile charger EFI image currently requires AArch64.";
      }
    ];
    system.build.mobileChargerImage = image;
  };
}
