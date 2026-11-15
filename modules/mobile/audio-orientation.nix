# Optional speaker routing that follows the screen orientation. Applications
# send FL/FR to the speaker sink, which always reaches the same physical
# speakers. Device modules describe, per output transform, which mixer
# settings put left and right on the speakers at the left and right edges; the
# consumer enables the policy and calls the applier from its rotation handler.
{
  config,
  lib,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices.audio.orientation;
  orientations = [
    "normal"
    "90"
    "180"
    "270"
  ];
  entry = lib.types.submodule {
    options = {
      card = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "ALSA card id, name or index; `null` uses `card` of this option set.";
      };
      control = lib.mkOption {
        type = lib.types.str;
        example = "AMP1 ASPRX1 Slot Position";
        description = "Mixer control name, as passed to `amixer cset name=...`.";
      };
      value = lib.mkOption {
        type = lib.types.either lib.types.int lib.types.str;
        description = "Value for the control: a number or an enumerated item name.";
      };
    };
  };
  resolve = e: {
    inherit (e) control value;
    card = if e.card == null then cfg.card else e.card;
  };
  routes = lib.mapAttrs (_: map resolve) cfg.routes;
  unresolved = lib.filter (e: e.card == null) (lib.concatLists (lib.attrValues routes));
in
{
  options.androidDevices.audio.orientation = {
    enable = lib.mkEnableOption ''
      speaker routing that follows the screen orientation. Installs
      `/etc/android-audio-orientation.json`, the `android-audio-orientation`
      applier, and a user service that reapplies the last orientation after
      WirePlumber activates the audio profile
    '';

    package = lib.mkPackageOption androidPackages "audio-orientation" { pkgsText = "androidPackages"; };

    card = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "MySoundCard";
      description = "Default ALSA card for entries that do not name one.";
    };

    routes = lib.mkOption {
      type = lib.types.submodule {
        options = lib.genAttrs orientations (
          name:
          lib.mkOption {
            type = lib.types.listOf entry;
            default = [ ];
            description = ''
              Mixer settings for output transform `${name}`. An empty list leaves
              the routing unchanged in this orientation.
            '';
          }
        );
      };
      default = { };
      description = ''
        Speaker routing per output transform (`normal`, `90`, `180`, `270`, as
        named by wlroots compositors and Niri). Device modules provide this data.
        Flipped transforms mirror the image, so they have no routing; the applier
        rejects them.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && !config.androidDevices.recovery.enable) {
    assertions = [
      {
        assertion = unresolved == [ ];
        message = "androidDevices.audio.orientation: entries without a card need androidDevices.audio.orientation.card.";
      }
    ];

    environment.systemPackages = [ cfg.package ];
    environment.etc."android-audio-orientation.json".text = builtins.toJSON { orientations = routes; };

    # Activating the UCM verb rewrites the routing controls. Follow WirePlumber
    # starts and restarts, then hold the recorded orientation while it settles.
    systemd.user.services.android-audio-orientation = {
      description = "Reapply the speaker routing for the screen orientation";
      wantedBy = [ "wireplumber.service" ];
      partOf = [ "wireplumber.service" ];
      after = [ "wireplumber.service" ];
      unitConfig.ConditionUser = "!@system";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe cfg.package} restore";
      };
    };
  };
}
