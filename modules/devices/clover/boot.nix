{
  config,
  lib,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices;
  board = config.hardware.clover;
in
{
  nixpkgs.hostPlatform = "aarch64-linux";
  networking.hostName = lib.mkDefault (
    if cfg.recovery.enable then "${board.systemHostName}-recovery" else board.systemHostName
  );
  hardware.deviceTree.name = "qcom/sdm660-xiaomi-clover.dtb";
  androidDevices = {
    platformKernelParams = [
      "androidboot.hardware=qcom"
      "androidboot.console=ttyMSM0"
    ];
    usb.signaller.address = lib.mkDefault "172.16.44.1/24";
    persistentImage.rootfs.device = lib.mkDefault "/dev/disk/by-partlabel/userdata";
    boot = {
      actions = {
        reboot = lib.mkDefault true;
        poweroff = lib.mkDefault true;
        bootloader = lib.mkDefault true;
        recovery = lib.mkDefault true;
      };
      firmwarePackage = lib.mkDefault (androidPackages.mkUBoot { device = "clover"; });
      # ABL boots recovery, whose ramdisk is a FIT (kernel, initrd, DTB) that
      # this U-Boot copies into its fastboot buffer and boots. ABL does not
      # start an image whose ramdisk exceeds 35 MiB (36 MiB failed on
      # hardware); an LZMA kernel keeps the FIT below that.
      recoveryLoader = "u-boot-fit";
      recoveryFitKernelCompression = "lzma";
      recoveryFitMaximumBytes = 36700160;
      directKernel.enable = lib.mkDefault true;
      uefi = {
        device = lib.mkDefault "/dev/disk/by-partlabel/system";
        requireStandardEsp = false;
        # The physical system partition keeps its stock 3 GiB size; the
        # recovery ESP role checks a plausible range instead.
        espSizeBytes = lib.mkDefault null;
      };
    };
    recovery.targetHostName = board.systemHostName;
  };
}
