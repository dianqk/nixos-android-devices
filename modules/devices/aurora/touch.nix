{
  config,
  lib,
  androidPackages,
  ...
}:
let
  cfg = config.hardware.aurora.touch;
  host = cfg.hostProcessor;
  data = "${host.package}/share/aurora-touch";
in
{
  imports = [
    (lib.mkRenamedOptionModule
      [ "hardware" "aurora" "touch" "package" ]
      [ "hardware" "aurora" "touch" "hostProcessor" "package" ]
    )
  ];

  options.hardware.aurora.touch = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = !config.androidDevices.recovery.enable;
      description = ''
        Load the Aurora touchscreen driver in the installed system. By default the
        controller firmware computes the contacts and the kernel reports them as
        the `Xiaomi 14 Ultra Touchscreen` multitouch device.
      '';
    };
    wakeDisplay = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether touches are reported while the panel is off, letting compositors
        that wake on input turn the display on. When false, the kernel powers the
        controller off while the panel is off (no reports, no CPU use) and lifts
        all contacts. Other input devices are unaffected.
      '';
    };
    displayConnector = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9_-]+";
      default = "DSI-1";
      description = ''
        DRM connector name whose `/sys/class/drm/card*-<name>/dpms` additionally
        gates the host processor's contacts when `wakeDisplay` is false.
      '';
    };
    hostProcessor = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Experimental: compute contacts in userspace from the controller's raw
          frames with the OEM Android 14 library instead of the controller
          firmware. Requires the former Android 14 base's controller firmware and
          a `firmwareSource` from that release; it does not work on the required
          Android 16 base. See the touch runtime documentation.
        '';
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = androidPackages.devices.aurora.touch.override {
          firmware-source = config.hardware.aurora.firmwareSource;
        };
        defaultText = lib.literalExpression "androidPackages.devices.aurora.touch built from hardware.aurora.firmwareSource";
        description = "Native touch adapter with its matching OEM library and configuration.";
      };
    };
  };
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        boot.kernelModules = [ "aurora-tcm" ];
        # Touch-to-wake needs the controller running while the panel is off.
        boot.extraModprobeConfig =
          lib.optionalString cfg.wakeDisplay ''
            options aurora-tcm follow_panel=0
          ''
          # Raw frames for the userspace host processor instead of firmware touch.
          + lib.optionalString host.enable ''
            options aurora-tcm primary_report=0xc0 disable_report=0
          '';
        services.udev.extraRules = ''
          SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Xiaomi 14 Ultra Touchscreen", SYMLINK+="input/aurora-touch"
        '';
      }
      (lib.mkIf host.enable {
        boot.kernelModules = [ "uinput" ];
        environment.systemPackages = [ host.package ];
        services.udev.extraRules = ''
          SUBSYSTEM=="misc", KERNEL=="aurora-touch-raw", TAG+="systemd", ENV{SYSTEMD_WANTS}="aurora-touch.service"
        '';
        systemd.services.aurora-touch = {
          description = "Aurora Synaptics touch host processor";
          wantedBy = [ "multi-user.target" ];
          after = [
            "systemd-modules-load.service"
            "dev-aurora\\x2dtouch\\x2draw.device"
          ];
          bindsTo = [ "dev-aurora\\x2dtouch\\x2draw.device" ];
          startLimitIntervalSec = 0;
          serviceConfig = {
            ExecStart =
              "${host.package}/bin/aurora-touch ${data}/libtouchreport.so ${data}/aurora_syna_thp_config.ini --continuous /dev/aurora-touch-raw --uinput"
              + lib.optionalString (!cfg.wakeDisplay) " --display-dpms ${cfg.displayConnector}";
            Restart = "on-failure";
            RestartSec = 3;
            TimeoutStopSec = 5;
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateNetwork = true;
            CapabilityBoundingSet = "";
            RestrictAddressFamilies = [ "AF_UNIX" ];
            # Device policy covers device nodes only; the sysfs dpms attribute stays readable.
            DevicePolicy = "closed";
            DeviceAllow = [
              "/dev/aurora-touch-raw r"
              "/dev/uinput rw"
            ];
          };
        };
      })
    ]
  );
}
