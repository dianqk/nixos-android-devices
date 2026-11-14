{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.hardware.unicorn.audioRuntime;
  links = pkgs.callPackage ../../../pkgs/unicorn/audio/runtime-links.nix { };
  preparer = pkgs.writeScriptBin "unicorn-audio-prepare" (
    "#!${pkgs.python3}/bin/python3\n" + builtins.readFile ../../../pkgs/unicorn/audio/prepare-runtime.py
  );
in
{
  options.hardware.unicorn.audioRuntime = {
    enable = lib.mkEnableOption "private Unicorn speaker firmware, calibration and Music data preparation";
    inputDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/unicorn-audio/private";
      description = ''
        Canonical runtime path below /var/lib/unicorn-audio/ naming an already
        provisioned root-only directory on the independent NixOS root filesystem.
        Every ancestor symlink and filesystem boundary is rejected at runtime.
        No private file is evaluated or built by Nix.
      '';
    };
  };
  config = lib.mkIf (cfg.enable && !config.androidDevices.recovery.enable) {
    assertions = [
      {
        assertion = config.hardware.unicorn.audio.enable;
        message = "Unicorn audioRuntime requires hardware.unicorn.audio.enable.";
      }
      {
        assertion =
          builtins.getContext cfg.inputDirectory == { }
          &&
            builtins.match "/var/lib/unicorn-audio/[A-Za-z0-9_.+-]+(/[A-Za-z0-9_.+-]+)*" cfg.inputDirectory
            != null
          && !(lib.elem "." (lib.splitString "/" cfg.inputDirectory))
          && !(lib.elem ".." (lib.splitString "/" cfg.inputDirectory));
        message = "audioRuntime.inputDirectory must name a canonical private directory below /var/lib/unicorn-audio/";
      }
    ];
    # Preserve NixOS's existing firmware_class.path and every unrelated firmware.
    hardware.firmware = [ links ];
    systemd.services.unicorn-audio-prepare = {
      description = "Prepare private Unicorn speaker runtime data only";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      before = [ "systemd-user-sessions.service" ];
      restartIfChanged = false;
      unitConfig.RequiresMountsFor = [ cfg.inputDirectory ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        UMask = "0077";
        RuntimeDirectory = "unicorn-audio";
        RuntimeDirectoryMode = "0700";
        # This service has no authority to close streams or power off amplifiers.
        # Stopping/reconfiguring it must not remove data under an active consumer.
        RuntimeDirectoryPreserve = "yes";
        TimeoutStartSec = 30;
        ExecStart = utils.escapeSystemdExecArgs [
          "${preparer}/bin/unicorn-audio-prepare"
          "--input-directory"
          cfg.inputDirectory
        ];
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ReadOnlyPaths = [ cfg.inputDirectory ];
        ReadWritePaths = [ "/run/unicorn-audio" ];
      };
    };
  };
}
