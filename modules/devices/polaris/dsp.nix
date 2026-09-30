{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.hardware.polaris;
  pdMapper = androidPackages.pd-mapper;
in
{
  config = lib.mkIf (cfg.radio.enable || cfg.audio.enable) {
    environment.systemPackages = [ pkgs.qrtr ];
    systemd.services.qrtr-ns.serviceConfig.ExecStart = "${pkgs.qrtr}/bin/qrtr-ns -f 1";
    systemd.services.polaris-pd-mapper = {
      requires = [ "qrtr-ns.service" ];
      after = [ "qrtr-ns.service" ];
      serviceConfig = {
        ExecStart = "${pdMapper}/bin/pd-mapper";
        Restart = "no";
      };
    };
  };
}
