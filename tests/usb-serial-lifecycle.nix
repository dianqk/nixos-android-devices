{ flake, pkgs, buildSystem }:
let
  kernel = flake.legacyPackages.${buildSystem}.devices.unicorn.kernel;
in
pkgs.stdenv.mkDerivation {
  pname = "usb-serial-lifecycle-tests";
  version = "1";
  inherit (kernel) src patches;
  nativeBuildInputs = [ pkgs.python3 ];
  phases = [ "unpackPhase" "patchPhase" "buildPhase" "installPhase" ];
  # Exercise the real functions after applying the evaluated device queue.
  patchFlags = [ "-p1" "--fuzz=0" ];
  buildPhase = ''
    export PYTHONDONTWRITEBYTECODE=1
    cp ${./usb-serial-lifecycle.py} "$TMPDIR/usb-serial-lifecycle.py"
    cp ${./usb-serial-lifecycle.c} "$TMPDIR/usb-serial-lifecycle.c"
    python3 "$TMPDIR/usb-serial-lifecycle.py" --source "$PWD"
  '';
  installPhase = ''touch "$out"'';
}
