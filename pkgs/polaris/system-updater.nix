{
  lib,
  writeShellApplication,
  coreutils,
  diffutils,
  gawk,
  gnugrep,
  nix,
  util-linux,
  bash,
}:
{ roles, systemHostName }:
writeShellApplication {
  name = "polaris-update-system";
  runtimeInputs = [
    coreutils
    diffutils
    gawk
    gnugrep
    nix
    util-linux
  ];
  text = ''
    export POLARIS_STORAGE_ROLES=${roles}
    export POLARIS_SYSTEM_HOSTNAME=${lib.escapeShellArg systemHostName}
    exec ${bash}/bin/bash ${../../devices/polaris/update-system.sh} "$@"
  '';
}
