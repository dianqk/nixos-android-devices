{
  lib,
  pkgs,
  androidPackages,
  ...
}:
{
  androidDevices = {
    kernelPackage = lib.mkDefault androidPackages.devices.asphalt.kernel;

    boot.android = {
      # Keep the kernel uncompressed like Lenovo's stock boot images, while a
      # v2 header carries the mainline DTB without depending on vendor_boot_a.
      kernelFile = "Image";
      headerVersion = 2;
      base = "0x00000000";
      kernelOffset = "0x00008000";
      ramdiskOffset = "0x01000000";
      secondOffset = "0x00000000";
      tagsOffset = "0x00000100";
      pageSize = "4096";
      dtbs = [ "dtbs/qcom/sm8475-lenovo-asphalt.dtb" ];
      dtbPlacement = "boot-image";
      dtbOffset = "0x01f00000";
      maximumBytes = 100663296;
    };
  };
}
