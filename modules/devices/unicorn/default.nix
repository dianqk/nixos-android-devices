{
  config,
  lib,
  androidPackages,
  pkgs,
  utils,
  ...
}:
let
  bluetoothIdentity = import ../../mobile/bluetooth-identity-service.nix { inherit lib pkgs utils; };
  cfg = config.androidDevices;
  firmware = config.hardware.unicorn.firmwarePackage;
  initrdFirmware = androidPackages.devices.unicorn.initrd-firmware.override {
    unicorn-firmware = firmware;
  };
in
{
  imports = [
    ../../mobile
    ./charging.nix
    ./audio.nix
    ./display.nix
    ./hardware-keys.nix
  ];
  options.hardware.unicorn.bluetoothIdentityFile = lib.mkOption {
    type = lib.types.nullOr bluetoothIdentity.pathType;
    default = null;
    description = ''
      Absolute device-side filename containing this handset's verified factory
      Bluetooth public address in displayed colon-separated byte order. The file
      must be a root-owned private regular file; its contents stay outside the
      Nix store. Null leaves Bluetooth identity provisioning disabled.
    '';
  };
  options.hardware.unicorn.firmwarePackage = lib.mkOption {
    type = lib.types.package;
    default = androidPackages.devices.unicorn.firmware;
    description = "Hash-checked Unicorn firmware package, including the OEM GPU, DSP and WLAN inputs.";
  };
  options.hardware.unicorn.systemHostName = lib.mkOption {
    type = lib.types.strMatching "[a-z0-9][a-z0-9-]*";
    default = "unicorn";
    description = "Installed Xiaomi 12S Pro host name accepted by recovery.";
  };
  config = {
    # The OEM WCN6855 firmware reports a zero permanent MAC on this board.
    # NetworkManager derives a persistent local address from its host identity
    # and connection UUID; USB networking remains excluded by usb-signaller.
    networking.networkmanager.settings."connection-unicorn-wifi" = {
      "match-device" = "driver:ath11k_pci";
      "wifi.cloned-mac-address" = "stable";
    };
    systemd.services.unicorn-bluetooth-identity =
      lib.mkIf
        (
          !cfg.recovery.enable
          && config.hardware.bluetooth.enable
          && config.hardware.unicorn.bluetoothIdentityFile != null
        )
        (
          bluetoothIdentity.mkService {
            identityFile = config.hardware.unicorn.bluetoothIdentityFile;
            boardCompatible = "xiaomi,unicorn";
            controllerCompatible = "qcom,wcn6855-bt";
          }
        );
    nixpkgs.hostPlatform = "aarch64-linux";
    hardware.enableRedistributableFirmware = lib.mkDefault false;
    hardware.firmware = lib.mkBefore [ firmware ];
    androidDevices.initrdFirmware = [ initrdFirmware ];
    boot.kernelModules.atkbd = lib.mkForce false;
    boot.kernel.sysctl."kernel.sysrq" = lib.mkDefault 16;
    networking.hostName = lib.mkDefault (
      config.hardware.unicorn.systemHostName + lib.optionalString cfg.recovery.enable "-recovery"
    );
    hardware.deviceTree.name = "qcom/sm8475-xiaomi-unicorn.dtb";
    androidDevices = {
      usb.signaller.followRole = lib.mkDefault true;
      enable = true;
      deviceName = "unicorn";
      usbController = "a600000.usb";
      usb.signaller.address = lib.mkDefault "172.16.47.1/24";
      persistentImage.rootfs.device = lib.mkDefault "/dev/disk/by-partlabel/linux";
      boot = {
        firmwarePackage = lib.mkDefault (androidPackages.mkUBoot { device = "unicorn"; });
        directKernel.enable = true;
        uefi = {
          device = lib.mkDefault "/dev/disk/by-partlabel/linux-boot";
          requireStandardEsp = true;
        };
        actions = {
          reboot = lib.mkDefault true;
          poweroff = lib.mkDefault true;
          bootloader = lib.mkDefault true;
          recovery = lib.mkDefault true;
          recoveryTarget = "slot-b";
        };
        android = {
          headerVersion = 2;
          kernelFile = "Image.gz";
          base = "0x00000000";
          kernelOffset = "0x00008000";
          ramdiskOffset = "0x01000000";
          secondOffset = "0x00000000";
          tagsOffset = "0x00000100";
          pageSize = "4096";
          dtbs = [ "dtbs/qcom/sm8475-xiaomi-unicorn.dtb" ];
          dtbPlacement = "boot-image";
          dtbOffset = "0x01f00000";
          dtbProperties = {
            "qcom,msm-id" = [
              531
              65536
              540
              65536
              530
              65536
            ];
            "qcom,board-id" = [
              65544
              0
            ];
          };
          maximumBytes = 104857600;
        };
      };
      recovery = {
        targetHostName = config.hardware.unicorn.systemHostName;
        screenPackage = androidPackages.mkRecoveryScreen {
          device = "unicorn";
          features = [
            "ab-partitions"
            "recovery-daemon"
          ];
        };
        extendedStorageTools = true;
        daemon = {
          linuxOnly = true;
          slotModel = "ab";
          compatible = "xiaomi,unicorn";
          controller = "1d84000.ufshc";
          slotMetadata = "qcom-gpt";
          miscBytes = 4194304;
        };
      };
    };
  };
}
