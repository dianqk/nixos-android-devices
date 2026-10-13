{
  config,
  lib,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices;
  board = config.hardware.sheng;
in
{
  nixpkgs.hostPlatform = "aarch64-linux";
  networking.hostName = lib.mkDefault (
    if cfg.recovery.enable then "${board.systemHostName}-recovery" else board.systemHostName
  );
  hardware.deviceTree.name = "qcom/sm8550-xiaomi-sheng.dtb";
  androidDevices = {
    platformKernelParams = [
      "androidboot.hardware=qcom"
      "androidboot.console=ttyMSM0"
    ];
    usb.signaller.address = lib.mkDefault "172.16.45.1/24";
    persistentImage.rootfs.device = lib.mkDefault "/dev/disk/by-partlabel/linux";
    boot = {
      actions = {
        reboot = lib.mkDefault true;
        poweroff = lib.mkDefault true;
        bootloader = lib.mkDefault true;
        recovery = lib.mkDefault true;
        recoveryTarget = lib.mkDefault "slot-b";
        android = lib.mkDefault true;
      };
      firmwarePackage = lib.mkDefault (androidPackages.mkUBoot { device = "sheng"; });
      directKernel.enable = lib.mkDefault true;
      uefi = {
        device = lib.mkDefault "/dev/disk/by-partlabel/linux-boot";
        requireStandardEsp = true;
      };
    };
    recovery = {
      targetHostName = board.systemHostName;
    };
  };
}
