{ lib, runCommand }:
{
  systemHostName,
  rootLabel,
  espSizeBytes ? 1073741824,
  minimumRootBytes ? 17179869184,
}:
runCommand "sheng-recovery-tools" { } ''
  mkdir -p $out/bin
  cp ${../../devices/ufs-linux-layout.jq} $out/bin/mobile-linux-layout.jq
  cp ${../../devices/sheng/slot-gate.sh} $out/bin/sheng-slot-gate
  cp ${../../devices/sheng/ab-recovery.sh} $out/bin/recovery-impl
  cp ${../../devices/sheng/storage.sh} $out/bin/sheng-storage
  cp ${../../devices/sheng/install-recovery.sh} $out/bin/sheng-install-recovery
  cp ${../../devices/sheng/check-recovery-image.sh} $out/bin/sheng-check-recovery-image
  chmod +x $out/bin/sheng-install-recovery $out/bin/sheng-check-recovery-image
  cat > $out/bin/recovery <<'EOF'
  #!/bin/sh
  SHENG_SYSTEM_HOSTNAME=${lib.escapeShellArg systemHostName}
  SHENG_ROOT_LABEL=${lib.escapeShellArg rootLabel}
  MOBILE_ESP_BYTES=${toString (if espSizeBytes == null then 0 else espSizeBytes)}
  MOBILE_MINIMUM_ROOT_BYTES=${toString minimumRootBytes}
  export SHENG_SYSTEM_HOSTNAME SHENG_ROOT_LABEL MOBILE_ESP_BYTES MOBILE_MINIMUM_ROOT_BYTES
  exec /bin/recovery-impl "$@"
  EOF
  chmod +x $out/bin/recovery $out/bin/recovery-impl $out/bin/sheng-storage
''
