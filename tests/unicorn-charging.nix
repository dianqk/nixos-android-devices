{
  flake,
  pkgs,
  buildSystem,
}:
let
  kernel = flake.legacyPackages.${buildSystem}.devices.unicorn.kernel;
  upstream = flake.legacyPackages.${buildSystem}.devices.unicorn.mipps-auth.upstream;
in
pkgs.stdenv.mkDerivation {
  pname = "unicorn-charging-tests";
  version = "1";
  inherit (kernel) src patches;
  nativeBuildInputs = [ pkgs.python3 ];
  phases = [
    "unpackPhase"
    "patchPhase"
    "buildPhase"
    "installPhase"
  ];
  patchFlags = [
    "-p1"
    "--fuzz=0"
  ];
  buildPhase = ''
    export PYTHONDONTWRITEBYTECODE=1
    mkdir -p "$TMPDIR/project/tests" "$TMPDIR/project/pkgs/unicorn"
    cp ${./unicorn-charging-kernel.py} "$TMPDIR/project/tests/unicorn-charging-kernel.py"
    cp ${./unicorn-charging-kernel.c} "$TMPDIR/project/tests/unicorn-charging-kernel.c"
    cp ${./unicorn-charging.py} "$TMPDIR/project/tests/unicorn-charging.py"
    cp ${../pkgs/unicorn/mipps-auth.py} "$TMPDIR/project/pkgs/unicorn/mipps-auth.py"
    python3 "$TMPDIR/project/tests/unicorn-charging-kernel.py" --source "$PWD"
    python3 "$TMPDIR/project/tests/unicorn-charging.py" --upstream ${upstream}
  '';
  installPhase = ''touch "$out"'';
}
