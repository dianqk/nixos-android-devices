{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.dodge.wirelessCharging;
  policy = pkgs.writeShellApplication {
    name = "dodge-wireless-care";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./wireless-care.sh;
  };
in
{
  options.hardware.dodge.wirelessCharging = {
    enable = lib.mkEnableOption "the userspace voltage-care policy for automatic normal Qi charging";
    ceilingMicrovolts = lib.mkOption {
      type = lib.types.ints.between 3100000 4350000;
      default = 4350000;
      description = "Per-cell voltage ceiling for the userspace battery hold; wireless input remains available.";
    };
    restartMicrovolts = lib.mkOption {
      type = lib.types.ints.between 3000000 4300000;
      default = 4300000;
      description = "Release the care hold below this voltage. Kernel safety holds remain independent.";
    };
  };
  config = lib.mkIf (cfg.enable && !config.androidDevices.recovery.enable) {
    assertions = [
      {
        assertion = cfg.restartMicrovolts < cfg.ceilingMicrovolts;
        message = "Dodge wireless restart voltage must be below its ceiling.";
      }
    ];
    systemd.services.dodge-wireless-care = {
      description = "Dodge wireless battery care hold";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${policy}/bin/dodge-wireless-care /sys/class/power_supply/qcom-battmgr-bat ${toString cfg.ceilingMicrovolts} ${toString cfg.restartMicrovolts}";
        Restart = "on-failure";
        RestartSec = 2;
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
    };
  };
}
