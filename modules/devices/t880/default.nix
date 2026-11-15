# Alldocube iPlay 80 mini Ultra (T880; MediaTek MT8883, MT6897 class).
# Installed NixOS on slot A, Android on B, and host-supplied RAM recovery.
{
  config,
  lib,
  androidPackages,
  ...
}:
let
  cfg = config.androidDevices;
  board = config.hardware.t880;
  recoveryTree =
    androidPackages.packaging.runCommand "t880-recovery.dtb"
      { nativeBuildInputs = [ androidPackages.buildPackages.dtc ]; }
      ''
        cp ${config.system.build.kernel}/dtbs/mediatek/mt6897-alldocube-t880.dtb $out
        chmod u+w $out
        # DVFSRC_INIT is rejected in the recovery boot path. Keep LK's
        # DRAM/vcore state and let UFS probe without its unavailable supplier.
        fdtput -t s $out /soc/system-controller@1c00f000 status disabled
        fdtput -t s $out /soc/dram-bw status disabled
        fdtput -d $out /soc/ufshci@112b0000 dvfsrc-vcore-supply
        fdtput -d $out /soc/ufshci@112b0000 clk-scale-up-vcore-min
      '';
in
{
  imports = [
    ../../mobile
    ./connectivity.nix
    ./cellular.nix
    ./sensors.nix
  ];

  options.hardware.t880.systemHostName = lib.mkOption {
    type = lib.types.strMatching "[a-z0-9][a-z0-9-]*";
    default = "t880";
    description = "Installed T880 system host name accepted by its recovery.";
  };

  config = {
    nixpkgs.hostPlatform = "aarch64-linux";
    networking.hostName = lib.mkDefault (
      if cfg.recovery.enable then "${board.systemHostName}-recovery" else board.systemHostName
    );
    hardware.deviceTree.name = "mediatek/mt6897-alldocube-t880.dtb";
    androidDevices.boot.recoveryDeviceTree = lib.mkIf cfg.recovery.enable recoveryTree;
    # These switches and the port controller route the USB SuperSpeed lanes.
    # Their TCPM/TCPCI/Type-C dependencies are included by the module closure.
    androidDevices.initrdKernelModules = lib.mkIf cfg.recovery.enable [
      "tcpci_mt6375"
      "whs3844"
      "mtk-usb-dp-selector"
      "fsa4480"
    ];
    # Battery care is a consumer choice. The board supplies the battery path;
    # enabling the window holds the battery between 75 and 80 % on USB power
    # (one-off full charge on request) through the MT6375 driver.
    androidDevices.charging.window = lib.mkIf (!cfg.recovery.enable) {
      enable = lib.mkDefault false;
      battery = "/sys/class/power_supply/mt6375-battery";
    };
    # Mali-G615 CSF firmware for panthor (the GPUEB powers the GPU).
    hardware.firmware = lib.mkIf (!cfg.recovery.enable) [ androidPackages.devices.t880.gpu-firmware ];
    # ramoops is a reserved-memory node of the device tree (plain DRAM at
    # 0x300000000): LK restores its own pstore area (0x48090000) from expdb
    # at every boot, so records written there are lost.
    # The installed system resets on a hang before userspace takes the
    # watchdog: the kernel stops pinging the RGU watchdog it inherits from the
    # bootloader after 90 s unless userspace has opened it (systemd does, in
    # the initrd and in the system). The RAM recovery keeps the kernel's
    # pings.
    boot.kernelParams =
      lib.optionals (!cfg.recovery.enable) [ "watchdog.open_timeout=90" ]
      ++ lib.optionals cfg.recovery.enable [
        "mt6375_power.auto_charge=0"
        # Retain inherited clocks until the remaining consumer handoff is complete.
        "clk_ignore_unused"
      ];
    systemd.settings.Manager = lib.mkIf (!cfg.recovery.enable) {
      RuntimeWatchdogSec = lib.mkDefault "30s";
      # A shutdown that hangs (for example behind a stuck driver) resets.
      RebootWatchdogSec = lib.mkDefault "60s";
    };
    boot.initrd.systemd.settings.Manager = lib.mkIf (!cfg.recovery.enable) {
      RuntimeWatchdogSec = lib.mkDefault "30s";
    };
    # systemd-pstore archives into fixed file names, so a later boot would
    # overwrite a crash record: keep crash boots (a dmesg record present) in
    # their own directories, the last 20.
    systemd.services.t880-pstore-keep = lib.mkIf (!cfg.recovery.enable) {
      description = "Keep crash records from pstore";
      wantedBy = [ "systemd-pstore.service" ];
      before = [ "systemd-pstore.service" ];
      after = [ "local-fs.target" ];
      unitConfig = {
        DefaultDependencies = false;
        ConditionPathExistsGlob = "/sys/fs/pstore/dmesg-*";
      };
      serviceConfig.Type = "oneshot";
      script = ''
        d=/var/lib/t880-pstore/$(date +%Y%m%d-%H%M%S)-$(cut -c1-8 /proc/sys/kernel/random/boot_id)
        mkdir -p "$d"
        cp /sys/fs/pstore/* "$d"/
        ls -1d /var/lib/t880-pstore/*/ | head -n -20 | xargs -r rm -rf
      '';
    };
    androidDevices = {
      enable = true;
      deviceName = "t880";
      video.vaapi.package = lib.mkDefault (androidPackages.libva-v4l2.override { t880 = true; });
      # The mtu3 device controller (verified on a T880).
      usbController = "11201000.usb";
      usb.signaller.address = lib.mkDefault "172.16.47.1/24";
      # The Type-C port manager owns the USB data role (partner type, PD
      # data-role swap); usb-signaller keeps only the gadget modes.
      usb.signaller.hostMode = lib.mkDefault false;
      usb.signaller.manageRole = lib.mkDefault false;
      # PLACEHOLDER: partition names follow the project's convention for
      # devices with Android super (FAT linux-boot and ext4 linux carved from
      # userdata). The T880 partition table has not been read.
      persistentImage.rootfs.device = lib.mkDefault "/dev/disk/by-partlabel/linux";
      boot = {
        firmwarePackage = lib.mkDefault (androidPackages.mkUBoot { device = "t880"; });
        # Stock LK boots U-Boot from the boot image; U-Boot boots RAM
        # recovery from the FIT in that image's ramdisk.
        recoveryLoader = "u-boot-fit";
        # Every recovery FIT must also start with U-Boot `fastboot boot`
        # (128 MiB download buffer).
        recoveryFitMaximumBytes = 134217728;
        uefi = {
          device = lib.mkDefault "/dev/disk/by-partlabel/linux-boot";
          requireStandardEsp = true;
        };
        android = {
          # UNVERIFIED (MT6895/MT6897 xaga template): header v4 carries no
          # load addresses; LK takes them from the stock vendor_boot. These
          # values only describe the template and are not written to v4.
          headerVersion = 4;
          base = "0x3fff8000";
          kernelOffset = "0x00008000";
          ramdiskOffset = "0x26f08000";
          secondOffset = "0x00000000";
          tagsOffset = "0x07c88000";
          pageSize = "4096";
          dtbs = [ "dtbs/mediatek/mt6897-alldocube-t880.dtb" ];
          # UNVERIFIED: usual GKI boot partition size.
          maximumBytes = 67108864;
        };
      };
      recovery = {
        targetHostName = board.systemHostName;
        screenPackage = lib.mkDefault (
          androidPackages.mkRecoveryScreen {
            device = "t880";
            features = [ "recovery-daemon" ];
          }
        );
        extendedStorageTools = true;
        daemon = {
          # Linux on slot A; Android stays on slot B. LK reads the AOSP
          # bootloader_control block in the 512 KiB misc partition.
          slotModel = "mediatek-a";
          slotMetadata = "aosp-boot-control";
          compatible = "alldocube,t880";
          controller = "112b0000.ufshci";
          miscBytes = 524288;
          # LK's proinfo serial number, passed on by U-Boot.
          serialPrefix = "T880";
          # The reboot-mode "recovery" value makes LK report recovery mode
          # to U-Boot (still loaded from boot_a), which then boots the FIT
          # waiting for a host-supplied RAM recovery FIT over USB fastboot.
          recoveryRebootArgument = "recovery";
        };
      };
    };
  };
}
