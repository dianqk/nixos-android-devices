{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices;
in
{
  options.androidDevices = {
    enable = lib.mkEnableOption "the shared Android/mobile hardware and boot support";
    deviceName = lib.mkOption {
      type = lib.types.str;
      description = "Opaque device label used only in generated artifact names and display strings; it does not select hardware policy.";
    };
    usbSerial = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9._-]{1,64}";
      description = "Stable per-device serial exposed by the USB gadget.";
    };
    usbController = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[A-Za-z0-9._:-]{1,128}");
      default = null;
      description = "Exact registered UDC name used by both boot stages.";
    };
    panicTimeout = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 30;
      description = "Seconds before rebooting after a kernel panic; zero disables the automatic panic reboot.";
    };
    earlyKernelParams = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Device console parameters placed before the common boot parameters.";
    };
    platformKernelParams = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Platform boot parameters placed before the framebuffer console.";
    };
    hardwareKernelParams = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Device USB controller and storage boot-device parameters.";
    };
  };

  config = lib.mkIf cfg.enable {
    # One fixed USB serial per model; recovery uses its own. Consumers only
    # override it to tell several units of the same model apart.
    androidDevices.usbSerial = lib.mkDefault (
      let
        name = lib.toUpper cfg.deviceName;
      in
      if cfg.recovery.enable then "RECOVERY_${name}" else name
    );
    # Every registered board exports its kernel under the same attribute.
    androidDevices.kernelPackage = lib.mkDefault androidPackages.devices.${cfg.deviceName}.kernel;
    assertions = [
      {
        assertion = !cfg.usb.enable || cfg.usbController != null;
        message = "androidDevices.usbController is required when the USB gadget is enabled.";
      }
    ];
    system.stateVersion = lib.mkDefault "26.05";
    boot.kernelPackages = lib.mkForce (pkgs.linuxPackagesFor cfg.kernelPackage);
    system.boot.loader.kernelFile = lib.mkDefault "Image.gz";
    hardware.deviceTree.enable = lib.mkDefault false;
    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = false;
    boot.kernelParams =
      cfg.earlyKernelParams
      ++ [
        "ignore_loglevel"
        "printk.devkmsg=on"
        "panic=${toString cfg.panicTimeout}"
        "rootwait"
      ]
      ++ cfg.platformKernelParams
      ++ [
        # Full recovery owns tty2. Pin boot/status output to tty1: tty0 follows
        # the foreground VT and would overwrite the menu after it takes over.
        # Keep the display console last so /dev/console remains visible.
        (
          if cfg.recovery.enable && !cfg.recovery.minimal && cfg.recovery.screen.enable then
            "console=tty1"
          else
            "console=tty0"
        )
      ]
      ++ cfg.hardwareKernelParams;
    # Tag before systemd's 73-seat-late.rules schedules the uaccess builtin.
    # extraRules is written to 99-local.rules, which is too late for this tag.
    services.udev.packages = [
      (pkgs.writeTextFile {
        name = "android-camera-dma-heap-udev-rules";
        destination = "/etc/udev/rules.d/70-android-camera-dma-heap.rules";
        text = ''
          SUBSYSTEM=="dma_heap", KERNEL=="system", GROUP="video", MODE="0660", TAG+="uaccess"
        '';
      })
    ];
    documentation.enable = lib.mkDefault false;
  };
}
