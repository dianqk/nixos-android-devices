{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  stage1Firmware = androidPackages.devices.sheng.initrd-firmware;
  udevadmWrapper = androidPackages.packaging.writeShellScript "udevadm-trigger-wrapper" ''
    out=$(${config.systemd.package}/bin/udevadm trigger "$@" 2>&1)
    ret=$?
    if [ "$ret" -ne 0 ]; then
      filtered=$(printf '%s\n' "$out" | grep -v qcom-battmgr \
        | grep -v 'Resource temporarily unavailable' || true)
      if [ -n "$filtered" ]; then
        printf '%s\n' "$filtered" >&2
        exit "$ret"
      fi
    fi
  '';
in
{
  androidDevices = {
    initrdFirmware = [ stage1Firmware ];
  };

  # ADSP and CDSP are large but compress substantially above the shared mobile
  # level. Keep both blobs compact without making the other mobile images
  # pay the compression cost.
  boot.initrd.compressorArgs = lib.mkForce [
    "-T0"
    "-19"
  ];

  # Bound the known qcom-battmgr cold-boot race without masking unrelated
  # udev trigger failures.
  systemd.services.systemd-udev-trigger.serviceConfig.ExecStart = lib.mkForce [
    ""
    "${udevadmWrapper} --type=subsystems --action=add"
    "${udevadmWrapper} --type=devices --action=add"
  ];
}
