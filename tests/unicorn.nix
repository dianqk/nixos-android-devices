{ flake }:
let
  lib = flake.inputs.nixpkgs.lib;
in
lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
  buildSystem:
  let
    make =
      modules:
      flake.lib.mkSystem {
        device = "unicorn";
        inherit buildSystem modules;
        nixpkgsConfig.allowUnfreePredicate =
          package:
          builtins.elem (lib.getName package) [
            "unicorn-firmware"
            "unicorn-firmware-zstd"
          ];
      };
    system = (make [ ]).config;
    makeUsb =
      acm:
      (make [
        {
          androidDevices.usb.acm.enable = acm;
          androidDevices.usb.ssh.enable = true;
        }
      ]).config;
    usb = makeUsb true;
    usbWithoutAcm = makeUsb false;
    identity = (
      make [
        {
          hardware.bluetooth.enable = true;
          hardware.unicorn.bluetoothIdentityFile = "/var/lib/mobile-identity/bluetooth-address";
        }
      ]
    );
    identityConfig = identity.config;
    identityType = identity.options.hardware.unicorn.bluetoothIdentityFile.type;
    powerKeys = (make [ { hardware.unicorn.hardwareKeys.enable = true; } ]).config;
    volumeKeys =
      (make [
        {
          hardware.unicorn.hardwareKeys = {
            enable = true;
            screen.enable = false;
            powerOff.enable = false;
          };
          services.pipewire = {
            enable = true;
            systemWide = true;
          };
        }
      ]).config;
    charging = (make [ { services.xiaomi-mipps-auth.enable = true; } ]).config;
    chargingDiscovery =
      (make [
        {
          services.xiaomi-mipps-auth.enable = true;
          services.xiaomi-mipps-auth.allowDataRoleSwap = true;
        }
      ]).config;
    chargingRecovery =
      (make [
        {
          services.xiaomi-mipps-auth.enable = true;
          androidDevices.recovery.enable = true;
        }
      ]).config;
    recovery = (make [ { androidDevices.recovery.enable = true; } ]).config;
    contract = builtins.fromJSON recovery.boot.initrd.systemd.contents."/etc/mobile-recovery.json".text;
  in
  assert !system.androidDevices.usb.acm.enable;
  assert !system.services.fprintd.enable;
  assert !recovery.services.fprintd.enable;
  assert !(system.systemd.services ? qsee-supplicant);
  assert !(system.systemd.services ? unicorn-fingerprint-select);
  assert !(flake.legacyPackages.${buildSystem}.devices.unicorn ? fingerprint-runtime);
  assert !(flake.legacyPackages.${buildSystem}.devices.unicorn ? libfprint);
  assert !(system.androidDevices.kernelPackage.config.isYes "QCOM_QSEECOM");
  assert lib.all (a: a.assertion) usb.assertions;
  assert lib.all (a: a.assertion) usbWithoutAcm.assertions;
  assert usb.androidDevices.kernelPackage.config.isYes "USB_CONFIGFS_ACM";
  assert usb.systemd.services.usb-signaller.environment.USB_SIGNALLER_ACM == "1";
  assert usbWithoutAcm.systemd.services.usb-signaller.environment.USB_SIGNALLER_ACM == "0";
  assert !(usbWithoutAcm.systemd.services ? "serial-getty@ttyGS0");
  assert !(lib.hasInfix "serial-getty@ttyGS0.service" usb.services.udev.extraRules);
  assert !(lib.hasInfix "serial-getty@ttyGS0.service" usbWithoutAcm.services.udev.extraRules);
  assert usb.systemd.services."serial-getty@ttyGS0".serviceConfig.Type == "simple";
  assert usb.systemd.services."serial-getty@ttyGS0".serviceConfig.StandardInput == "null";
  assert usb.systemd.services."serial-getty@ttyGS0".serviceConfig.StandardOutput == "journal";
  assert !usb.systemd.services."serial-getty@ttyGS0".serviceConfig.TTYReset;
  assert !usb.systemd.services."serial-getty@ttyGS0".serviceConfig.TTYVHangup;
  assert lib.hasInfix "/sys/class/udc/${usb.androidDevices.usbController}/state" (
    lib.last usb.systemd.services."serial-getty@ttyGS0".serviceConfig.ExecStart
  );
  assert lib.all (c: c.services.openssh.startWhenNeeded) [
    usb
    usbWithoutAcm
  ];
  assert lib.all (c: c.systemd.sockets.sshd.socketConfig.Accept) [
    usb
    usbWithoutAcm
  ];
  assert lib.all (c: c.systemd.sockets.sshd.socketConfig.FreeBind) [
    usb
    usbWithoutAcm
  ];
  assert usb.systemd.services."sshd@".serviceConfig.StandardInput == "socket";
  assert usbWithoutAcm.systemd.network.networks."10-mobile-usb".address == [ "172.16.47.1/24" ];
  assert !system.services.xiaomi-mipps-auth.enable;
  assert !system.services.xiaomi-mipps-auth.allowDataRoleSwap;
  assert lib.hasSuffix "--allow-data-role-swap"
    chargingDiscovery.systemd.services.xiaomi-mipps-auth.serviceConfig.ExecStart;
  assert charging.systemd.services.xiaomi-mipps-auth.serviceConfig.RuntimeDirectoryPreserve == "yes";
  assert !(system.systemd.services ? xiaomi-mipps-auth);
  assert !(chargingRecovery.systemd.services ? xiaomi-mipps-auth);
  assert charging.systemd.services.xiaomi-mipps-auth.wantedBy == [ "multi-user.target" ];
  assert charging.systemd.services.xiaomi-mipps-auth.serviceConfig.Type == "simple";
  assert lib.hasInfix "unicorn-mipps-auth"
    charging.systemd.services.xiaomi-mipps-auth.serviceConfig.ExecStart;
  assert lib.hasSuffix "--daemon" charging.systemd.services.xiaomi-mipps-auth.serviceConfig.ExecStart;
  assert !(lib.hasInfix "--usb-online-trigger" charging.services.udev.extraRules);
  assert system.hardware.unicorn.audio.enable;
  assert !system.hardware.unicorn.audioRuntime.enable;
  assert !recovery.hardware.unicorn.audio.enable;
  assert !system.hardware.unicorn.display.seamless.enable;
  assert system.hardware.unicorn.display.idleRefreshRate == 0;
  assert !(recovery.systemd.services ? unicorn-audio-prepare);
  assert !(recovery.systemd.services ? unicorn-hardware-keys);
  assert !powerKeys.hardware.unicorn.hardwareKeys.volume.enable;
  assert powerKeys.systemd.services.unicorn-hardware-keys.wants == [ ];
  assert powerKeys.systemd.services.unicorn-hardware-keys.serviceConfig.SupplementaryGroups == [ ];
  assert
    !(lib.hasInfix "--wpctl" powerKeys.systemd.services.unicorn-hardware-keys.serviceConfig.ExecStart);
  assert lib.all (a: a.assertion) powerKeys.assertions;
  assert volumeKeys.hardware.unicorn.hardwareKeys.volume.enable;
  assert volumeKeys.systemd.services.unicorn-hardware-keys.serviceConfig.CapabilityBoundingSet == [ ];
  assert !(builtins.elem "consoleblank=0" volumeKeys.boot.kernelParams);
  assert lib.hasInfix "--no-screen"
    volumeKeys.systemd.services.unicorn-hardware-keys.serviceConfig.ExecStart;
  assert lib.hasInfix "--no-poweroff"
    volumeKeys.systemd.services.unicorn-hardware-keys.serviceConfig.ExecStart;
  assert !(recovery.systemd.services ? unicorn-bluetooth-identity);
  assert system.hardware.unicorn.bluetoothIdentityFile == null;
  assert !(system.systemd.services ? unicorn-bluetooth-identity);
  assert lib.all (path: !(identityType.check path)) [
    "relative/address"
    "/nix/store/identity"
    "/var/../identity"
    "/var//identity"
    "/var/identity/"
    ./unicorn.nix
    "${flake.inputs.nixpkgs}/identity"
  ];
  assert identityType.check "/var/lib/mobile-identity/bluetooth-address";
  assert builtins.elem "bluetooth.service"
    identityConfig.systemd.services.unicorn-bluetooth-identity.before;
  assert builtins.elem "bluetooth.service"
    identityConfig.systemd.services.unicorn-bluetooth-identity.requiredBy;
  assert
    identityConfig.systemd.services.unicorn-bluetooth-identity.serviceConfig.TimeoutStartSec == 65;
  assert lib.all (a: a.assertion) system.assertions;
  assert lib.all (a: a.assertion) recovery.assertions;
  assert system.boot.loader.systemd-boot.enable;
  assert system.fileSystems."/".device == "/dev/disk/by-partlabel/linux";
  assert system.fileSystems."/boot".device == "/dev/disk/by-partlabel/linux-boot";
  assert !system.androidDevices.boot.actions.android;
  assert system.androidDevices.boot.actions.recoveryTarget == "slot-b";
  assert contract.linux_only;
  assert contract.compatible == "xiaomi,unicorn";
  assert contract.slot_model == "ab";
  assert contract.slot_metadata == "qcom-gpt";
  assert contract.controller == "1d84000.ufshc";
  assert contract.misc_bytes == 4194304;
  assert system.androidDevices.kernelPackage.drvPath == recovery.androidDevices.kernelPackage.drvPath;
  assert !(builtins.elem "atkbd" system.boot.kernelModules);
  assert system.boot.kernel.sysctl."kernel.sysrq" == 16;
  assert lib.any (
    package: lib.hasPrefix "unicorn-firmware" (lib.getName package)
  ) system.hardware.firmware.paths;
  assert recovery.androidDevices.initrdFirmware != [ ];
  # Installed peripherals require the modules output; recovery input stays built in.
  assert builtins.elem "modules" system.androidDevices.kernelPackage.outputs;
  assert lib.all recovery.androidDevices.kernelPackage.config.isYes [
    "DRM_PANEL_XIAOMI_L2S_380C0A"
    "TOUCHSCREEN_ST_FTS_SPI"
    "SPI_QCOM_GENI"
    "SERIAL_QCOM_GENI"
    "CPU_FREQ_THERMAL"
    "DEVFREQ_THERMAL"
    "SCSI_UFS_CRYPTO"
    "QCOM_INLINE_CRYPTO_ENGINE"
    "MAGIC_SYSRQ"
    "RTC_INTF_DEV"
    "FW_LOADER_COMPRESS"
    "FW_LOADER_COMPRESS_ZSTD"
  ];
  assert !(recovery.androidDevices.kernelPackage.config.isYes "MAGIC_SYSRQ_SERIAL");
  assert
    recovery.androidDevices.boot.android.dtbProperties."qcom,board-id" == [
      65544
      0
    ];
  {
    kernel = system.androidDevices.kernelPackage.drvPath;
    system = system.system.build.toplevel.drvPath;
    recovery = recovery.system.build.mobileBootImage.drvPath;
  }
)
