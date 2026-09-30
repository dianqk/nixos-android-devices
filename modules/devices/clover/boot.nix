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
      firmwarePackage = lib.mkDefault (androidPackages.mkUBoot { device = "clover"; });
      directKernel.enable = lib.mkDefault true;
      uefi = {
        device = lib.mkDefault "/dev/disk/by-partlabel/system";
        requireStandardEsp = false;
      };
    };
    recovery = {
      initialInstallAdapter = ../../../devices/clover/initial-install.sh;
      targetHostName = board.systemHostName;
      bootPartitionLabel = "system";
      extraTargetConfig = ''
        CLOVER_STORAGE_ROLES=/bin/clover-storage-roles
        CLOVER_ROOT_UUID=${lib.escapeShellArg (if board.rootUUID == null then "" else board.rootUUID)}
      '';
    };
  };
}
