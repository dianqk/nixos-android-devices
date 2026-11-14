{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  devices = config.androidDevices;
  cfg = devices.usb.signaller;
  enabled = devices.enable && devices.usb.enable && !devices.recovery.enable;
  kernel = devices.kernelPackage.config;
  tools = androidPackages.usb-gadgets;
  anyExtra = cfg.hidTouch.enable || cfg.massStorage.enable || cfg.uvc.enable;
  absolute = value: value != null && lib.hasPrefix "/" value && !(lib.hasInfix "\n" value);
  backend = kind: active: {
    description = "USB ${kind} gadget backend";
    path = lib.optional (kind == "uvc" && active) androidPackages.uvc-gadget;
    # Only the manager starts/stops these units; no independent boot activation.
    serviceConfig =
      if active then
        {
          Type = "notify";
          NotifyAccess = "main";
          ExecStart = "${tools}/bin/usb-gadget-backend run ${kind}";
          ExecStopPost = "${pkgs.coreutils}/bin/rm -f /run/usb-signaller/${kind}.ready";
          KillMode = "mixed";
          TimeoutStartSec = 12;
          TimeoutStopSec = 3;
          Restart = "no";
          UMask = "0077";
        }
      else
        {
          Type = "oneshot";
          ExecStart = "${pkgs.coreutils}/bin/true";
        };
  };
in
{
  options.androidDevices.usb.hidraw.enable =
    lib.mkEnableOption "HIDRAW access for the active local user";
  options.androidDevices.usb.signaller = {
    hidTouch.enable = lib.mkEnableOption "native ten-contact USB touchscreen reports";
    massStorage = {
      enable = lib.mkEnableOption "an independent USB mass-storage image";
      image = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Existing regular disk image, exclusively used while exported. Block devices are rejected.";
      };
      readOnly = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Expose the disk image read-only to the USB host.";
      };
    };
    uvc = {
      enable = lib.mkEnableOption "USB UVC video output";
      source = {
        type = lib.mkOption {
          type = lib.types.enum [
            "test"
            "v4l2"
            "libcamera"
          ];
          default = "test";
          description = "Explicit video source; failures never fall back to a test pattern.";
        };
        device = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "V4L2 capture device supporting 640x480 YUYV at 30 fps.";
        };
        camera = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Explicit libcamera camera ID or index, supporting the VGA30 MJPEG/YUV420 profile.";
        };
      };
    };
  };
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !anyExtra || enabled;
          message = "Extra USB modes require an installed system with USB enabled.";
        }
      ];
    }
    (lib.mkIf (devices.usb.hidraw.enable && !devices.recovery.enable) {
      assertions = [
        {
          assertion = kernel.isYes "HIDRAW";
          message = "HIDRAW access requires HIDRAW=y.";
        }
      ];
      services.udev.packages = [
        (androidPackages.packaging.writeTextDir "lib/udev/rules.d/70-mobile-hidraw.rules" ''
          SUBSYSTEM=="hidraw", TAG+="uaccess"
        '')
      ];
    })
    (lib.mkIf enabled {
      assertions = [
        {
          assertion = !cfg.hidTouch.enable || kernel.isYes "USB_CONFIGFS_F_HID";
          message = "USB touch requires USB_CONFIGFS_F_HID=y.";
        }
        {
          assertion = !cfg.massStorage.enable || kernel.isYes "USB_CONFIGFS_MASS_STORAGE";
          message = "USB storage requires USB_CONFIGFS_MASS_STORAGE=y.";
        }
        {
          assertion = !cfg.uvc.enable || kernel.isYes "USB_CONFIGFS_F_UVC";
          message = "USB video requires USB_CONFIGFS_F_UVC=y.";
        }
        {
          assertion = !cfg.massStorage.enable || absolute cfg.massStorage.image;
          message = "USB storage requires an absolute image path.";
        }
        {
          assertion = !cfg.uvc.enable || cfg.uvc.source.type != "v4l2" || absolute cfg.uvc.source.device;
          message = "V4L2 UVC requires an explicit absolute capture-device path.";
        }
        {
          assertion =
            !cfg.uvc.enable
            || cfg.uvc.source.type != "libcamera"
            || (cfg.uvc.source.camera != null && cfg.uvc.source.camera != "");
          message = "Libcamera UVC requires an explicit camera ID or index.";
        }
      ];
      environment.systemPackages = lib.optionals anyExtra [ tools ];
      environment.etc."usb-signaller/gadgets.json".text = builtins.toJSON {
        serial = devices.usbSerial;
        udc = devices.usbController;
        controlGroup = if cfg.controlGroup == null then "root" else cfg.controlGroup;
        storage = { inherit (cfg.massStorage) image readOnly; };
        uvc = cfg.uvc.source;
      };
      systemd.services = {
        usb-signaller-touch-mode = backend "touch" cfg.hidTouch.enable;
        usb-signaller-storage-mode = backend "storage" cfg.massStorage.enable;
        usb-signaller-uvc-mode = backend "uvc" cfg.uvc.enable;
        usb-signaller.environment.USB_SIGNALLER_GADGET_BACKEND = "${tools}/bin/usb-gadget-backend";
      };
    })
  ];
}
