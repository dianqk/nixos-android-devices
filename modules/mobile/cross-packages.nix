{ config, lib, ... }:
{
  config = lib.mkIf config.androidDevices.enable {
    nixpkgs.overlays = [
      (
        _final: prev:
        lib.optionalAttrs (prev.stdenv.buildPlatform != prev.stdenv.hostPlatform) {
          enlightenment = prev.enlightenment.overrideScope (
            _scopeFinal: scopePrev: {
              # Meson's cross branch runs eolian_gen, edje_cc, eet and the other
              # generators from PATH. These must execute on the build host.
              efl = (import ../../pkgs { pkgs = prev; }).mkCrossEfl { efl = scopePrev.efl; };
            }
          );
        }
      )
    ];
  };
}
