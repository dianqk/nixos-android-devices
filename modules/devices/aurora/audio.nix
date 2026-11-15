{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.aurora;
  ucmDirectory = "${cfg.firmwarePackage.audio}/share/alsa/ucm2";
in
{
  options.hardware.aurora.audio.enable = lib.mkOption {
    type = lib.types.bool;
    default = !config.androidDevices.recovery.enable;
    description = "Install Aurora Android 16 AudioReach topology and CS35L43 speaker firmware. Physical audio validation is pending.";
  };
  config = lib.mkIf cfg.audio.enable {
    hardware.firmware = [ cfg.firmwarePackage.audio ];
    environment.systemPackages = [ pkgs.alsa-utils ];
    environment.variables.ALSA_CONFIG_UCM2 = ucmDirectory;
    systemd.user.services.pipewire.environment.ALSA_CONFIG_UCM2 = ucmDirectory;
    systemd.user.services.pipewire-pulse.environment.ALSA_CONFIG_UCM2 = ucmDirectory;
    systemd.user.services.wireplumber.environment.ALSA_CONFIG_UCM2 = ucmDirectory;
  };
}
