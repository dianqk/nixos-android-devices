{ pkgs, androidPackages, ... }:
let
  ucm = androidPackages.devices.asphalt.alsa-ucm;
  ucmDirectory = "${ucm}/share/alsa/ucm2";
in
{
  environment.systemPackages = [ pkgs.alsa-utils ];
  environment.variables.ALSA_CONFIG_UCM2 = ucmDirectory;
  systemd.user.services.pipewire.environment.ALSA_CONFIG_UCM2 = ucmDirectory;
  systemd.user.services.pipewire-pulse.environment.ALSA_CONFIG_UCM2 = ucmDirectory;
  systemd.user.services.wireplumber.environment.ALSA_CONFIG_UCM2 = ucmDirectory;
}
