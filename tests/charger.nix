{ flake }:
let
  lib = flake.inputs.nixpkgs.lib;
in
lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
  buildSystem:
  lib.genAttrs [ "asphalt" "polaris" "aurora" ] (
    device:
    let
      make =
        modules:
        flake.lib.mkSystem {
          nixpkgsConfig.allowUnfreePredicate =
            package:
            builtins.elem (lib.getName package) [
              "aurora-firmware"
              "aurora-firmware-zstd"
              "aurora-touch"
            ];
          inherit device;
          inherit buildSystem;
          modules = [
            {
              androidDevices.usbSerial = "charger-evaluation";
              androidDevices.persistentImage.rootfs.uuid = "11111111-2222-3333-4444-555555555555";
            }
          ]
          ++ modules;
        };
      c = (make [ ]).config;
      off = (make [ { androidDevices.charger.enable = false; } ]).config;
      recovery = (make [ { androidDevices.recovery.enable = true; } ]).config;
      image = c.system.build.mobileChargerImage;
    in
    assert lib.all (x: x.assertion) c.assertions;
    assert c.androidDevices.charger.enable;
    assert image.stdenv.buildPlatform.system == buildSystem;
    assert image.initrd.stdenv.buildPlatform.system == buildSystem;
    assert image.modules.stdenv.buildPlatform.system == buildSystem;
    assert c.androidDevices.charger.package.stdenv.hostPlatform.system == "aarch64-linux";
    assert c.androidDevices.charger.package.stdenv.buildPlatform.system == buildSystem;
    assert
      if device == "asphalt" then
        lib.all (name: builtins.elem name c.androidDevices.charger.kernelModules) [
          "qcom_pd_mapper"
          "qcom_battmgr"
          "ucsi_glink"
        ]
        && c.androidDevices.charger.display.fontWidth == 32
        && c.androidDevices.charger.statePath == c.androidDevices.charger.batteryPath
      else if device == "aurora" then
        c.androidDevices.charger.kernelModules == [ ]
        && c.androidDevices.charger.backlightPath == "/sys/class/backlight/n1-panel"
        && c.androidDevices.charger.inputPath == "/sys/class/power_supply/qcom-battmgr-usb"
        && c.androidDevices.charger.statePath == c.androidDevices.charger.batteryPath
        && lib.all c.androidDevices.kernelPackage.config.isYes [
          "BATTERY_QCOM_BATTMGR"
          "QCOM_Q6V5_PAS"
          "QCOM_PD_MAPPER"
          "QCOM_PMIC_GLINK"
          "RPMSG_QCOM_GLINK_SMEM"
          "DRM_PANEL_XIAOMI_N1"
          "INPUT_PM8941_PWRKEY"
        ]
      else
        c.androidDevices.charger.kernelModules == [ ]
        && c.androidDevices.charger.statePath == c.androidDevices.charger.inputPath
        && c.androidDevices.charger.display.widthMm == 68
        && c.androidDevices.charger.display.heightMm == 136;
    assert !(builtins.hasAttr "mobileChargerImage" off.system.build);
    assert !(builtins.hasAttr "mobileChargerImage" recovery.system.build);
    assert !(builtins.hasAttr "EFI/android-devices/charger.efi" c.boot.loader.systemd-boot.extraFiles);
    assert lib.hasInfix "install-charger.py" c.boot.loader.systemd-boot.extraInstallCommands;
    assert lib.hasInfix (builtins.unsafeDiscardStringContext (
      toString image
    )) c.system.build.installBootLoader.text;
    assert lib.hasInfix "/EFI/android-devices/charger.efi" c.system.build.mobileBootFiles.buildCommand;
    {
      image = image.drvPath;
      initrd = image.initrd.drvPath;
      modules = c.androidDevices.charger.kernelModules;
    }
  )
)
