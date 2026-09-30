{
  config,
  lib,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices;
  board = config.hardware.asphalt;
in
{
  nixpkgs.hostPlatform = "aarch64-linux";
  networking.hostName = lib.mkDefault (
    if cfg.recovery.enable then "${board.systemHostName}-recovery" else board.systemHostName
  );
  hardware.deviceTree.name = "qcom/sm8475-lenovo-asphalt.dtb";
  androidDevices = {
    platformKernelParams = [
      "androidboot.hardware=qcom"
      "androidboot.console=ttyMSM0"
    ];
    usb.signaller.address = lib.mkDefault "172.16.43.1/24";
    persistentImage.rootfs.device = lib.mkDefault "/dev/disk/by-partlabel/linux";
    boot = {
      firmwarePackage = lib.mkDefault (androidPackages.mkUBoot { device = "asphalt"; });
      directKernel.enable = lib.mkDefault false;
      uefi = {
        device = lib.mkDefault "/dev/disk/by-partlabel/linux-boot";
        requireStandardEsp = true;
      };
    };
    recovery = {
      initialInstallAdapter = ../../../devices/asphalt/initial-install.sh;
      targetHostName = board.systemHostName;
      bootPartitionLabel = "linux-boot";
    };
  };
}
