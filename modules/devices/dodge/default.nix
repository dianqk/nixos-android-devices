{
  config,
  lib,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices;

in
{
  imports = [
    ../../mobile
    ./modem.nix
    ./audio.nix
    ./sensors.nix
    ./touch.nix
    ./wireless-care.nix
  ];

  options.hardware.dodge.bootChoice.enable = lib.mkEnableOption "host-validated same-slot owned boot-choice integration (requires matched patched firmware/boot image and a separate deployment trial)";
  options.hardware.dodge.firmwareSource = lib.mkOption {
    type = lib.types.path;
    default = androidPackages.devices.dodge.firmware-source;
    defaultText = lib.literalExpression "androidPackages.devices.dodge.firmware-source";
    description = "Dodge Linux payload tree with lib/firmware, share/alsa/ucm2, SSC registry/runtime data and SHA256SUMS, from mkFirmwareArchive or a local directory.";
  };
  options.hardware.dodge.firmwarePackage = lib.mkOption {
    type = lib.types.package;
    default = androidPackages.devices.dodge.firmware.override {
      firmware-source = config.hardware.dodge.firmwareSource;
      includeADSP = !cfg.recovery.enable;
      includeVideo = !cfg.recovery.enable;
    };
    defaultText = lib.literalExpression "androidPackages.devices.dodge.firmware built from hardware.dodge.firmwareSource";
    description = "Dodge firmware mapped to the Linux driver paths.";
  };
  options.hardware.dodge.systemHostName = lib.mkOption {
    type = lib.types.strMatching "[a-z0-9][a-z0-9-]*";
    default = "dodge";
    description = "Installed system host name accepted by Dodge recovery.";
  };

  config = {
    nixpkgs.hostPlatform = "aarch64-linux";
    networking.hostName = lib.mkDefault (
      config.hardware.dodge.systemHostName + lib.optionalString cfg.recovery.enable "-recovery"
    );
    hardware.deviceTree.name =
      "qcom/sm8750-oneplus-dodge" + lib.optionalString cfg.recovery.enable "-recovery" + ".dtb";
    hardware.firmware = [ config.hardware.dodge.firmwarePackage ];
    boot.kernelParams = lib.optionals cfg.recovery.enable [
      "clk_ignore_unused"
      "pd_ignore_unused"
      "regulator_ignore_unused"
      "cpuidle.off=1"
    ]
    ++ [
      "fbcon=font:TER16x32"
    ];
    androidDevices = {
      enable = true;
      deviceName = "dodge";
      initrdFirmware = [ config.hardware.dodge.firmwarePackage ];
      panicTimeout = lib.mkDefault 1;
      usbController = "a600000.usb";
      usb.signaller = {
        address = lib.mkDefault "172.16.49.1/24";
        hostMode = false;
        manageRole = lib.mkDefault cfg.recovery.enable;
      };
      persistentImage.rootfs.device = lib.mkDefault "/dev/disk/by-partlabel/linux";
      initrdUsb.ssh.hostKeyStorage.enable = false;
      boot = {
        actions.android = lib.mkDefault (!config.hardware.dodge.bootChoice.enable);
        actions.androidSameSlot = config.hardware.dodge.bootChoice.enable;
        uefi.bootChoice.enable = config.hardware.dodge.bootChoice.enable;
        standaloneFirmwareImage = false;
        firmwarePackage = lib.mkDefault (androidPackages.mkUBoot { device = "dodge"; });
        recoveryLoader = "fit";
        recoveryFitMaximumBytes = 67108864;
        android.dtbs = [ "dtbs/${config.hardware.deviceTree.name}" ];
        uefi = {
          device = lib.mkDefault "/dev/disk/by-partlabel/linux-boot";
          requireStandardEsp = true;
        };
      };
      recovery = {
        targetHostName = config.hardware.dodge.systemHostName;
        screen.enable = lib.mkDefault false;
        consoleBlankSeconds = lib.mkIf (!cfg.recovery.screen.enable) (lib.mkDefault 60);
        screenPackage = androidPackages.mkRecoveryScreen {
          device = "dodge";
          features = [
            "ab-partitions"
            "recovery-daemon"
          ];
        };
        extendedStorageTools = true;
        daemon = {
          slotModel = "ab";
          compatible = "oneplus,dodge";
          controller = "1d84000.ufs";
          slotMetadata = "qcom-gpt";
          miscBytes = 1048576;
        };
      };
    };
  };
}
