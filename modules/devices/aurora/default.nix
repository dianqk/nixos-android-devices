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
    ./charging.nix
    ./audio.nix
    ./touch.nix
    ./sensors.nix
    ./modem.nix
    (lib.mkRemovedOptionModule [
      "hardware"
      "aurora"
      "firmwareVariant"
    ] "Aurora runtime firmware is the OS3.0.308.0.WNACNXM (Android 16) release only.")
  ];
  options.hardware.aurora.firmwareSource = lib.mkOption {
    type = lib.types.path;
    default = androidPackages.devices.aurora.firmware-source;
    defaultText = lib.literalExpression "androidPackages.devices.aurora.firmware-source";
    description = "OS3.0.308.0.WNACNXM firmware payload tree (adsp, audio, bluetooth, gpu, modem, sensors, touch, video, wlan, each with SHA256SUMS), for example from androidPackages.mkFirmwareArchive or a local directory.";
  };
  options.hardware.aurora.firmwarePackage = lib.mkOption {
    type = lib.types.package;
    default = androidPackages.devices.aurora.firmware.override {
      firmware-source = config.hardware.aurora.firmwareSource;
    };
    defaultText = lib.literalExpression "androidPackages.devices.aurora.firmware built from hardware.aurora.firmwareSource";
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
      usbController = "a600000.usb";
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
      # ABL boots recovery_b, whose ramdisk is a FIT (kernel, initrd, DTB) that
      # this U-Boot copies into its fastboot buffer (0x7000000) and boots.
      # The direct ABL layout below stays until the FIT path is verified.
      boot.recoveryLoader = "u-boot-fit";
      boot.recoveryFitMaximumBytes = 117440512;
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
        osPatchLevel = lib.mkDefault "2026-08-01";
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
      usb.signaller.address = lib.mkDefault "172.16.46.1/24";
      # The PMK8550 RTC (rtc@6100) has neither allow-set-time nor an offset
      # nvmem cell, so Linux can read but not set it.
      clock.rtcOffset.enable = lib.mkDefault (!config.androidDevices.recovery.enable);
    };
    boot.consoleLogLevel = 8;
    # Reboot with the kernel's default cold PSCI reset. Warm resets
    # (`reboot=warm`, PSCI SYSTEM_RESET2) left the board stuck in U-Boot with a
    # black screen after several software reboots, and ABL could ignore a
    # reboot-mode request after them. A cold reset is a full PMIC power cycle:
    # with a cable attached ABL may occasionally start the offline charger, and
    # RAM (ramoops) need not survive.
    boot.kernelParams = [
      "fbcon=font:TER16x32"
      # Suspend to idle: with the WLAN link torn down, CX/DDR collapse and the
      # board resumes. PSCI SYSTEM_SUSPEND (deep) never collapses CX/DDR and
      # wakes after seconds without a recorded wake source.
      "mem_sleep_default=s2idle"
    ]
    # Preserve firmware-owned clocks in RAM recovery; their handoff is not
    # verified on this board.
    ++ lib.optionals config.androidDevices.recovery.enable [
      "clk_ignore_unused"
      "pd_ignore_unused"
    ];
  };
}
