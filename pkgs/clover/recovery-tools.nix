{ lib, runCommand }:
{
  systemHostName,
  rootLabel,
  rootUUID,
  storageRolesFile,
}:
runCommand "clover-recovery-tools" { } ''
  mkdir -p $out/bin
  cp ${../../devices/clover/recovery-tools.sh} $out/bin/recovery-impl
  cp ${../../devices/clover/storage.sh} $out/bin/clover-storage
  cp ${../../devices/clover/check-partition.sh} $out/bin/clover-check-partition
  cp ${storageRolesFile} $out/bin/clover-storage-roles
  cat > $out/bin/recovery <<'EOF'
  #!/bin/sh
  CLOVER_PARTITION_CHECK=/bin/clover-check-partition
  export CLOVER_PARTITION_CHECK
  CLOVER_STORAGE_ROLES=/bin/clover-storage-roles
  CLOVER_ROOT_UUID=${lib.escapeShellArg (if rootUUID == null then "" else rootUUID)}
  export CLOVER_ROOT_UUID
  CLOVER_ROOT_LABEL=${lib.escapeShellArg rootLabel}
  CLOVER_SYSTEM_HOSTNAME=${lib.escapeShellArg systemHostName}
  export CLOVER_STORAGE_ROLES CLOVER_ROOT_LABEL CLOVER_SYSTEM_HOSTNAME
  exec /bin/recovery-impl "$@"
  EOF
  chmod +x $out/bin/recovery $out/bin/recovery-impl $out/bin/clover-storage
''
