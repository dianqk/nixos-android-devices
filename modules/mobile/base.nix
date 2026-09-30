{
  config,
  lib,
  pkgs,
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
        "panic=30"
        "rootwait"
      ]
      ++ cfg.platformKernelParams
      ++ [
        # Keep the framebuffer console as the last console so kernel and
        # systemd boot/shutdown logs are visible on the display; without it
        # /dev/console is the serial port only.
        "console=tty0"
      ]
      ++ cfg.hardwareKernelParams;
    # Camera applications using the software ISP allocate from this DMA heap.
    services.udev.extraRules = ''
      SUBSYSTEM=="dma_heap", KERNEL=="system", GROUP="video", MODE="0660"
    '';
    documentation.enable = lib.mkDefault false;
  };
}
