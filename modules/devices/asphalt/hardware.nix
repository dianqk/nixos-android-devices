{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  ufsMaxFrequency = config.hardware.asphalt.ufs.maxFrequency;
  # Limit UFS clock scaling as soon as the controller's devfreq device appears.
  # Scaled down, the link also stays in its low HS gear.
  ufsRule = ''
    ACTION=="add|change", SUBSYSTEM=="devfreq", KERNEL=="1d84000.ufshc", ATTR{max_freq}="${toString ufsMaxFrequency}"
  '';
in
{
  options.hardware.asphalt.ufs.maxFrequency = lib.mkOption {
    type = lib.types.nullOr lib.types.ints.positive;
    default = 75000000;
    example = null;
    description = ''
      Upper limit in Hz for UFS clock scaling, applied in the initrd and the
      installed system. Once fw_devlink sync_state() releases the boot-time
      interconnect and power votes, transfers at the higher UFS clock and
      gear raise PHY/data-link errors and controller resets on Linux
      7.3.0-rc6; 75 MHz measured clean. Set to null to remove the limit.
    '';
  };

  config.services.udev.extraRules = lib.mkIf (ufsMaxFrequency != null) ufsRule;
  config.boot.initrd.services.udev.rules = lib.mkIf (ufsMaxFrequency != null) ufsRule;

  config.androidDevices = {
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
