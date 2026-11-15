# Carry the reboot argument (`reboot bootloader`, `reboot recovery`) across the
# shutdown ramfs. systemd-shutdown runs the system-shutdown hooks, pivots into
# /run/initramfs and executes its /shutdown, which issues the final reboot. That
# second instance reads /run/systemd/reboot-param relative to the new root, so
# without this copy the kernel receives a plain restart and its reboot-mode
# driver never sees the requested mode.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  coreutils = lib.getBin pkgs.coreutils;
  hook = pkgs.writeShellScript "reboot-param-to-shutdown-ramfs" ''
    [ "''${1-}" = reboot ] || exit 0
    [ -f /run/systemd/reboot-param ] || exit 0
    [ -x /run/initramfs/shutdown ] || exit 0
    ${coreutils}/bin/mkdir -p /run/initramfs/run/systemd || exit 0
    ${coreutils}/bin/cp /run/systemd/reboot-param /run/initramfs/run/systemd/reboot-param || true
    exit 0
  '';
in
{
  config = lib.mkIf (config.androidDevices.enable && config.systemd.shutdownRamfs.enable) {
    systemd.shutdown.reboot-param = hook;
  };
}
