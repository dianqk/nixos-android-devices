{
  lib,
  pkgs,
  androidPackages,
  ...
}:
{
  imports = [
    ./sensors
    ./packages
    ../xiaomi-mipps-auth.nix
  ];
  androidDevices = {
    kernelPackage = lib.mkDefault androidPackages.devices.sheng.kernel;

    boot.android = {
      base = "0x00000000";
      kernelOffset = "0x00008000";
      ramdiskOffset = "0x01000000";
      secondOffset = "0x00000000";
      tagsOffset = "0x01e00000";
      pageSize = "4096";
      dtbs = [ "dtbs/qcom/sm8550-xiaomi-sheng.dtb" ];
      maximumBytes = 201326592;
    };
  };

}
