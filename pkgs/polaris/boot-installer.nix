{
  writeShellApplication,
  coreutils,
  gnugrep,
  nix,
  util-linux,
  bash,
}:
{ roles }:
writeShellApplication {
  name = "polaris-install-boot";
  runtimeInputs = [
    coreutils
    gnugrep
    nix
    util-linux
  ];
  text = ''
    export POLARIS_STORAGE_ROLES=${roles}
    exec ${bash}/bin/bash ${../../devices/polaris/install-boot.sh} "$@"
  '';
}
