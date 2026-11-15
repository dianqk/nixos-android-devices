{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.hardware.marble;
  ucmDirectory = "${androidPackages.devices.marble.alsa-ucm}/share/alsa/ucm2";
in
{
  options.hardware.marble.audio.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Install the Marble speaker and microphone support: the AW88263S
      amplifier ACF (from hardware.marble.firmwareSource), the AudioReach
      topology (tertiary TDM speakers, WCD9385 capture) and the ALSA UCM
      configuration for PipeWire. Off by default: there is no host speaker
      protection. Verified on hardware: both speakers and the bottom
      microphone. Voice calls, the earpiece and wired headsets are not
      supported.
    '';
  };
  config = lib.mkIf cfg.audio.enable {
    hardware.firmware = [
      cfg.firmwarePackage.audio
      androidPackages.devices.marble.audio-topology
    ];
    environment.systemPackages = [ pkgs.alsa-utils ];
    environment.variables.ALSA_CONFIG_UCM2 = ucmDirectory;
    systemd.user.services.pipewire.environment.ALSA_CONFIG_UCM2 = ucmDirectory;
    systemd.user.services.pipewire-pulse.environment.ALSA_CONFIG_UCM2 = ucmDirectory;
    systemd.user.services.wireplumber.environment.ALSA_CONFIG_UCM2 = ucmDirectory;
  };
}
