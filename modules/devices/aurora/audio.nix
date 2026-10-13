{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.aurora;
  ucmDirectory = "${cfg.firmwarePackage.audio}/share/alsa/ucm2";
in
{
  options.hardware.aurora.audio.enable = lib.mkOption {
    type = lib.types.bool;
    default = !config.androidDevices.recovery.enable && cfg.firmwareVariant == "android14";
    description = "Install Aurora Android 14 AudioReach topology and CS35L43 speaker firmware. Physical audio validation is pending.";
  };
  config = lib.mkIf cfg.audio.enable {
    assertions = [ {
      assertion = cfg.firmwareVariant == "android14";
      message = "Aurora audio currently requires the Android 14 firmware baseline.";
    } ];
    hardware.firmware = [ cfg.firmwarePackage.audio ];
    environment.systemPackages = [ pkgs.alsa-utils ];
    environment.variables.ALSA_CONFIG_UCM2 = ucmDirectory;
    systemd.user.services.pipewire.environment.ALSA_CONFIG_UCM2 = ucmDirectory;
    systemd.user.services.pipewire-pulse.environment.ALSA_CONFIG_UCM2 = ucmDirectory;
    systemd.user.services.wireplumber.environment.ALSA_CONFIG_UCM2 = ucmDirectory;
  };
}
