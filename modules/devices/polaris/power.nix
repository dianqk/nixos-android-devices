{
  config,
  lib,
  ...
}:
{
  options.hardware.polaris.power.disable-suspend = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Disable all systemd sleep targets and GNOME's idle auto-suspend. On
      sdm845 mainline the device does not wake from s2idle: it hangs and
      must be force-rebooted (the qcom watchdog resets it first), so
      suspend is effectively a crash. The user-facing symptom is a dead
      screen after the device has been idle for a while.
    '';
  };

  config = lib.mkIf config.hardware.polaris.power.disable-suspend {
    systemd.targets.sleep.enable = false;

    # Keep gsd-power from triggering suspend on idle; its defaults are
    # suspend after 5 minutes on battery.
    programs.dconf.profiles.user.databases = [
      {
        settings."org/gnome/settings-daemon/plugins/power" = {
          sleep-inactive-ac-type = "nothing";
          sleep-inactive-battery-type = "nothing";
        };
      }
    ];
  };
}
