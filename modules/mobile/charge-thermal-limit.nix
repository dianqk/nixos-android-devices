# Temperature-stepped charge current cap for boards whose charger firmware
# leaves thermal charge limiting to the operating system (as Android's thermal
# daemons do). The board supplies the cap file, sensors and steps.
{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices.charging.thermalLimit;
  tool = androidPackages.packaging.writeShellApplication {
    name = "charge-thermal-limit";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./charge-thermal-limit.sh;
  };
  environment = {
    CHARGE_THERMAL_CURRENT_FILE = cfg.currentFile;
    CHARGE_THERMAL_DEFAULT = toString cfg.defaultCurrent;
    CHARGE_THERMAL_INTERVAL = toString cfg.interval;
    CHARGE_THERMAL_REFRESH = toString cfg.refreshPolls;
    CHARGE_THERMAL_SENSORS = lib.concatMapStringsSep " " (
      sensor: "${sensor.path}:${toString sensor.multiplier}"
    ) cfg.sensors;
    CHARGE_THERMAL_STEPS = lib.concatMapStringsSep " " (
      step: "${toString step.trip}:${toString step.clear}:${toString step.current}"
    ) cfg.steps;
  };
  ascending = lib.all ({ fst, snd }: fst.trip < snd.trip) (
    lib.zipLists cfg.steps (lib.drop 1 cfg.steps)
  );
in
{
  options.androidDevices.charging.thermalLimit = {
    enable = lib.mkEnableOption ''
      a charge current cap that follows temperature: the highest readable
      sensor selects a step, which applies until the temperature falls below
      its clear temperature. The default cap is written below the first step
      and when the service stops. This writes charger settings; enable it only
      after the board's cap file was verified to limit the battery current
    '';
    currentFile = lib.mkOption {
      type = lib.types.str;
      example = "/sys/class/power_supply/battery/constant_charge_current";
      description = "Writable charge current cap in µA.";
    };
    sensors = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            path = lib.mkOption {
              type = lib.types.str;
              description = "Temperature file (power_supply `temp` or thermal zone `temp`).";
            };
            multiplier = lib.mkOption {
              type = lib.types.ints.positive;
              default = 1;
              description = "Factor to millidegrees Celsius (100 for power_supply tenths of a degree).";
            };
          };
        }
      );
      default = [ ];
      description = "Temperature sensors; the highest reading controls the cap.";
    };
    steps = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            trip = lib.mkOption {
              type = lib.types.int;
              description = "Temperature in m°C from which the step applies.";
            };
            clear = lib.mkOption {
              type = lib.types.int;
              description = "Temperature in m°C below which the step no longer applies.";
            };
            current = lib.mkOption {
              type = lib.types.ints.unsigned;
              description = "Charge current cap in µA.";
            };
          };
        }
      );
      default = [ ];
      description = "Steps with ascending trip temperatures. Without a readable sensor the last step applies.";
    };
    defaultCurrent = lib.mkOption {
      type = lib.types.ints.unsigned;
      description = "Cap in µA below the first step and after the service stops.";
    };
    interval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = "Seconds between temperature polls.";
    };
    refreshPolls = lib.mkOption {
      type = lib.types.ints.positive;
      default = 12;
      description = "Polls between rewrites of an unchanged cap (firmware restarts may reset it).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.sensors != [ ] && cfg.steps != [ ];
        message = "androidDevices.charging.thermalLimit needs sensors and steps.";
      }
      {
        assertion = ascending && lib.all (step: step.clear <= step.trip) cfg.steps;
        message = "androidDevices.charging.thermalLimit steps need ascending trips and clear <= trip.";
      }
    ];
    systemd.services.charge-thermal-limit = {
      description = "Temperature-stepped charge current cap";
      wantedBy = [ "multi-user.target" ];
      inherit environment;
      serviceConfig = {
        ExecStart = "${lib.getExe tool} run";
        ExecStopPost = "${lib.getExe tool} restore";
        Restart = "on-failure";
        RestartSec = 5;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
  };
}
