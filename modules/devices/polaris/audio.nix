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

      # The ASoC card is only registered once the TAS2559 amplifier on i2c-5 has
      # been powered up, which happens roughly 30 s into boot - well after
      # PipeWire and WirePlumber have started. WirePlumber does not pick the
      # card up when it appears later, so the session ends up with no sink and
      # no source at all until WirePlumber is restarted by hand.
      #
      # Wait for the card, then nudge WirePlumber only if its object graph has
      # no ALSA card in it. Both the user session and the sound device nodes are
      # available to this unit, so no privileges are needed.
      polaris-audio-rescan = lib.mkIf config.services.pipewire.wireplumber.enable {
        description = "Pick up the Polaris sound card once it registers";
        wantedBy = [ "default.target" ];
        after = [ "wireplumber.service" ];
        wants = [ "wireplumber.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "polaris-audio-rescan" ''
            set -u
            # Sessions without PipeWire (e.g. root's) have nothing to rescan.
            [ -S "''${XDG_RUNTIME_DIR:-/nonexistent}/pipewire-0" ] || exit 0
            i=0
            while [ ! -e /dev/snd/controlC0 ] && [ "$i" -lt 60 ]; do
              sleep 1
              i=$((i + 1))
            done
            # The ADC kcontrols come up at 0 (-inf dB) after boot: the capture
            # device's UCM sequence is not applied for the probe/early streams,
            # so a recording started cold is silent. Set the capture gain once
            # the card is usable (0..20 range, 15 = 3.75 dB).
            i=0
            while [ "$i" -lt 20 ]; do
              ${pkgs.alsa-utils}/bin/amixer -c 0 sset 'ADC1' 15 >/dev/null 2>&1 &&
                ${pkgs.alsa-utils}/bin/amixer -c 0 sset 'ADC3' 15 >/dev/null 2>&1 &&
                break
              sleep 1
              i=$((i + 1))
            done

            # Give the monitor a moment to enumerate a card that showed up late.
            sleep 3
            if ! ${pkgs.pipewire}/bin/pw-dump 2>/dev/null |
              ${pkgs.gnugrep}/bin/grep -q '"api.alsa.card.longname"'; then
              ${pkgs.systemd}/bin/systemctl --user restart wireplumber.service || true
            fi
          '';
        };
      };
    };
    # ADSP's APR services need the userspace service registry.
    systemd.services.polaris-pd-mapper.wantedBy = [ "multi-user.target" ];
  };
}
