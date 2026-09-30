{ config, lib, ... }:
{
  imports = [
    ../../mobile
    ./boot.nix
    ./hardware.nix
    ./persistent-core.nix
    ./recovery.nix
  ];

  options.hardware.clover = {
    storageRolesFile = lib.mkOption {
      type = lib.types.path;
      default = ../../../devices/clover/storage-roles-unconfigured.sh;
      description = "Verified per-tablet GPT identity contract for recovery operations.";
    };
    systemHostName = lib.mkOption {
      type = lib.types.strMatching "[a-z0-9][a-z0-9-]*";
      default = "clover";
      description = "Installed Clover system host name accepted by recovery.";
    };
    rootUUID = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.strMatching "[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}"
      );
      default = null;
      description = "Optional existing root UUID to preserve when formatting or checking userdata.";
    };
    bluetoothAddress = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[0-9A-Fa-f:]{17}");
      default = null;
      description = "This tablet's Bluetooth public address, when known.";
    };
    wifiAddress = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[0-9A-Fa-f:]{17}");
      default = null;
      description = "This tablet's Wi-Fi public address, when known.";
    };
  };

  config = {
    assertions = lib.mkIf (!config.androidDevices.recovery.enable) [
      {
        assertion = config.networking.hostName == config.hardware.clover.systemHostName;
        message = "Clover systemHostName must match networking.hostName.";
      }
    ];
    androidDevices = {
      enable = true;
      deviceName = "clover";
      usbController = "a800000.usb";
      earlyKernelParams = [ "earlycon" ];
      hardwareKernelParams = [
        "androidboot.usbcontroller=a800000.dwc3"
        "androidboot.boot_devices=soc/c0c4000.sdhci"
      ];
    };
    boot.consoleLogLevel = 8;
  };
}
