{
  config,
  lib,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices;
  board = config.hardware.polaris;
in
{
  nixpkgs.hostPlatform = "aarch64-linux";
  networking.hostName = lib.mkDefault (
    if cfg.recovery.enable then "${board.systemHostName}-recovery" else board.systemHostName
  );
  hardware.deviceTree.name = "qcom/sdm845-xiaomi-polaris.dtb";
  androidDevices = {
    platformKernelParams = [
      "androidboot.hardware=qcom"
      "androidboot.console=ttyMSM0"
    ];
    usb.signaller.address = lib.mkDefault "172.16.42.1/24";
    persistentImage.rootfs.device = lib.mkDefault "/dev/disk/by-partlabel/userdata";
    boot = {
      firmwarePackage = lib.mkDefault (androidPackages.mkUBoot { device = "polaris"; });
      directKernel.enable = lib.mkDefault false;
      uefi = {
        device = lib.mkDefault "/dev/disk/by-partlabel/system";
        requireStandardEsp = false;
      };
    };
    recovery = {
      initialInstallAdapter = ../../../devices/polaris/initial-install.sh;
      targetHostName = board.systemHostName;
      bootPartitionLabel = "system";
    };
  };
}
