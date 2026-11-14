{ flake }:
let
  f = flake;
  lib = f.inputs.nixpkgs.lib;
  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
  devices = [
    "polaris"
    "asphalt"
    "clover"
    "sheng"
    "aurora"
  ];
  # Unicorn uses a console example and USB2-only wiring; its two-platform
  # hardware/configuration contract is covered by tests/unicorn.nix.
  recoveryDevices = devices;
in
lib.genAttrs systems (
  buildSystem:
  let
    env = f.lib.mkBuildEnvironment {
      inherit buildSystem;
      config.allowUnfree = true;
    };
    mkSystemConfig =
      device:
      env.nixosSystem {
        modules = [
          f.nixosModules.${device}
          (f.outPath + "/examples/${device}/system.nix")
          {
            androidDevices.persistentImage.rootfs = {
              name = "audit-${device}-rootfs";
              uuid = "11111111-2222-3333-4444-555555555555";
              padding = 268435456;
            };
          }
        ];
      };
    enabledSheng = (mkSystemConfig "sheng").extendModules {
      modules = [
        {
          hardware.sheng.sensors.enable = true;
          hardware.sheng.suspendWorkarounds.enable = true;
          hardware.sheng.wifiMacAddress = "02:00:00:00:00:01";
          services.fprintd.enable = true;
          hardware.sheng = {
            thp.enable = true;
            pen-status.enable = true;
          };
        }
      ];
    };
    packages = f.packages.${buildSystem};
    deviceArtifacts = f.legacyPackages.${buildSystem}.devices;
    flatten =
      prefix: attrs:
      lib.concatMapAttrs (
        name: value:
        let
          path = prefix + name;
        in
        if lib.isDerivation value then
          { ${path} = value; }
        else
          flatten (path + ".") (builtins.removeAttrs value [ "recurseForDerivations" ])
      ) attrs;
    allArtifacts =
      packages // flatten "devices." (builtins.removeAttrs deviceArtifacts [ "recurseForDerivations" ]);
  in
  {
    outputNames =
      let
        expected = [
          "android-tools"
          "audio-orientation"
          "boot-choice-efi"
          "boot-choice-kernelsu"
          "boot-choice-kernelsu-diagnostic"
          "boot-choice-native"
          "boot-choice-template"
          "boot-choice-template-diagnostic"
          "boot-selector-builder"
          "devices.asphalt.boot"
          "devices.asphalt.boot-files"
          "devices.asphalt.bootstrap-info"
          "devices.asphalt.charger"
          "devices.asphalt.kernel"
          "devices.asphalt.recovery"
          "devices.asphalt.sensors"
          "devices.asphalt.system"
          "devices.asphalt.u-boot"
          "devices.aurora.boot"
          "devices.aurora.boot-files"
          "devices.aurora.bootstrap-info"
          "devices.aurora.firmware"
          "devices.aurora.kernel"
          "devices.aurora.recovery"
          "devices.aurora.system"
          "devices.aurora.touch"
          "devices.aurora.u-boot"
          "devices.clover.boot"
          "devices.clover.boot-files"
          "devices.clover.boot-kernel"
          "devices.clover.bootstrap-info"
          "devices.clover.kernel"
          "devices.clover.recovery"
          "devices.clover.system"
          "devices.clover.u-boot"
          "devices.dodge.boot-firmware"
          "devices.dodge.firmware"
          "devices.dodge.kernel"
          "devices.dodge.recovery"
          "devices.marble.boot"
          "devices.marble.boot-files"
          "devices.marble.bootstrap-info"
          "devices.marble.firmware"
          "devices.marble.kernel"
          "devices.marble.recovery"
          "devices.marble.system"
          "devices.marble.u-boot"
          "devices.polaris.boot"
          "devices.polaris.boot-files"
          "devices.polaris.bootstrap-info"
          "devices.polaris.charger"
          "devices.polaris.kernel"
          "devices.polaris.recovery"
          "devices.polaris.sensors"
          "devices.polaris.system"
          "devices.polaris.u-boot"
          "devices.sheng.boot"
          "devices.sheng.boot-files"
          "devices.sheng.boot-kernel"
          "devices.sheng.bootstrap-info"
          "devices.sheng.kernel"
          "devices.sheng.recovery"
          "devices.sheng.system"
          "devices.sheng.u-boot"
          "devices.t880.boot"
          "devices.t880.boot-files"
          "devices.t880.bootstrap-info"
          "devices.t880.connectivity-modules"
          "devices.t880.kernel"
          "devices.t880.recovery"
          "devices.t880.system"
          "devices.t880.u-boot"
          "devices.unicorn.boot"
          "devices.unicorn.boot-files"
          "devices.unicorn.boot-kernel"
          "devices.unicorn.bootstrap-info"
          "devices.unicorn.firmware"
          "devices.unicorn.kernel"
          "devices.unicorn.mipps-auth"
          "devices.unicorn.recovery"
          "devices.unicorn.system"
          "devices.unicorn.u-boot"
          "fastrpc"
          "kernel-tools"
          "libva-v4l2"
          "mink-modem-opener"
          "minkipc"
          "mobile-boot-action"
          "mobile-charger"
          "mobile-charger-host"
          "mobile-device"
          "modemmanager-mtk-soc"
          "mtk-ccci-userspace"
          "sensor-rotate"
          "usb-signaller"
        ];
      in
      assert builtins.attrNames allArtifacts == expected;
      assert
        builtins.attrNames packages == [
          "android-tools"
          "audio-orientation"
          "boot-choice-efi"
          "boot-choice-kernelsu"
          "boot-choice-kernelsu-diagnostic"
          "boot-choice-native"
          "boot-choice-template"
          "boot-choice-template-diagnostic"
          "boot-selector-builder"
          "fastrpc"
          "kernel-tools"
          "libva-v4l2"
          "mink-modem-opener"
          "minkipc"
          "mobile-boot-action"
          "mobile-charger"
          "mobile-charger-host"
          "mobile-device"
          "modemmanager-mtk-soc"
          "mtk-ccci-userspace"
          "sensor-rotate"
          "usb-signaller"
        ];
      builtins.attrNames allArtifacts;
    outputs = lib.mapAttrs (
      _: p:
      # The VA driver, QTEE and MediaTek modem userspace follow native upstream dependencies;
      # project device executables and data use the selected compilation/packaging host.
      assert
        p.system == (
          if
            builtins.elem _ [
              "libva-v4l2"
              "minkipc"
              "mink-modem-opener"
              "modemmanager-mtk-soc"
              "mtk-ccci-userspace"
            ]
          then
            "aarch64-linux"
          else
            buildSystem
        );
      assert lib.hasSuffix ".system" _ -> p.stdenv.hostPlatform.system == "aarch64-linux";
      {
        inherit (p) drvPath system;
      }
    ) allArtifacts;
    devices = lib.genAttrs devices (
      device:
      let
        c = (mkSystemConfig device).config;
        k = c.androidDevices.kernelPackage;
      in
      assert k.stdenv.hostPlatform.system == "aarch64-linux";
      assert k.stdenv.buildPlatform.system == buildSystem;
      {
        target = k.stdenv.hostPlatform.system;
        builder = k.stdenv.buildPlatform.system;
        flags = k.makeFlags;
        rootfs = c.system.build.mobileSystemImage.drvPath;
        initrdCollector =
          let
            collector = lib.findFirst (
              p: lib.getName p == "make-initrd-ng"
            ) (throw "Missing initrd collector") c.system.build.initialRamdisk.nativeBuildInputs;
          in
          assert collector.stdenv.hostPlatform.system == buildSystem;
          {
            inherit (collector) drvPath;
            host = collector.stdenv.hostPlatform.system;
          };

        moduleInstall =
          let
            flags = builtins.filter (lib.hasPrefix "INSTALL_MOD_PATH=") k.installFlags;
            modular = builtins.elem "modules" k.outputs;
          in
          assert k.config.isYes "MODULES" && modular;
          assert flags == lib.optional modular "INSTALL_MOD_PATH=${builtins.placeholder "modules"}";
          # Ordinary install (never the arm64 EFI zinstall) plus modules_install;
          # dtbs_install only when the kernel builds every DTB.
          assert
            lib.take 2 k.installTargets == [
              "install"
              "modules_install"
            ];
          assert lib.all (
            target:
            lib.elem target [
              "install"
              "modules_install"
              "dtbs_install"
            ]
          ) k.installTargets;
          assert
            builtins.length (builtins.filter (flag: flag == "modules") k.buildFlags)
            == (if modular then 1 else 0);
          {
            inherit flags modular;
            outputs = k.outputs;
          };

        usbPeripherals =
          let
            required = [
              "USB_XHCI_HCD"
              "USB_XHCI_PLATFORM"
              "USB_DWC3"
              "USB_ROLE_SWITCH"
              "USB_STORAGE"
              "USB_UAS"
              "SCSI"
              "BLK_DEV_SD"
              "USB_USBNET"
              "USB_RTL8152"
              "USB_NET_AX8817X"
              "USB_NET_AX88179_178A"
              "USB_NET_CDCETHER"
              "USB_NET_CDC_NCM"
              "USB_HID"
              "HID_GENERIC"
              "USB_ACM"
              "USB_SERIAL"
              "VFAT_FS"
              "EXFAT_FS"
              "DRM_MSM_DP"
              "TYPEC"
            ]
            ++ lib.optional (builtins.elem device [
              "clover"
              "asphalt"
            ]) "MMC_SDHCI_MSM";
          in
          assert lib.all k.config.isEnabled required;
          lib.genAttrs required k.config.getValue;

        efi =
          assert c.boot.loader.systemd-boot.enable;
          assert !c.boot.loader.efi.canTouchEfiVariables;
          assert c.boot.loader.systemd-boot.installDeviceTree;
          assert c.system.boot.loader.kernelFile == "Image";
          assert k.features.efiBootStub;
          assert c.fileSystems."/boot".fsType == "vfat";
          assert
            c.fileSystems."/boot".device == (
              if
                builtins.elem device [
                  "polaris"
                  "clover"
                ]
              then
                "/dev/disk/by-partlabel/system"
              else
                "/dev/disk/by-partlabel/linux-boot"
            );
          assert !(c.boot.initrd.systemd.services ? mobile-initial-profile);
          assert !(c.boot.initrd.systemd.contents ? "/etc/systemd/system-generators/systemd-fstab-generator");
          assert !(builtins.elem "init=/nix/var/nix/profiles/system/init" c.boot.kernelParams);
          assert c.system.build.mobileBootImage.drvPath == deviceArtifacts.${device}.u-boot.drvPath;
          {
            files = c.system.build.mobileBootFiles.drvPath;
            installer = c.system.build.installBootLoader;
            closureFinder = c.boot.initrd.systemd.services.initrd-find-nixos-closure.serviceConfig.ExecStart;
          };

        desktop =
          assert c.users.users.demo.hashedPassword == "";
          assert !c.services.greetd.enable && c.services.getty.autologinUser == null;
          assert lib.hasInfix "--autologin demo" (
            lib.last c.systemd.services."getty@tty1".serviceConfig.ExecStart
          );
          assert lib.hasInfix "/dev/tty1" c.programs.bash.loginShellInit;
          assert lib.hasInfix "NIRI_CONFIG=/etc/niri/config.kdl" c.programs.bash.loginShellInit;
          assert lib.hasInfix "/bin/niri-session -l" c.programs.bash.loginShellInit;
          assert c.programs.niri.enable && !c.programs.sway.enable && c.programs.foot.enable;
          assert
            device != "polaris"
            || lib.all (name: builtins.elem name (map lib.getName c.androidDevices.initrdFirmware)) [
              "wireless-regdb"
              "polaris-gpu-firmware"
              "polaris-bluetooth-firmware"
            ];
          assert
            device != "polaris"
            || builtins.elem "polaris-multimedia-firmware" (map lib.getName c.environment.systemPackages);
          assert
            device != "polaris" || builtins.elem "/share/uncompressed-firmware" c.environment.pathsToLink;
          assert lib.hasInfix "touch { map-to-output \"DSI-1\"; }" c.environment.etc."niri/config.kdl".text;
          assert
            c.example.desktop.scale == (
              if device == "aurora" then
                "3"
              else if
                builtins.elem device [
                  "asphalt"
                  "sheng"
                ]
              then
                "2"
              else
                "1"
            );
          assert lib.hasInfix ''/bin/wvkbd-mobintl"'' c.environment.etc."niri/config.kdl".text;
          assert !lib.hasInfix "transform" c.environment.etc."niri/config.kdl".text;
          assert !lib.hasInfix "mobile-sensor-rotate" c.environment.etc."niri/config.kdl".text;
          assert lib.hasInfix "(maximum + 2) / 4" c.systemd.services."getty@".preStart;
          assert !(builtins.elem "mobile-basic-test" (map lib.getName c.environment.systemPackages));
          assert lib.all (name: builtins.elem name (map lib.getName c.environment.systemPackages)) [
            "iw"
            "bluez"
            "ffmpeg"
            "glmark2"
            "vkmark"
          ];
          assert builtins.elem (lib.getName (mkSystemConfig device).pkgs.fastfetch) (
            map lib.getName c.environment.systemPackages
          );
          assert lib.hasInfix "--app-id=example-terminal" c.environment.etc."niri/config.kdl".text;
          {
            session = c.programs.bash.loginShellInit;
            niriConfig = c.environment.etc."niri/config.kdl".text;
            fastfetch = (mkSystemConfig device).pkgs.fastfetch.drvPath;
          };
      }
    );
    recoveryProfiles = lib.genAttrs recoveryDevices (
      device:
      let
        c =
          (env.nixosSystem {
            modules = [
              f.nixosModules.${device}
              (f.outPath + "/examples/${device}/recovery.nix")
            ];
          }).config;
      in
      # One kernel per device: recovery uses the installed system's kernel.
      assert
        c.androidDevices.kernelPackage.drvPath == (mkSystemConfig device)
        .config.androidDevices.kernelPackage.drvPath;
      assert
        c.androidDevices.kernelPackage.drvPath
        == f.legacyPackages.${buildSystem}.devices.${device}.kernel.drvPath;
      assert !c.boot.loader.systemd-boot.enable;
      assert
        c.boot.initrd.systemd.services.mobile-recovery-screen.serviceConfig.ExecStart
        == "/bin/mobile-recovery-screen";
      assert !(c.boot.initrd.systemd.contents ? "/etc/mobile-recovery-font.ttf");
      assert lib.all c.androidDevices.kernelPackage.config.isYes [
        "VT"
        "FRAMEBUFFER_CONSOLE"
        "DRM_FBDEV_EMULATION"
      ];
      {
        utilities = c.system.build.mobileRecoveryUtils.drvPath;
        contract = builtins.fromJSON c.boot.initrd.systemd.contents."/etc/mobile-recovery.json".text;
        screen = c.boot.initrd.systemd.services.mobile-recovery-screen.serviceConfig.ExecStart;
        ready = c.boot.initrd.systemd.services.mobile-recovery-ready.script;
      }
    );
    videoPackages = lib.genAttrs devices (
      device:
      let
        system = mkSystemConfig device;
        ffmpeg = system.config.androidDevices.video.ffmpegPackage;
      in
      assert ffmpeg.drvPath == system.pkgs.ffmpeg.drvPath;
      ffmpeg.drvPath
    );
    # Experimental MediaTek board: console system and minimal recovery only.
    t880 =
      let
        c = (mkSystemConfig "t880").config;
        r =
          (env.nixosSystem {
            modules = [
              f.nixosModules.t880
              (f.outPath + "/examples/t880/recovery.nix")
            ];
          }).config;
        k = c.androidDevices.kernelPackage;
        artifacts = deviceArtifacts.t880;
        usb = [
          "USB_XHCI_HCD"
          "USB_XHCI_PLATFORM"
          "USB_MTU3"
          "USB_ROLE_SWITCH"
          "USB_STORAGE"
          "USB_UAS"
          "SCSI"
          "BLK_DEV_SD"
          "USB_USBNET"
          "USB_RTL8152"
          "USB_NET_AX8817X"
          "USB_NET_AX88179_178A"
          "USB_NET_CDCETHER"
          "USB_NET_CDC_NCM"
          "USB_HID"
          "HID_GENERIC"
          "USB_ACM"
          "USB_SERIAL"
          "VFAT_FS"
          "EXFAT_FS"
          "TYPEC"
          "SCSI_UFS_MEDIATEK"
          "USB_CONFIGFS_ACM"
          "USB_CONFIGFS_NCM"
        ];
      in
      assert k.stdenv.hostPlatform.system == "aarch64-linux";
      assert k.stdenv.buildPlatform.system == buildSystem;
      # One kernel per device and build platform.
      assert r.androidDevices.kernelPackage.drvPath == k.drvPath;
      assert k.drvPath == artifacts.kernel.drvPath;
      assert lib.all k.config.isEnabled usb;
      assert c.boot.loader.systemd-boot.enable;
      assert c.fileSystems."/boot".device == "/dev/disk/by-partlabel/linux-boot";
      assert c.system.build.mobileBootImage.drvPath == artifacts.u-boot.drvPath;
      assert !r.androidDevices.recovery.minimal;
      assert r.boot.initrd.systemd.services ? mobile-recovery-daemon;
      assert r.system.build.mobileBootImage.drvPath == artifacts.recovery.drvPath;
      assert r.system.build.mobileBootImage.firmware.drvPath == artifacts.u-boot.firmware.drvPath;
      assert r.system.build.mobileBootImage.system == buildSystem;
      assert r.system.build.mobileBootImage.payload.system == buildSystem;
      {
        kernel = k.drvPath;
        recovery = artifacts.recovery.drvPath;
        payload = r.system.build.mobileBootImage.payload.drvPath;
        usbPeripherals = lib.genAttrs usb k.config.getValue;
      };
    # Experimental Qualcomm board: console system and u-boot-fit RAM recovery.
    marble =
      let
        c = (mkSystemConfig "marble").config;
        r =
          (env.nixosSystem {
            modules = [
              f.nixosModules.marble
              (f.outPath + "/examples/marble/recovery.nix")
            ];
          }).config;
        k = c.androidDevices.kernelPackage;
        artifacts = deviceArtifacts.marble;
        builtIn = [
          "PINCTRL_SM8475"
          "SM_GCC_8450"
          "SCSI_UFS_QCOM"
          "PHY_SNPS_EUSB2"
          "PHY_NXP_PTN3222"
          "USB_DWC3"
          "USB_DWC3_QCOM"
          "USB_CONFIGFS_ACM"
          "USB_CONFIGFS_NCM"
          "DRM_SIMPLEDRM"
          "FRAMEBUFFER_CONSOLE"
          "TOUCHSCREEN_GOODIX_BERLIN_SPI"
          "KEYBOARD_GPIO"
          "INPUT_PM8941_PWRKEY"
          "EXT4_FS"
          "VFAT_FS"
        ];
      in
      assert k.stdenv.hostPlatform.system == "aarch64-linux";
      assert k.stdenv.buildPlatform.system == buildSystem;
      # One kernel per device and build platform.
      assert r.androidDevices.kernelPackage.drvPath == k.drvPath;
      assert k.drvPath == artifacts.kernel.drvPath;
      assert lib.all k.config.isYes builtIn;
      assert c.boot.loader.systemd-boot.enable;
      assert c.fileSystems."/boot".device == "/dev/disk/by-partlabel/linux-boot";
      assert c.system.build.mobileBootImage.drvPath == artifacts.u-boot.drvPath;
      assert r.androidDevices.boot.recoveryLoader == "u-boot-fit";
      assert r.boot.initrd.systemd.services ? mobile-recovery-daemon;
      assert r.system.build.mobileBootImage.drvPath == artifacts.recovery.drvPath;
      assert r.system.build.mobileBootImage.firmware.drvPath == artifacts.u-boot.firmware.drvPath;
      assert r.system.build.mobileBootImage.system == buildSystem;
      assert r.system.build.mobileBootImage.payload.system == buildSystem;
      assert r.androidDevices.usbSerial == "RECOVERY_MARBLE";
      assert r.androidDevices.usb.signaller.address == "172.16.48.1/24";
      {
        kernel = k.drvPath;
        recovery = artifacts.recovery.drvPath;
        payload = r.system.build.mobileBootImage.payload.drvPath;
        builtIn = lib.genAttrs builtIn k.config.getValue;
      };
    optionalSheng = enabledSheng.config.system.build.toplevel.drvPath;
    shengInstalledUsb =
      let
        c = (mkSystemConfig "sheng").config;
      in
      assert c.androidDevices.boot.android.maximumBytes == 201326592;
      assert c.androidDevices.usb.enable;
      assert !(c.boot.initrd.systemd.services ? mobile-sheng-usb-device);
      assert c.systemd.services.usb-signaller.environment.USB_SIGNALLER_ACM == "1";
      c.systemd.services.usb-signaller.serviceConfig.ExecStart;
    shengRecoveryUsb =
      let
        c =
          (env.nixosSystem {
            modules = [
              f.nixosModules.sheng
              {
                androidDevices.recovery.enable = true;
                androidDevices.usbSerial = "eval-sheng";
              }
            ];
          }).config;
      in
      assert c.androidDevices.boot.android.maximumBytes == 104857600;
      assert
        c.androidDevices.boot.android.avbFooter == {
          partitionName = "recovery";
          partitionSize = 104857600;
        };
      assert c.androidDevices.usb.enable;
      assert !(c.boot.initrd.systemd.services ? mobile-sheng-usb-device);
      c.boot.initrd.systemd.services.mobile-initrd-usb.serviceConfig.ExecStart;
    asphaltRadio =
      let
        c =
          ((mkSystemConfig "asphalt").extendModules {
            modules = [
              {
                hardware.asphalt.radio = {
                  bluetoothAddressFile = builtins.toFile "example-bt-address" "06:05:04:03:02:01\n";
                  wifiAddressFile = builtins.toFile "example-wifi-address" "02:00:00:00:00:01\n";
                };
              }
            ];
          }).config;
      in
      {
        system = c.system.build.toplevel.drvPath;
        bluetooth = c.systemd.services.asphalt-bluetooth-address.script;
        wifi = c.environment.etc."NetworkManager/conf.d/90-asphalt-wifi-mac.conf".source;
      };
    shengRuntimeCacheReuse =
      let
        p = enabledSheng.pkgs;
        d = p.androidDevicePackages.devices.sheng;
        targetInputs = [
          p.glib
          p.libssc
        ]
        ++ (with p.libsForQt5; [
          qtbase
          qtsvg
          qtwebsockets
          qtx11extras
        ]);
        inputs = map (input: input.drvPath) (d.thp.buildInputs ++ d.pen-status.buildInputs);
      in
      assert d.thp.stdenv.buildPlatform.system == buildSystem;
      assert d.pen-status.stdenv.buildPlatform.system == buildSystem;
      assert d.thp.stdenv.hostPlatform.system == "aarch64-linux";
      assert d.pen-status.stdenv.hostPlatform.system == "aarch64-linux";
      assert lib.all (input: builtins.elem input.drvPath inputs) targetInputs;
      true;
    shengFingerprintRuntimeCacheReuse =
      let
        p = enabledSheng.pkgs;
        d = p.androidDevicePackages.devices.sheng;
        inputs = map (input: input.drvPath) (d.libfprint.buildInputs ++ d.fprintd.buildInputs);
        targetInputs = with p; [
          gusb
          pixman
          glib
          cairo
          libgudev
          openssl
          polkit
          nss
          pam
          systemdLibs
        ];
      in
      assert d.libfprint.stdenv.buildPlatform.system == buildSystem;
      assert d.fprintd.stdenv.buildPlatform.system == buildSystem;
      assert d.libfprint.stdenv.hostPlatform.system == "aarch64-linux";
      assert d.fprintd.stdenv.hostPlatform.system == "aarch64-linux";
      assert lib.all (input: builtins.elem input.drvPath inputs) targetInputs;
      true;
    shengWifi = enabledSheng.config.networking.networkmanager.wifi.macAddress;
    kernelShell = f.devShells.${buildSystem}.kernel.drvPath;
    eflGenerators =
      let
        p = (mkSystemConfig "clover").pkgs;
        generators = builtins.filter (
          input: lib.getName input == "efl"
        ) p.enlightenment.efl.nativeBuildInputs;
      in
      assert generators == [ ];
      map (
        generator:
        assert generator.stdenv.hostPlatform.system == buildSystem;
        {
          inherit (generator) drvPath;
          host = generator.stdenv.hostPlatform.system;
        }
      ) generators;
  }
)
