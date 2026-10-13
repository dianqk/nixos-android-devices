{ config, lib, ... }:
let
  # Keep clocks and power domains the boot firmware left on that no Linux
  # driver has claimed.
  ignoreUnusedParams = [
    "clk_ignore_unused"
    "pd_ignore_unused"
  ];
in
{
  options.hardware.asphalt.ignoreUnusedClocksAndDomains = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Pass clk_ignore_unused and pd_ignore_unused to the installed system. The charger keeps them regardless.";
  };

  imports = [
    ../../mobile
    ./boot.nix
    ./charger.nix
    ./radio.nix
    ./hardware.nix
    ./firmware.nix
    ./sensors.nix
    ./audio
    ./recovery.nix
  ];
  config.androidDevices = {
    enable = true;
    deviceName = "asphalt";
    usbController = "a600000.usb";
    earlyKernelParams = [
      "console=ttyMSM0,115200n8"
      "loglevel=8"
    ];
    hardwareKernelParams = [
      "androidboot.usbcontroller=a600000.usb"
      "androidboot.boot_devices=soc/1d84000.ufshc"
    ]
    ++ lib.optionals config.hardware.asphalt.ignoreUnusedClocksAndDomains ignoreUnusedParams;
  };
}
