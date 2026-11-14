{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.hardware.unicorn.hardwareKeys;
  daemon = pkgs.writeScriptBin "unicorn-hardware-keys" (
    "#!${pkgs.python3}/bin/python3\n" + builtins.readFile ../../../pkgs/unicorn/hardware-keys.py
  );
in
{
  options.hardware.unicorn.hardwareKeys = {
    enable = lib.mkEnableOption "Unicorn console volume and short/long power key handling";
    screen.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Toggle VT console display power on a short power-key press. Graphical sessions should handle display power themselves.";
    };
    powerOff.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Request orderly shutdown when the power key is held.";
    };
    volume.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.services.pipewire.enable && config.services.pipewire.systemWide;
      defaultText = lib.literalExpression "config.services.pipewire.enable && config.services.pipewire.systemWide";
      description = "Handle volume keys through system-wide PipeWire. Disabled by default when that audio service is absent; power-key handling does not require audio.";
    };
    powerOffHoldSeconds = lib.mkOption {
      type = lib.types.ints.between 1 6;
      default = 3;
      description = "Power-key hold time for orderly shutdown; shorter presses toggle console display power.";
    };
  };
  config = lib.mkIf (cfg.enable && !config.androidDevices.recovery.enable) {
    assertions = [
      {
        assertion =
          !cfg.volume.enable || (config.services.pipewire.enable && config.services.pipewire.systemWide);
        message = "Unicorn hardwareKeys.volume requires system-wide PipeWire; disable volume handling to use the power keys independently.";
      }
    ];
    boot.kernelParams = lib.optional cfg.screen.enable "consoleblank=0";
    services.logind.settings.Login = lib.mkIf (cfg.screen.enable || cfg.powerOff.enable) {
      HandlePowerKey = "ignore";
      HandlePowerKeyLongPress = "ignore";
    };
    systemd.services.unicorn-hardware-keys = {
      description = "Unicorn console volume and power keys";
      wantedBy = [ "multi-user.target" ];
      after = [
        "systemd-udev-trigger.service"
        "systemd-logind.service"
      ]
      ++ lib.optionals cfg.volume.enable [
        "pipewire.service"
        "wireplumber.service"
      ];
      wants = lib.optionals cfg.volume.enable [
        "pipewire.service"
        "wireplumber.service"
      ];
      serviceConfig = {
        ExecStart = utils.escapeSystemdExecArgs (
          [ "${daemon}/bin/unicorn-hardware-keys" ]
          ++ lib.optionals cfg.volume.enable [
            "--wpctl"
            "${pkgs.wireplumber}/bin/wpctl"
          ]
          ++ lib.optionals (!cfg.screen.enable) [ "--no-screen" ]
          ++ (
            if cfg.powerOff.enable then
              [
                "--systemctl"
                "${pkgs.systemd}/bin/systemctl"
              ]
            else
              [ "--no-poweroff" ]
          )
          ++ [
            "--long-press"
            (toString cfg.powerOffHoldSeconds)
          ]
        );
        Restart = "on-failure";
        RestartSec = 1;
        # VT blank/unblank requires CAP_SYS_ADMIN when SSH owns no local VT.
        CapabilityBoundingSet = lib.optional cfg.screen.enable "CAP_SYS_ADMIN";
        # The PipeWire socket is 0660 pipewire:pipewire. With DAC override
        # removed from the capability set, root also needs this group.
        SupplementaryGroups = lib.optional cfg.volume.enable "pipewire";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        TimeoutStopSec = 5;
      };
    };
  };
}
