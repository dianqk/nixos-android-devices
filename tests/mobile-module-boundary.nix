{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
in
lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
  buildSystem:
  let
    env = flake.lib.mkBuildEnvironment { inherit buildSystem; };
    inherit (env) pkgs;
    firmware = pkgs.writeText "test-uefi.img" "evaluation-only firmware fixture";
    system = env.nixosSystem {
      modules = [
        # Internal regression: deliberately import no registered device module.
        ../modules/mobile
        {
          networking.hostName = "independent-host";
          hardware.deviceTree = {
            name = "test/independent.dtb";
            package = lib.mkForce pkgs.emptyDirectory;
          };
          androidDevices = {
            enable = true;
            deviceName = "unregistered-board";
            usbSerial = "test-serial";
            usb.enable = false;
            # This synthetic board has no bootable DTB or firmware. Supply
            # full-recovery display capabilities independently of the generic
            # Nixpkgs kernel's framebuffer module choices; real board kernels
            # are checked by public-api/platforms.
            kernelPackage = pkgs.linux // {
              config = pkgs.linux.config // {
                isYes =
                  name:
                  builtins.elem name [
                    "VT"
                    "FRAMEBUFFER_CONSOLE"
                    "DRM_FBDEV_EMULATION"
                  ]
                  || pkgs.linux.config.isYes name;
              };
            };
            boot = {
              firmwarePackage = firmware;
              uefi.device = "/dev/disk/by-partlabel/custom-boot";
              android = {
                base = "0x00000000";
                kernelOffset = "0x00008000";
                ramdiskOffset = "0x01000000";
                secondOffset = "0x00f00000";
                tagsOffset = "0x00000100";
                pageSize = "4096";
                dtbs = [ "test/independent.dtb" ];
              };
            };
            persistentImage.rootfs = {
              uuid = "11111111-2222-3333-4444-555555555555";
              device = "/dev/disk/by-partlabel/custom-root";
            };
            recovery = {
              targetHostName = "installed-host";
              screenPackage = pkgs.emptyDirectory;
              extendedStorageTools = true;
              # A new board supplies explicit daemon inputs; no shared branch.
              daemon = {
                slotModel = "single";
                compatible = "test,independent";
                controller = "test-controller";
                miscBytes = 1048576;
                bootRequest = "bcb";
                recoveryRebootArgument = null;
                roles = {
                  root.label = "custom-root";
                  esp.label = "custom-boot";
                  firmware.label = "custom-firmware";
                  recovery.label = "custom-recovery";
                  misc.label = "custom-misc";
                };
              };
            };
          };
        }
      ];
    };
    standard = system.config;
    vendor =
      (system.extendModules {
        modules = [ { androidDevices.boot.uefi.requireStandardEsp = false; } ];
      }).config;
    direct =
      (system.extendModules {
        modules = [ { androidDevices.boot.directKernel.enable = true; } ];
      }).config;
    recovery =
      (system.extendModules {
        modules = [
          {
            androidDevices.recovery.enable = true;
            androidDevices.boot.directKernel.enable = true;
            androidDevices.boot.firmwarePackage = lib.mkForce null;
          }
        ];
      }).config;
    missingFirmware =
      (system.extendModules {
        modules = [ { androidDevices.boot.firmwarePackage = lib.mkForce null; } ];
      }).config;
    standardScript = standard.system.build.installBootLoader.text;
    vendorScript = vendor.system.build.installBootLoader.text;
    contract = builtins.fromJSON recovery.boot.initrd.systemd.contents."/etc/mobile-recovery.json".text;
  in
  assert lib.all (c: lib.all (a: a.assertion) c.assertions) [
    standard
    vendor
    direct
    recovery
  ];
  assert !(lib.all (a: a.assertion) missingFirmware.assertions);
  assert !(system.options.androidDevices ? unregistered-board);
  assert standard.networking.hostName == "independent-host";
  assert standard.androidDevices.platformKernelParams == [ ];
  assert !(builtins.elem "androidboot.hardware=qcom" standard.boot.kernelParams);
  assert standard.hardware.deviceTree.name == "test/independent.dtb";
  assert standard.fileSystems."/".device == "/dev/disk/by-partlabel/custom-root";
  assert standard.fileSystems."/boot".device == "/dev/disk/by-partlabel/custom-boot";
  assert standard.system.build.mobileBootImage == firmware;
  assert !(standard.system.build ? mobileDirectBootImage);
  assert direct.system.build ? mobileDirectBootImage;
  assert !(recovery.system.build ? mobileDirectBootImage);
  assert !recovery.androidDevices.persistentImage.enable;
  assert !recovery.boot.loader.systemd-boot.enable;
  assert contract.hostname == "installed-host";
  assert contract.identity == "unregistered-board";
  assert contract.roles.esp.label == "custom-boot";
  assert contract.boot_request == "bcb" && contract.recovery_reboot_argument == null;
  assert lib.hasInfix "mobile-storage-roles.json" standard.system.systemBuilderCommands;
  assert lib.all (script: lib.hasInfix "The mounted /boot does not match" script) [
    standardScript
    vendorScript
  ];
  assert lib.hasInfix "PART_ENTRY_TYPE" standardScript;
  assert lib.hasInfix "--getsize64" standardScript;
  assert lib.hasInfix "--output=avail" standardScript;
  assert !(lib.hasInfix "SYSTEMD_RELAX_ESP_CHECKS" standardScript);
  assert lib.hasInfix "SYSTEMD_RELAX_ESP_CHECKS=1" vendorScript;
  assert !(lib.hasInfix "PART_ENTRY_TYPE" vendorScript);
  {
    # Construct derivations only; fixtures are intentionally not bootable images.
    boot = standard.system.build.mobileBootImage.drvPath;
    bootFiles = standard.system.build.mobileBootFiles.drvPath;
    directBoot = direct.system.build.mobileDirectBootImage.drvPath;
    recovery = recovery.system.build.mobileBootImage.drvPath;
  }
)
