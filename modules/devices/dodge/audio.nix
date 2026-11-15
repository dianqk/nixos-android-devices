{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.hardware.dodge;
  ucmDirectory = "${cfg.firmwarePackage.audio}/share/alsa/ucm2";
in
{
  options.hardware.dodge.audio.enable = lib.mkOption {
    type = lib.types.bool;
    default = !config.androidDevices.recovery.enable;
    description = "Enable Dodge WCD9395 microphones/headsets and volume-capped PID2308 speakers.";
  };
  config = lib.mkMerge [
    {
      boot.blacklistedKernelModules = [
        "snd_q6apm"
        "q6prm"
      ];
    }
    (lib.mkIf cfg.audio.enable {
      boot.kernelModules = [ "fastrpc" ];
      # q6apm must start after the FastRPC static audio PD has assigned its heap.
      # An explicit modprobe in the audio service still loads this module normally.
      services.udev.extraRules = ''
        SUBSYSTEM=="misc", KERNEL=="fastrpc-adsp-secure", TAG+="systemd", ENV{SYSTEMD_WANTS}+="dodge-audio.service"
      '';
      systemd.services.dodge-audio = {
        description = "Dodge static audio PD and AudioReach initialization";
        wantedBy = [ "multi-user.target" ];
        requires = [ "dev-fastrpc\\x2dadsp\\x2dsecure.device" ];
        after = [ "dev-fastrpc\\x2dadsp\\x2dsecure.device" ];
        serviceConfig = {
          Type = "notify";
          ExecStart = "${androidPackages.fastrpc}/bin/adsprpcd audiopd adsp";
          ExecStartPost = "${pkgs.kmod}/bin/modprobe -a q6prm snd_q6apm";
          Environment = "ADSP_LIBRARY_PATH=;/run/current-system/firmware";
          Restart = "on-failure";
          RestartSec = 3;
          TimeoutStartSec = 45;
        };
      };
      services.pipewire.wireplumber.extraConfig."60-dodge-speaker-volume" = {
        "monitor.alsa.rules" = [
          {
            matches = [ { "device.name" = "alsa_card.platform-sound"; } ];
            actions.update-props = {
              "device.routes.default-sink-volume" = 0.027;
              "device.routes.default-source-volume" = 1.0;
            };
          }
        ];
      };
      hardware.firmware = [ cfg.firmwarePackage.audio ];
      environment.systemPackages = [ pkgs.alsa-utils ];
      environment.variables.ALSA_CONFIG_UCM2 = ucmDirectory;
      systemd.user.services.pipewire.environment.ALSA_CONFIG_UCM2 = ucmDirectory;
      systemd.user.services.pipewire-pulse.environment.ALSA_CONFIG_UCM2 = ucmDirectory;
      systemd.user.services.wireplumber.environment.ALSA_CONFIG_UCM2 = ucmDirectory;
    })
  ];
}
