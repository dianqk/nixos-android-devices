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
    enable = lib.mkEnableOption "VA-API over Qualcomm Iris/Venus V4L2 codecs";
    package = lib.mkPackageOption androidPackages "libva-v4l2" { };
  };

  config = lib.mkIf (cfg.enable && !config.androidDevices.recovery.enable) {
    hardware.graphics = {
      enable = true;
      extraPackages = [ cfg.package ];
    };
  };
}
