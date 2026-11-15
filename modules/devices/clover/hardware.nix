{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
{
  androidDevices = {

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
    # The PM660 RTC (rtc@6000) has neither allow-set-time nor an offset nvmem
    # cell, so Linux can read but not set it.
    clock.rtcOffset.enable = lib.mkDefault (!config.androidDevices.recovery.enable);
  };
}
