{
  config,
  lib,
  androidPackages,
  ...
}:
let
  cfg = config.hardware.aurora.touch;
  data = "${cfg.package}/share/aurora-touch";
in
{
  options.hardware.aurora.touch = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default =
        !config.androidDevices.recovery.enable && config.hardware.aurora.firmwareVariant == "android14";
      description = "Enable the Aurora Android 14 touch host processor in the installed system.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = androidPackages.devices.aurora.touch;
      description = "Native touch adapter with its matching OEM library and configuration.";
    };
  };
  config = lib.mkIf cfg.enable {
    boot.kernelModules = [
      "uinput"
      "aurora-tcm"
    ];
    environment.systemPackages = [ cfg.package ];
    services.udev.extraRules = ''
      SUBSYSTEM=="misc", KERNEL=="aurora-touch-raw", TAG+="systemd", ENV{SYSTEMD_WANTS}="aurora-touch.service"
      SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Xiaomi 14 Ultra Touchscreen", SYMLINK+="input/aurora-touch"
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
        ExecStart = "${cfg.package}/bin/aurora-touch ${data}/libtouchreport.so ${data}/aurora_syna_thp_config.ini --continuous /dev/aurora-touch-raw --uinput";
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
        DevicePolicy = "closed";
        DeviceAllow = [
          "/dev/aurora-touch-raw r"
          "/dev/uinput rw"
        ];
      };
    };
  };
}
