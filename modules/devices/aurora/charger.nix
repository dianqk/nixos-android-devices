{ config, lib, ... }:
{
  androidDevices.charger = {
    enable = lib.mkDefault true;
    firmware = [ config.hardware.aurora.firmwarePackage ];
    # SM8650 display, keys, ADSP, GLINK and battmgr are built into this kernel.
    # No sensor/audio userspace or persistent filesystem is needed here.
    kernelModules = [ ];
    kernelParams = [
      "clk_ignore_unused"
      "pd_ignore_unused"
    ];
    deviceTree = "${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}";
    batteryPath = "/sys/class/power_supply/qcom-battmgr-bat";
    inputPath = "/sys/class/power_supply/qcom-battmgr-usb";
    inputName = "pmic_pwrkey";
    framebuffer = "msmdrmfb";
    backlightPath = "/sys/class/backlight/n1-panel";
    display.fontWidth = 32;
  };
}
