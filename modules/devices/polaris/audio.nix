{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  ucm = androidPackages.devices.polaris.alsa-ucm;

  # alsa-lib probes cards at conf.d/${CardDriver}/${CardLongName}.conf, i.e.
  # conf.d/sdm845/xiaomi-XiaomiMiMIX2S.conf for this device. The stock UCM
  # ships its entry as conf.d/sdm845/"Xiaomi Mi MIX 2S".conf (card short name,
  # which is never probed) and references ${CardId}, which is undefined when
  # a configuration is loaded through conf.d. Wrap the stock package with the
  # corrected card entry and a HiFi file that hardcodes hw:0. Verified on
  # device: wpctl exposes "Built-in speakers" / "Built-in microphones"
  # instead of Dummy Output and playback through the tas2559 works.
  ucmFixed = pkgs.runCommand "polaris-alsa-ucm-fixed" { src = ucm; } ''
    mkdir -p "$out/share/alsa/ucm2/Polaris" "$out/share/alsa/ucm2/conf.d/sdm845"
    cp -r "$src/share/alsa/ucm2/." "$out/share/alsa/ucm2/"
    install -m644 ${./ucm/X2S-HiFi.conf} "$out/share/alsa/ucm2/Polaris/X2S-HiFi.conf"
    install -m644 ${./ucm/X2S-card.conf} "$out/share/alsa/ucm2/conf.d/sdm845/xiaomi-XiaomiMiMIX2S.conf"
  '';

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
    environment.variables.ALSA_CONFIG_UCM2 = "${ucmFixed}/share/alsa/ucm2";
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
