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
  ];
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
          "devices.asphalt.boot"
          "devices.asphalt.boot-files"
          "devices.asphalt.bootstrap-info"
          "devices.asphalt.disabled-dtbo"
          "devices.asphalt.kernel"
          "devices.asphalt.recovery"
          "devices.asphalt.system"
          "devices.asphalt.u-boot"
          "devices.clover.boot"
          "devices.clover.boot-files"
          "devices.clover.boot-kernel"
          "devices.clover.bootstrap-info"
          "devices.clover.kernel"
          "devices.clover.kernel-mainline"
          "devices.clover.recovery"
          "devices.clover.system"
          "devices.clover.u-boot"
          "devices.polaris.boot"
          "devices.polaris.boot-files"
          "devices.polaris.bootstrap-info"
          "devices.polaris.kernel"
          "devices.polaris.minimal.boot-files"
          "devices.polaris.minimal.bootstrap-info"
          "devices.polaris.minimal.rootfs"
          "devices.polaris.minimal.system"
          "devices.polaris.recovery"
          "devices.polaris.system"
          "devices.polaris.u-boot"
          "devices.sheng.boot"
          "devices.sheng.boot-files"
          "devices.sheng.boot-kernel"
          "devices.sheng.bootstrap-info"
          "devices.sheng.kernel"
          "devices.sheng.kernel-mainline"
          "devices.sheng.kernel-testing"
          "devices.sheng.recovery"
          "devices.sheng.system"
          "devices.sheng.u-boot"
          "kernel-tools"
          "mobile-device"
          "usb-signaller"
        ];
      in
      assert builtins.attrNames allArtifacts == expected;
      assert
        builtins.attrNames packages == [
          "android-tools"
          "kernel-tools"
          "mobile-device"
          "usb-signaller"
        ];
      builtins.attrNames allArtifacts;
    outputs = lib.mapAttrs (
      _: p:
      assert p.system == (if lib.hasSuffix ".system" _ then "aarch64-linux" else buildSystem);
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
          assert k.installTargets == [ "install" ];
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
          assert !c.services.greetd.enable && c.services.getty.autologinUser == "demo";
          assert lib.hasInfix "/dev/tty1" c.programs.bash.loginShellInit;
          assert lib.hasInfix "dbus-run-session" c.programs.bash.loginShellInit;
          assert c.programs.sway.enable && c.programs.foot.enable;
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
          assert lib.hasInfix "output DSI-1 transform 90" c.environment.etc."sway/config".text;
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
          assert lib.hasInfix "for_window [app_id=\"example-terminal\"] fullscreen enable"
            c.environment.etc."sway/config".text;
          {
            session = c.programs.bash.loginShellInit;
            swayConfig = c.environment.etc."sway/config".text;
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
      assert !c.boot.loader.systemd-boot.enable;
      {
        tools = c.androidDevices.recovery.tools.drvPath;
        utilities = c.system.build.mobileRecoveryUtils.drvPath;
        help = c.boot.initrd.systemd.contents."/etc/recovery-help".source;
        screen = c.boot.initrd.systemd.services.mobile-recovery-screen.serviceConfig.ExecStart;
        ready = c.boot.initrd.systemd.services.mobile-recovery-ready.script;
      }
    );
    videoPackages = lib.genAttrs [ "asphalt" "polaris" ] (
      device: (mkSystemConfig device).config.androidDevices.video.ffmpegPackage.drvPath
    );
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
