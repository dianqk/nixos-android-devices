{ lib, runCommand }:
{ systemHostName, requireRadioIdentity }:
runCommand "polaris-recovery-tools" { } ''
  mkdir -p $out/bin
  printf '%s\n' '#!/bin/sh' \
    'POLARIS_REQUIRE_RADIO_IDENTITY=${if requireRadioIdentity then "1" else "0"}' \
    'POLARIS_SYSTEM_HOSTNAME=${lib.escapeShellArg systemHostName}' \
    > $out/bin/recovery
  tail -n +2 ${../../devices/polaris/recovery-tools.sh} >> $out/bin/recovery
  cp ${../../devices/polaris/prepare-boot.sh} $out/bin/polaris-prepare-boot
  chmod +x $out/bin/polaris-prepare-boot
  chmod +x $out/bin/recovery
''
