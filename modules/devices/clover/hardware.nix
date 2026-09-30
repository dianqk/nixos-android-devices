{
  lib,
  pkgs,
  androidPackages,
  ...
}:
{
  androidDevices = {
    kernelPackage = lib.mkDefault androidPackages.devices.clover.kernel;

    boot.android = {
      base = "0x00000000";
      kernelOffset = "0x00008000";
      ramdiskOffset = "0x01000000";
      secondOffset = "0x00f00000";
      tagsOffset = "0x00000100";
      pageSize = "4096";
      dtbs = [ "dtbs/qcom/sdm660-xiaomi-clover.dtb" ];
      maximumBytes = 67108864;
    };
  };
}
