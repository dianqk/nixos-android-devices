{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.hardware.unicorn;
  ucm = androidPackages.devices.unicorn.audio-ucm;
  # Keep the upstream USB headset profiles and UCM entry point available.
  ucmTree = pkgs.symlinkJoin {
    name = "unicorn-ucm";
    paths = [
      ucm
      pkgs.alsa-ucm-conf
    ];
  };
  ucmDirectory = "${ucmTree}/share/alsa/ucm2";
  audioEnvironment.ALSA_CONFIG_UCM2 = ucmDirectory;
in
{
  imports = [ ./audio-runtime.nix ];
  options.hardware.unicorn.audio.enable = lib.mkOption {
    type = lib.types.bool;
    default = !config.androidDevices.recovery.enable;
    description = "Install Unicorn's WCD938x and 96 kHz CS35L41 AudioReach topology and ALSA tools.";
  };
  config = lib.mkIf (cfg.audio.enable && !config.androidDevices.recovery.enable) (
    lib.mkMerge [
      {
        hardware.firmware = [ androidPackages.devices.unicorn.audio-topology ];
        environment.systemPackages = [ (pkgs.alsa-utils.override { withPipewireLib = false; }) ];
      }
      (lib.mkIf cfg.audioRuntime.enable {
        # Raw Pro Audio probing opens unrouted MultiMedia1 and bypasses the
        # board's channel conversion and protected speaker UCM sequences.
        services.pipewire.wireplumber.extraConfig."51-unicorn-ucm" = {
          "monitor.alsa.rules" = [
            {
              matches = [
                {
                  "device.name" = "alsa_card.platform-sound";
                  "api.alsa.card.name" = "Xiaomi-12S-Pro";
                }
              ];
              actions.update-props = {
                "api.alsa.use-ucm" = true;
                "api.acp.disable-pro-audio" = true;
              };
            }
          ];
        };
        environment.systemPackages = [ ucm ];
        environment.etc."asound.conf".text = lib.mkAfter (
          builtins.readFile ../../../pkgs/unicorn/audio-normal/unicorn-stereo.conf
          + "\n"
          + builtins.readFile ../../../pkgs/unicorn/audio-normal/unicorn-mic.conf
        );
        environment.variables.ALSA_CONFIG_UCM2 = ucmDirectory;
        systemd.services = lib.mkIf config.services.pipewire.systemWide (
          lib.genAttrs [ "pipewire" "pipewire-pulse" "wireplumber" ] (_: {
            environment = audioEnvironment;
            requires = [ "unicorn-audio-prepare.service" ];
            after = [ "unicorn-audio-prepare.service" ];
          })
        );
        systemd.user.services = lib.mkIf (!config.services.pipewire.systemWide) (
          lib.genAttrs [ "pipewire" "pipewire-pulse" "wireplumber" ] (_: {
            environment = audioEnvironment;
          })
        );
      })
    ]
  );
}
