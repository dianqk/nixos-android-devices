# Userspace offset for a hardware RTC that Linux reads but cannot set (as
# Android's time_daemon does). Without it such an RTC sets the clock to its raw
# count since the last PMIC reset at every boot.
#
# rtc-offset-restore sets the clock early from RTC + saved offset, before
# time-set.target and systemd-timesyncd, and never moves it backwards. The
# offset (wall clock - RTC) is saved after each systemd-timesyncd
# synchronisation and at shutdown, only when the clock was synchronised or
# restored during this boot. A saved RTC count above the current one means the
# RTC was reset; the state is then discarded.
{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices.clock.rtcOffset;
  # Results before 2026-01-01 00:00 UTC are rejected as implausible.
  minimumEpoch = 1767225600;
  tool = androidPackages.packaging.writeShellApplication {
    name = "rtc-offset";
    runtimeInputs = [
      pkgs.coreutils
      config.systemd.package
    ];
    text = builtins.readFile ./rtc-offset.sh;
  };
  environment = {
    RTC_OFFSET_STATE_DIR = "/var/lib/rtc-offset";
    RTC_OFFSET_RUN_DIR = "/run/rtc-offset";
    RTC_OFFSET_MIN_EPOCH = toString minimumEpoch;
  };
  command = action: "${lib.getExe tool} ${action} ${lib.escapeShellArg cfg.rtc}";
in
{
  options.androidDevices.clock.rtcOffset = {
    enable = lib.mkEnableOption ''
      a saved userspace offset for an RTC that Linux cannot set: restore the
      clock from RTC + offset early at boot and save the offset after NTP
      synchronisation and at shutdown. `/run/rtc-offset/restored` marks a boot
      whose clock was restored (or already later than the restored time)
    '';
    rtc = lib.mkOption {
      type = lib.types.strMatching "rtc[0-9]+";
      default = "rtc0";
      description = "RTC class device (`/sys/class/rtc/<name>`) whose count is offset.";
    };
    markerFile = lib.mkOption {
      type = lib.types.str;
      default = "${environment.RTC_OFFSET_RUN_DIR}/restored";
      readOnly = true;
      description = "File present after the clock was restored during this boot.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.rtc-offset-restore = {
      description = "Restore the clock from the RTC and its saved offset";
      wantedBy = [ "sysinit.target" ];
      wants = [ "time-set.target" ];
      after = [ "local-fs.target" ];
      before = [
        "time-set.target"
        "sysinit.target"
        "systemd-timesyncd.service"
        "shutdown.target"
      ];
      conflicts = [ "shutdown.target" ];
      unitConfig.DefaultDependencies = false;
      inherit environment;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = command "restore";
        StateDirectory = "rtc-offset";
        StateDirectoryMode = "0700";
        RuntimeDirectory = "rtc-offset";
        RuntimeDirectoryPreserve = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    # Saves at shutdown; stopping it runs before systemd-timesyncd and D-Bus stop.
    systemd.services.rtc-offset-shutdown = {
      description = "Save the RTC offset at shutdown";
      wantedBy = [ "multi-user.target" ];
      after = [
        "rtc-offset-restore.service"
        "systemd-timesyncd.service"
        "dbus.service"
        "time-set.target"
      ];
      inherit environment;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
        ExecStop = command "save";
        StateDirectory = "rtc-offset";
        StateDirectoryMode = "0700";
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    # systemd-timesyncd touches this file after every synchronisation.
    systemd.paths.rtc-offset-save = {
      description = "Save the RTC offset after clock synchronisation";
      wantedBy = [ "paths.target" ];
      pathConfig.PathChanged = "/run/systemd/timesync/synchronized";
    };
    systemd.services.rtc-offset-save = {
      description = "Save the RTC offset after clock synchronisation";
      after = [ "rtc-offset-restore.service" ];
      inherit environment;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = command "save";
        StateDirectory = "rtc-offset";
        StateDirectoryMode = "0700";
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };
  };
}
