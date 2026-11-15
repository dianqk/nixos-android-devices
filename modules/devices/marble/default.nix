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
    ./audio.nix
    ./modem.nix
    ./power.nix
    ./sensors.nix
  ];
  options.hardware.marble.firmwareSource = lib.mkOption {
    type = lib.types.path;
    default = androidPackages.devices.marble.firmware-source;
    defaultText = lib.literalExpression "androidPackages.devices.marble.firmware-source";
    description = "OS3.0.4.0.VMRMIXM firmware payload tree (adsp, audio, bluetooth, cdsp, dsp, gpu, modem, slpi, video, wlan, each with SHA256SUMS), for example from androidPackages.mkFirmwareArchive or a local directory.";
  };
  options.hardware.marble.wifiBoardFile = lib.mkOption {
    type = lib.types.path;
    default = "${config.hardware.marble.firmwareSource}/wlan/bd_m16tgf.elf";
    defaultText = lib.literalExpression ''"''${config.hardware.marble.firmwareSource}/wlan/bd_m16tgf.elf"'';
    description = "WCN6855 board data installed as ath11k `board.bin`: one of the `bd_m16t*.elf` files of the firmware source (`gf`: GlobalFoundries WCN6855, `gl`: global, `in`: India hardware).";
  };
  options.hardware.marble.firmwarePackage = lib.mkOption {
    type = lib.types.package;
    default = androidPackages.devices.marble.firmware.override {
      firmware-source = config.hardware.marble.firmwareSource;
      inherit (config.hardware.marble) wifiBoardFile;
    };
    defaultText = lib.literalExpression "androidPackages.devices.marble.firmware built from hardware.marble.firmwareSource";
    description = "Marble firmware package (outputs out, dsp, modem, audio and sensors).";
  };
  options.hardware.marble.ignoreUnusedRegulators = lib.mkOption {
    type = lib.types.bool;
    default = cfg.recovery.enable;
    defaultText = lib.literalExpression "config.androidDevices.recovery.enable";
    description = ''
      Pass `regulator_ignore_unused`, which keeps regulators the boot firmware
      left on that no Linux driver uses. Off by default for the installed
      system: there every supply in use (display, touch, UFS, Wi-Fi, audio,
      cameras) has a consumer, the late cleanup finds no unused regulator
      left on, and storage stays error-free under write load. On in RAM
      recovery, where dropping it is not yet verified.
    '';
  };
  options.hardware.marble.ignoreUnusedClocksAndDomains = lib.mkOption {
    type = lib.types.bool;
    default = cfg.recovery.enable;
    defaultText = lib.literalExpression "config.androidDevices.recovery.enable";
    description = ''
      Pass `clk_ignore_unused` and `pd_ignore_unused`, which keep clocks and
      power domains the boot firmware left on that no Linux driver has
      claimed. Off by default for the installed system: there the kernel
      switches them off at boot and display, touch, storage, USB, Wi-Fi,
      modem, sensors, audio devices, cameras and suspend keep working. On in
      RAM recovery, where turning them off is not yet verified.
    '';
  };
  options.hardware.marble.systemHostName = lib.mkOption {
    type = lib.types.strMatching "[a-z0-9][a-z0-9-]*";
    default = "marble";
    description = "Installed host name accepted by Marble recovery.";
  };
  config = {
    nixpkgs.hostPlatform = "aarch64-linux";
    networking.hostName = lib.mkDefault (
      config.hardware.marble.systemHostName + lib.optionalString cfg.recovery.enable "-recovery"
    );
    hardware.deviceTree.name = "qcom/sm8475-xiaomi-marble.dtb";
    # GPU, video, Wi-Fi and Bluetooth (out) and ADSP/SLPI (dsp). The modem
    # output is installed by hardware.marble.modem (modem.nix), the audio
    # output by hardware.marble.audio (audio.nix).
    hardware.firmware = [
      config.hardware.marble.firmwarePackage
      config.hardware.marble.firmwarePackage.dsp
    ];
    androidDevices = {
      enable = true;
      deviceName = "marble";
      usbController = "a600000.usb";
      # Built-in drivers (msm GPU, ath11k, btqca, iris) request their firmware
      # while the installed initrd runs. The RAM recovery leaves them without
      # firmware until it is verified there.
      initrdFirmware = lib.mkIf (!cfg.recovery.enable) [ config.hardware.marble.firmwarePackage ];
      hardwareKernelParams = [
        "androidboot.usbcontroller=a600000.usb"
        "androidboot.boot_devices=soc/1d84000.ufshc"
      ];
      persistentImage.rootfs.device = lib.mkDefault "/dev/disk/by-partlabel/linux";
      # U-Boot's Qualcomm A/B profile confirms slot B after loading the ESP
      # entry. Its reboot-to-bootloader/recovery/Android actions are not yet
      # verified on this board, so only reboot and power-off are offered.
      boot.actions = {
        reboot = lib.mkDefault true;
        poweroff = lib.mkDefault true;
      };
      boot.firmwarePackage = lib.mkDefault (androidPackages.mkUBoot { device = "marble"; });
      # ABL boots a header v4 image whose kernel is the board's U-Boot and
      # whose ramdisk is a FIT (kernel, initrd, DTB). ABL places that ramdisk
      # after vendor_boot_b's; U-Boot finds it there, copies it into its
      # fastboot buffer (0x7000000) and boots it. The FIT and U-Boot together
      # must fit the 100 MiB recovery_b.
      boot.recoveryLoader = "u-boot-fit";
      boot.recoveryFitMaximumBytes = 103809024;
      boot.uefi.device = lib.mkDefault "/dev/disk/by-partlabel/linux-boot";
      boot.uefi.requireStandardEsp = true;
      # Image metadata matching the board's U-Boot image (recovery and the
      # installed firmware are both U-Boot boot images).
      boot.android = {
        headerVersion = 4;
        osVersion = lib.mkDefault "16.0.0";
        osPatchLevel = lib.mkDefault "2026-08";
        base = "0x00000000";
        kernelOffset = "0x00008000";
        ramdiskOffset = "0x01000000";
        secondOffset = "0x00000000";
        tagsOffset = "0x00000100";
        pageSize = "4096";
        dtbs = [ "dtbs/qcom/sm8475-xiaomi-marble.dtb" ];
        # recovery_b capacity.
        maximumBytes = 104857600;
      };
      recovery = {
        targetHostName = config.hardware.marble.systemHostName;
        screenPackage = androidPackages.mkRecoveryScreen {
          device = "marble";
          features = [
            "ab-partitions"
            "recovery-daemon"
          ];
        };
        extendedStorageTools = true;
        daemon = {
          slotModel = "ab";
          compatible = "xiaomi,marble";
          controller = "1d84000.ufshc";
          slotMetadata = "qcom-gpt";
          # Assumed from the Xiaomi Aurora layout; BCB operations check the
          # actual misc capacity before writing and refuse a mismatch.
          miscBytes = 4194304;
        };
      };
      # dwc3 is peripheral-only in the board DT (no role switch).
      usb.signaller.hostMode = false;
      # The charger firmware detects the port type when the ADSP starts; a
      # gadget already pulling D+ up makes a charging port read as SDP
      # (100 mA input limit) instead of CDP.
      usb.signaller.chargerSupply = "qcom-battmgr-usb";
      usb.signaller.address = lib.mkDefault "172.16.48.1/24";
    };
    boot.consoleLogLevel = 8;
    boot.kernelParams = [
      "fbcon=font:TER16x32"
    ]
    # Community port defaults: permissive device links and no PCIe ASPM;
    # firmware-owned clocks, power domains and regulators are kept only where
    # chosen (by default in RAM recovery).
    ++ lib.optionals config.hardware.marble.ignoreUnusedClocksAndDomains [
      "clk_ignore_unused"
      "pd_ignore_unused"
    ]
    ++ lib.optional config.hardware.marble.ignoreUnusedRegulators "regulator_ignore_unused"
    ++ [
      "fw_devlink=permissive"
      "pcie_aspm=off"
    ];
  };
}
