{ flake, pkgs, buildSystem }:
let
  kernel = flake.legacyPackages.${buildSystem}.devices.unicorn.kernel;
in
pkgs.stdenv.mkDerivation {
  pname = "unicorn-display-lifecycle-tests";
  version = "1";
  inherit (kernel) src patches;
  nativeBuildInputs = [ pkgs.python3 ];
  phases = [ "unpackPhase" "patchPhase" "buildPhase" "installPhase" ];
  # Apply the evaluated queue, including the kernel's own patches, to real source.
  patchFlags = [ "-p1" "--fuzz=0" ];
  buildPhase = ''
    export PYTHONDONTWRITEBYTECODE=1
    cp ${./unicorn-display-lifecycle.py} "$TMPDIR/unicorn-display-lifecycle.py"
    cp ${./unicorn-display-lifecycle.c} "$TMPDIR/unicorn-display-lifecycle.c"
    python3 "$TMPDIR/unicorn-display-lifecycle.py" --source "$PWD"
  '';
  installPhase = ''touch "$out"'';
}
