{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  ucm = androidPackages.devices.polaris.alsa-ucm;

in
{
  options.hardware.polaris.audio.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Include Polaris audio firmware, ALSA UCM and DSP service mapping.";
  };
  config = lib.mkIf config.hardware.polaris.audio.enable {
    # pd-mapper reads ADSP service descriptors from the uncompressed profile tree.
    environment.systemPackages = [
      pkgs.alsa-utils
      (androidPackages.devices.polaris.multimedia-firmware)
    ];
    environment.pathsToLink = [ "/share/uncompressed-firmware" ];
    environment.variables.ALSA_CONFIG_UCM2 = "${ucm}/share/alsa/ucm2";
    systemd.user.services = lib.mkIf config.services.pipewire.enable {
      pipewire.environment.ALSA_CONFIG_UCM2 = config.environment.variables.ALSA_CONFIG_UCM2;
      pipewire-pulse = lib.mkIf config.services.pipewire.pulse.enable {
        environment.ALSA_CONFIG_UCM2 = config.environment.variables.ALSA_CONFIG_UCM2;
      };
      wireplumber = lib.mkIf config.services.pipewire.wireplumber.enable {
        environment.ALSA_CONFIG_UCM2 = config.environment.variables.ALSA_CONFIG_UCM2;
      };
    };
    # ADSP's APR services need the userspace service registry.
    systemd.services.polaris-pd-mapper.wantedBy = [ "multi-user.target" ];
  };
}
