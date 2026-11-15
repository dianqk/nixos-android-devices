# Battery care: while plugged in, keep the battery between two charge levels
# (the system runs from the charger meanwhile), with a one-off full charge on
# request. Uses the kernel's standard power_supply charge_control_start/
# end_threshold; the charger driver enforces the window.
{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices.charging.window;
  tool = androidPackages.packaging.writeShellApplication {
    name = "charge-window";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./charge-window.sh;
  };
  environment = {
    CHARGE_WINDOW_BATTERY = cfg.battery;
    CHARGE_WINDOW_START = toString cfg.startThreshold;
    CHARGE_WINDOW_END = toString cfg.endThreshold;
    CHARGE_WINDOW_RUNDIR = "/run/charge-window";
  };
in
{
  options.androidDevices.charging.window = {
    enable = lib.mkEnableOption ''
      battery care: while plugged in, charging stops at the end threshold
      and resumes below the start threshold, so the device runs from the
      charger with the battery partly charged. This is a consumer policy and
      is off by default. Create `/run/charge-window/full-charge` (members of
      the request group may) for a one-off full charge; the window returns
      when the battery is full or the charger is unplugged. Needs a battery
      driver with writable charge_control_start/end_threshold
    '';
    battery = lib.mkOption {
      type = lib.types.str;
      example = "/sys/class/power_supply/battery";
      description = "power_supply directory of the battery.";
    };
    startThreshold = lib.mkOption {
      type = lib.types.ints.between 0 99;
      default = 75;
      description = "Charging resumes below this capacity (%).";
    };
    endThreshold = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 80;
      description = "Charging stops at this capacity (%).";
    };
    requestGroup = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group allowed to request a one-off full charge.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.startThreshold < cfg.endThreshold;
        message = "androidDevices.charging.window: startThreshold must be below endThreshold.";
      }
    ];
    systemd.tmpfiles.rules = [ "d /run/charge-window 1770 root ${cfg.requestGroup} -" ];
    systemd.services.charge-window = {
      description = "Battery care charge window";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      inherit environment;
      serviceConfig = {
        ExecStart = "${lib.getExe tool} run";
        ExecStopPost = "${lib.getExe tool} restore";
        Restart = "on-failure";
        RestartSec = 5;
        ProtectSystem = "strict";
        ReadWritePaths = [ "/run/charge-window" ];
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
  };
}
