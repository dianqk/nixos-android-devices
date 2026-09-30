# ---
# Module: Xiaomi Sheng Touch Host Processor
# Description: NT36532E userspace touch processor for multitouch + Focus Pen
# Scope: System
# ---

{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:

let
  cfg = config.hardware.sheng.thp;
  pkg = cfg.package;
in
{
  options.hardware.sheng.thp = {
    package = lib.mkPackageOption androidPackages.devices.sheng "thp" {
      pkgsText = "androidPackages.devices.sheng";
    };
    enable = lib.mkEnableOption "Xiaomi Sheng touch host processor";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkg ];

    # Bluetooth exposes the pen's raw report and button transports to libinput
    # before xiaomi-sheng-thp can EVIOCGRAB them. Ignore those physical evdev
    # devices so reconnects cannot leak keypad/PageUp/PageDown events into the
    # greeter; the daemon still reads them directly and exposes its uinput pen.
    services.udev.extraRules = ''
      SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Xiaomi Focus Pen", ENV{LIBINPUT_IGNORE_DEVICE}="1"
      SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Xiaomi Focus Pen Keyboard", ENV{LIBINPUT_IGNORE_DEVICE}="1"
      SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Xiaomi Focus Pen Pro", ENV{LIBINPUT_IGNORE_DEVICE}="1"
      SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Xiaomi Focus Pen Pro Keyboard", ENV{LIBINPUT_IGNORE_DEVICE}="1"
    '';

    systemd.services.xiaomi-sheng-thp = {
      description = "Xiaomi Sheng NT36532E userspace touch processor";
      after = [
        "systemd-modules-load.service"
        "bluetooth.service"
      ];
      wants = [ "bluetooth.service" ];
      wantedBy = [ "multi-user.target" ];
      startLimitIntervalSec = 60;
      startLimitBurst = 5;
      serviceConfig = {
        Type = "simple";
        ExecStartPre = [
          "${pkgs.coreutils}/bin/test -e /proc/nvt_thp_stream"
          "${pkgs.coreutils}/bin/test -e /proc/nvt_thp_stylus"
        ];
        ExecStart = "${pkg}/libexec/xiaomi-sheng-thp/xiaomi-sheng-thp";
        Restart = "on-failure";
        RestartSec = 5;
        KillSignal = "SIGINT";
        TimeoutStopSec = 10;
      };
    };
  };
}
