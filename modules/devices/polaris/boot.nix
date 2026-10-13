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
      actions = {
        reboot = lib.mkDefault true;
        poweroff = lib.mkDefault true;
        bootloader = lib.mkDefault true;
        recovery = lib.mkDefault true;
      };
      firmwarePackage = lib.mkDefault (androidPackages.mkUBoot { device = "polaris"; });
      directKernel.enable = lib.mkDefault false;
      uefi = {
        device = lib.mkDefault "/dev/disk/by-partlabel/system";
        requireStandardEsp = false;
      };
    };
    initrdUsb.ssh.hostKeyStorage = {
      compatible = "xiaomi,polaris";
      controller = "1d84000.ufshc";
    };
    recovery.targetHostName = board.systemHostName;
  };
}
