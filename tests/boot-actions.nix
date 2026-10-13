{ flake }:
let
  lib = flake.inputs.nixpkgs.lib;
in
lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
  buildSystem:
  let
    make =
      device: modules:
      flake.lib.mkSystem {
        nixpkgsConfig.allowUnfreePredicate =
          package:
          builtins.elem (lib.getName package) [
            "aurora-firmware"
            "aurora-firmware-zstd"
            "aurora-touch"
          ];
        inherit device buildSystem;
        modules = [
          {
            androidDevices.usbSerial = "boot-actions-${device}";
            androidDevices.persistentImage.rootfs.uuid = "11111111-2222-3333-4444-555555555555";
          }
        ]
        ++ modules;
      };
    inspect =
      system:
      let
        c = system.config;
      in
      {
        actions = builtins.removeAttrs c.androidDevices.boot.actions [ "helperPackage" ];
        entries = c.boot.loader.systemd-boot.extraEntries;
        files = c.boot.loader.systemd-boot.extraFiles;
        hook = c.boot.loader.systemd-boot.extraInstallCommands;
        initial =
          if c.androidDevices.recovery.enable then "" else c.system.build.mobileBootFiles.buildCommand;
        firmwareConfig = c.androidDevices.boot.firmwarePackage.firmware.extraConfig;
      };
    valid =
      s:
      assert lib.all (a: a.assertion) s.config.assertions;
      s;
  in
  {
    firmwarePolicy =
      let
        profile = args: import ../pkgs/u-boot/boot-actions.nix args;
        rejected = args: !(builtins.tryEval (profile args)).success;
      in
      assert rejected {
        profile = "qcom-ab";
        confirmationNonGptLunMask = -1;
      };
      assert rejected {
        profile = "qcom-ab";
        confirmationNonGptLunMask = 256;
      };
      assert rejected {
        profile = "qcom-ab";
        confirmationNonGptLunMask = "192";
      };
      assert rejected {
        profile = "pon";
        confirmationNonGptLunMask = 192;
      };
      assert rejected {
        profile = "none";
        confirmationNonGptLunMask = 192;
      };
      assert lib.all
        (
          mask:
          rejected {
            profile = "qcom-ab";
            androidNonGptLunMask = mask;
          }
        )
        [
          (-1)
          256
          "192"
        ];
      assert rejected {
        profile = "pon";
        androidNonGptLunMask = 192;
      };
      assert rejected {
        profile = "none";
        androidNonGptLunMask = 192;
      };
      assert rejected {
        profile = "pon";
        chargerConfirmationPath = "/EFI/android-devices/charger.efi";
      };
      assert rejected {
        profile = "qcom-ab";
        chargerConfirmationPath = "bad\"value";
      };
      assert lib.hasInfix ''CONFIRM_CHARGER_PATH=""'' (profile {
        profile = "qcom-ab";
      });
      assert lib.hasInfix "ANDROID_NON_GPT_LUN_MASK=0" (profile {
        profile = "qcom-ab";
      });
      assert lib.hasInfix "CONFIRM_NON_GPT_LUN_MASK=0" (profile {
        profile = "qcom-ab";
      });
      profile {
        profile = "qcom-ab";
        confirmationNonGptLunMask = 192;
      };
    devices = lib.genAttrs [ "polaris" "clover" "asphalt" "sheng" "aurora" ] (
      device:
      let
        s = valid (make device [ ]);
        c = s.config;
        supported = true;
        ab = builtins.elem device [
          "asphalt"
          "sheng"
          "aurora"
        ];
        recovery = valid (make device [ { androidDevices.recovery.enable = true; } ]);
      in
      assert c.androidDevices.boot.actions.reboot == supported;
      assert c.androidDevices.boot.actions.poweroff == supported;
      assert c.androidDevices.boot.actions.bootloader == supported;
      assert c.androidDevices.boot.actions.recovery == supported;
      assert c.androidDevices.boot.actions.android == ab;
      assert c.androidDevices.boot.actions.recoveryTarget == (if ab then "slot-b" else "oem");
      assert lib.hasInfix (
        "options " + (if ab then "recovery-b" else "recovery")
      ) c.boot.loader.systemd-boot.extraEntries."android-recovery.conf";
      assert lib.hasInfix "needed=16777216" c.system.build.installBootLoader.text;
      assert (lib.hasInfix "/mobile-boot-action.efi" c.system.build.installBootLoader.text) == supported;
      assert
        builtins.attrNames c.boot.loader.systemd-boot.extraEntries == (
          if supported then
            [
              "android-bootloader.conf"
              "android-recovery.conf"
            ]
            ++ lib.optional ab "android-system.conf"
          else
            [ ]
        );
      assert
        (lib.hasInfix "CONFIG_EFI_MOBILE_BOOT_ACTION=y" c.androidDevices.boot.firmwarePackage.firmware.extraConfig)
        == supported;
      assert
        (lib.hasInfix "CONFIG_EFI_MOBILE_BOOT_ACTION_QCOM_AB=y" c.androidDevices.boot.firmwarePackage.firmware.extraConfig)
        == ab;
      assert
        (lib.hasInfix "CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM=y" c.androidDevices.boot.firmwarePackage.firmware.extraConfig)
        == ab;
      assert
        (!ab)
        || lib.hasInfix ''CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_ESP="linux-boot"'' c.androidDevices.boot.firmwarePackage.firmware.extraConfig;
      assert
        (!ab)
        || lib.hasInfix (
          "CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_NON_GPT_LUN_MASK=" + (if device == "asphalt" then "192" else "0")
        ) c.androidDevices.boot.firmwarePackage.firmware.extraConfig;
      assert
        (!ab)
        || lib.hasInfix (
          "CONFIG_EFI_MOBILE_QCOM_AB_ANDROID_NON_GPT_LUN_MASK=" + (if device == "asphalt" then "192" else "0")
        ) c.androidDevices.boot.firmwarePackage.firmware.extraConfig;
      assert recovery.config.boot.loader.systemd-boot.extraFiles == { };
      assert recovery.config.boot.loader.systemd-boot.extraEntries == { };
      assert c.androidDevices.boot.actions.helperPackage.stdenv.buildPlatform.system == buildSystem;
      assert c.androidDevices.boot.actions.helperPackage.stdenv.hostPlatform.system == "aarch64-linux";
      inspect s
    );
    disabled = lib.genAttrs [ "polaris" "clover" "asphalt" "sheng" "aurora" ] (
      device:
      let
        s = valid (
          make device [
            {
              androidDevices.boot.actions = {
                reboot = false;
                poweroff = false;
                bootloader = false;
                recovery = false;
                android = false;
              };
            }
          ]
        );
      in
      assert s.config.boot.loader.systemd-boot.extraFiles == { };
      assert s.config.boot.loader.systemd-boot.extraEntries == { };
      assert !(lib.hasInfix "loader-actions.py" s.config.boot.loader.systemd-boot.extraInstallCommands);
      assert
        (lib.hasInfix "install-charger.py" s.config.boot.loader.systemd-boot.extraInstallCommands)
        == s.config.androidDevices.charger.enable;
      inspect s
    );
    recoveryOnly =
      let
        s = valid (
          make "polaris" [
            {
              androidDevices.boot.actions.bootloader = false;
            }
          ]
        );
      in
      assert
        builtins.attrNames s.config.boot.loader.systemd-boot.extraEntries == [ "android-recovery.conf" ];
      inspect s;
  }
)
