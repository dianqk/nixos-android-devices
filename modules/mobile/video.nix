{
  config,
  lib,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices.video.vaapi;
in
{
  options.androidDevices.video.vaapi = {
    enable = lib.mkEnableOption "VA-API over supported stateful V4L2 codecs";
    package = lib.mkPackageOption androidPackages "libva-v4l2" { };
  };

  config = lib.mkIf (cfg.enable && !config.androidDevices.recovery.enable) {
    environment.variables.GST_VA_ALL_DRIVERS = "1";
    # List form merges with board-specific manager defaults (for example UCM).
    systemd.user.settings.Manager.DefaultEnvironment = [ "GST_VA_ALL_DRIVERS=1" ];
    hardware.graphics = {
      enable = true;
      extraPackages = [ cfg.package ];
    };
  };
}
