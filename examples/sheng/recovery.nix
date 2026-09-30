{ androidPackages, lib, ... }:
{
  imports = [ ./baseline.nix ];
  androidDevices.recovery.enable = true;
  # Retain the proven independent RAM recovery while testing installed kernels.
  androidDevices.kernelPackage = lib.mkForce androidPackages.devices.sheng.kernel-testing;
}
