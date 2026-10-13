{ config, lib, ... }:
{
  imports = [
    ../../mobile
    ./boot.nix
    ./hardware.nix
    ./system-hardware.nix
    ./power.nix
    ./mobile.nix
    ./recovery.nix
  ];

  options.hardware.sheng = {
    systemHostName = lib.mkOption {
      type = lib.types.strMatching "[a-z0-9][a-z0-9-]*";
      default = "sheng";
      description = "Installed Sheng system host name accepted by recovery.";
    };
    wifiMacAddress = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[0-9A-Fa-f:]{17}");
      default = null;
      description = "Stable Wi-Fi MAC for this tablet; use its factory address when known.";
    };
    bluetoothAddress = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[0-9A-Fa-f:]{17}");
      default = null;
      description = "This tablet's Bluetooth public address, when required by its controller.";
    };
  };

  config = {
    assertions = lib.mkIf (!config.androidDevices.recovery.enable) [
      {
        assertion = config.networking.hostName == config.hardware.sheng.systemHostName;
        message = "Sheng systemHostName must match networking.hostName.";
      }
    ];
    androidDevices = {
      enable = true;
      deviceName = "sheng";
      usbController = "a600000.usb";
      earlyKernelParams = [
        "console=ttyMSM0,115200n8"
        "loglevel=8"
      ];
      hardwareKernelParams = [ "androidboot.boot_devices=soc/1d84000.ufshc" ];
    };
  };
}
