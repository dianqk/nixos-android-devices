{
  config,
  lib,
  androidPackages,
  ...
}:
{
  imports = [
    ../../mobile
    ./charger.nix
    ./audio.nix
    ./touch.nix
    ./sensors.nix
    ./modem.nix
  ];
  options.hardware.aurora.firmwareVariant = lib.mkOption {
    type = lib.types.enum [
      "android14"
      "android16"
    ];
    default = "android14";
    description = "OEM runtime firmware; current development requires the OS1.0.3.0.UNACNXM Android 14 base. Applies to recovery and the installed system.";
  };
  options.hardware.aurora.firmwarePackage = lib.mkOption {
    type = lib.types.package;
    default = androidPackages.devices.aurora.firmware.override {
      firmwareVariant = config.hardware.aurora.firmwareVariant;
    };
    description = "Aurora firmware package, optionally overridden with this handset's Bluetooth NVM.";
  };
  options.hardware.aurora.systemHostName = lib.mkOption {
    type = lib.types.strMatching "[a-z0-9][a-z0-9-]*";
    default = "aurora";
    description = "Installed host name accepted by Aurora recovery.";
  };
  config = {
    nixpkgs.hostPlatform = "aarch64-linux";
    networking.hostName = lib.mkDefault (
      config.hardware.aurora.systemHostName
      + lib.optionalString config.androidDevices.recovery.enable "-recovery"
    );
    hardware.deviceTree.name = "qcom/sm8650-xiaomi-aurora.dtb";
    hardware.firmware = [ config.hardware.aurora.firmwarePackage ];
    androidDevices = {
      enable = true;
      deviceName = "aurora";
      usbSerial = lib.mkDefault "aurora";
      usbController = "a600000.usb";
      kernelPackage = lib.mkDefault androidPackages.devices.aurora.kernel;
      initrdFirmware = [ config.hardware.aurora.firmwarePackage ];
      persistentImage.rootfs.device = lib.mkDefault "/dev/disk/by-partlabel/linux";
      boot.actions = {
        reboot = lib.mkDefault true;
        poweroff = lib.mkDefault true;
        bootloader = lib.mkDefault true;
        recovery = lib.mkDefault true;
        recoveryTarget = lib.mkDefault "slot-b";
        android = lib.mkDefault true;
      };
      boot.firmwarePackage = lib.mkDefault (androidPackages.mkUBoot { device = "aurora"; });
      boot.uefi.device = lib.mkDefault "/dev/disk/by-partlabel/linux-boot";
      boot.uefi.requireStandardEsp = true;
      recovery = {
        targetHostName = config.hardware.aurora.systemHostName;
        screenPackage = androidPackages.mkRecoveryScreen {
          device = "aurora";
          features = [
            "ab-partitions"
            "recovery-daemon"
          ];
        };
        extendedStorageTools = true;
        daemon = {
          slotModel = "ab";
          compatible = "xiaomi,aurora";
          controller = "1d84000.ufshc";
          slotMetadata = "qcom-gpt";
          miscBytes = 4194304;
        };
      };
      boot.android = {
        headerVersion = 0;
        # Stock OS3.0.7.0.WNACNXM boot header; ABL rejects a zero OS version
        # when the experimental slot has AVB verification disabled.
        osVersion = lib.mkDefault "14.0.0";
        osPatchLevel = lib.mkDefault "2026-02-01";
        base = "0x00000000";
        kernelOffset = "0x00008000";
        # ABL loads the gzip payload at a 512 KiB offset. A branch wrapper
        # places the real, unchanged Image at the next 2 MiB boundary.
        arm64LoadOffset = 524288;
        ramdiskOffset = "0x01000000";
        secondOffset = "0x00000000";
        tagsOffset = "0x01e00000";
        pageSize = "4096";
        dtbs = [ "dtbs/qcom/sm8650-xiaomi-aurora.dtb" ];
        maximumBytes = 100663296;
      };
      usb.signaller.roleSwitch = "a600000.usb-role-switch";
    };
    boot.consoleLogLevel = 8;
    boot.kernelParams = [ "fbcon=font:TER16x32" ];
  };
}
