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
      installed system. The kernel scales between 75 MHz (HS-G1) and
      850 MHz (HS-G4 with the SM8475 turbo configuration); sustained writes
      at 850 MHz measured clean, but system suspend and resume at that rate
      are not yet verified. Set to null to remove the limit.
    '';
  };

  config.services.udev.extraRules = lib.mkIf (ufsMaxFrequency != null) ufsRule;
  config.boot.initrd.services.udev.rules = lib.mkIf (ufsMaxFrequency != null) ufsRule;

  config.androidDevices = {

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
