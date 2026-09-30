{
  lib,
  runCommand,
  i2c-tools,
  python3Minimal,
}:
{
  systemHostName,
  rootLabel,
  espSizeBytes ? 1073741824,
  minimumRootBytes ? 17179869184,
}:
runCommand "asphalt-recovery-tools" { } ''
  mkdir -p $out/bin
  cp ${../../devices/ufs-linux-layout.jq} $out/bin/mobile-linux-layout.jq
  printf '%s\n' '#!/bin/sh' \
    'ASPHALT_SYSTEM_HOSTNAME=${lib.escapeShellArg systemHostName}' \
    'ASPHALT_ROOT_LABEL=${lib.escapeShellArg rootLabel}' \
    'MOBILE_ESP_BYTES=${toString (if espSizeBytes == null then 0 else espSizeBytes)}' \
    'MOBILE_MINIMUM_ROOT_BYTES=${toString minimumRootBytes}' \
    'ASPHALT_I2CTRANSFER=${i2c-tools}/bin/i2ctransfer' \
    > $out/bin/recovery
  tail -n +2 ${../../devices/asphalt/ab-recovery.sh} >> $out/bin/recovery
  chmod +x $out/bin/recovery
  printf '%s\n' '#!${python3Minimal}/bin/python3' > $out/bin/asphalt-uefi-plan
  tail -n +2 ${../../devices/asphalt/uefi-plan.py} >> $out/bin/asphalt-uefi-plan
  chmod +x $out/bin/asphalt-uefi-plan
  printf '%s\n' '#!/bin/sh' \
    'ASPHALT_SYSTEM_HOSTNAME=${lib.escapeShellArg systemHostName}' \
    'ASPHALT_ROOT_LABEL=${lib.escapeShellArg rootLabel}' \
    'MOBILE_ESP_BYTES=${toString (if espSizeBytes == null then 0 else espSizeBytes)}' \
    'MOBILE_MINIMUM_ROOT_BYTES=${toString minimumRootBytes}' \
    > $out/bin/asphalt-storage
  tail -n +2 ${../../devices/asphalt/storage.sh} >> $out/bin/asphalt-storage
  chmod +x $out/bin/asphalt-storage
''
