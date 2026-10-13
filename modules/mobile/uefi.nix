{
  config,
  lib,
  androidPackages,
  pkgs,
  ...
}:
let
  cfg = config.androidDevices;
  enabled = cfg.enable && !cfg.recovery.enable;
  esp = cfg.boot.uefi.device;
  requireStandardEsp = cfg.boot.uefi.requireStandardEsp;
  efiArch = pkgs.stdenv.hostPlatform.efiArch;
  actions = cfg.boot.actions;
  specialActions = actions.bootloader || actions.recovery || actions.android;
  helperPath = "EFI/android-devices/mobile-boot-action.efi";
  loaderActions =
    lib.optionalString actions.reboot "auto-reboot yes\n"
    + lib.optionalString actions.poweroff "auto-poweroff yes\n";
  loaderActionsFile = androidPackages.packaging.writeText "mobile-loader-actions.conf" loaderActions;
  extraFiles = config.boot.loader.systemd-boot.extraFiles;
  extraEntries = config.boot.loader.systemd-boot.extraEntries;
  installExtra = path: source: ''
    install -Dm644 ${lib.escapeShellArg (toString source)} "$out/"${lib.escapeShellArg path}
    install -Dm644 /dev/null "$out/EFI/nixos/.extra-files/"${lib.escapeShellArg path}
  '';
in
{
  options.androidDevices.boot.actions = {
    reboot = lib.mkEnableOption "the pre-Linux systemd-boot reboot menu action";
    poweroff = lib.mkEnableOption "the pre-Linux systemd-boot power-off menu action";
    bootloader = lib.mkEnableOption "confirmed reboot to OEM bootloader using compatible U-Boot firmware";
    recovery = lib.mkEnableOption "confirmed reboot to the configured recovery target";
    recoveryTarget = lib.mkOption {
      type = lib.types.enum [
        "oem"
        "slot-b"
      ];
      default = "oem";
      description = "OEM recovery on non-A/B devices, or the installed NixOS recovery_b on Qualcomm A/B devices.";
    };
    android = lib.mkEnableOption "confirmed switch to Android boot_a using compatible Qualcomm A/B firmware";
    helperPackage = lib.mkOption {
      type = lib.types.package;
      default = androidPackages.mobile-boot-action;
      description = "ARM64 EFI helper implementing the mobile boot-action protocol.";
    };
  };
  options.androidDevices.boot.uefi = {
    requireStandardEsp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Require the standard GPT ESP type and check its configured size and update space. Disable only for a board-managed vendor-type FAT boot partition; mount and target identity checks still apply.";
    };
    espSizeBytes = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = 1073741824;
      description = "Expected standard ESP size; null accepts the measured size. Free-space checks still apply. Share this setting with recovery.";
    };
    device = lib.mkOption {
      type = lib.types.str;
      description = "Physical FAT boot partition; never an Android super logical partition.";
    };
  };
  # Apply to the upstream NixOS installer instead of copying its implementation.
  options.system.build.installBootLoader = lib.mkOption {
    apply =
      installer:
      if enabled then
        androidPackages.packaging.writeShellScript "mobile-install-systemd-boot" ''
          set -eu
          test "$(${pkgs.util-linux}/bin/findmnt -rn -M /boot -o FSTYPE)" = vfat || {
            echo 'Mount the prepared FAT boot partition at /boot first' >&2; exit 1;
          }
          actual=$(${pkgs.util-linux}/bin/findmnt -rn -M /boot -o SOURCE)
          test "$(${pkgs.coreutils}/bin/readlink -f "$actual")" = "$(${pkgs.coreutils}/bin/readlink -f ${lib.escapeShellArg esp})" || {
            echo 'The mounted /boot does not match the configured physical partition' >&2; exit 1;
          }
          ${lib.optionalString (!requireStandardEsp) ''
            # The board retains the vendor GPT type on its FAT boot partition.
            export SYSTEMD_RELAX_ESP_CHECKS=1
          ''}
          ${lib.optionalString requireStandardEsp ''
            ${lib.optionalString (cfg.boot.uefi.espSizeBytes != null) ''
              test "$(${pkgs.util-linux}/bin/blockdev --getsize64 "$actual")" = ${toString cfg.boot.uefi.espSizeBytes} || {
                echo '${cfg.deviceName} /boot does not match androidDevices.boot.uefi.espSizeBytes' >&2; exit 1;
              }
            ''}
            test "$(${pkgs.util-linux}/bin/blkid -p -s PART_ENTRY_TYPE -o value "$actual")" = c12a7328-f81f-11d2-ba4b-00a0c93ec93b || {
              echo '${cfg.deviceName} /boot must have the standard GPT ESP type' >&2; exit 1;
            }
          ''}
          # Reserve a full new payload on both standard and vendor-type FAT ESPs.
          # This is conservative when generations share kernel/initrd files.
          needed=16777216
          for payload in ${config.system.build.kernel}/Image \
            ${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile} \
            ${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name} \
            ${config.systemd.package}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi; do
            bytes=$(${pkgs.coreutils}/bin/stat -Lc %s "$payload")
            needed=$((needed + bytes))
          done
          ${lib.optionalString specialActions ''
            bytes=$(${pkgs.coreutils}/bin/stat -Lc %s ${actions.helperPackage}/mobile-boot-action.efi)
            needed=$((needed + bytes))
          ''}
          ${lib.optionalString cfg.charger.enable ''
            bytes=$(${pkgs.coreutils}/bin/stat -Lc %s ${config.system.build.mobileChargerImage})
            needed=$((needed + bytes))
          ''}
          available=$(${pkgs.coreutils}/bin/df -B1 --output=avail /boot | ${pkgs.coreutils}/bin/tail -n 1)
          test "$available" -ge "$needed" || {
            echo "${cfg.deviceName} /boot needs $needed free bytes for this update; available: $available" >&2; exit 1;
          }
          # Fresh roots have not activated /etc yet. bootctl still needs the
          # selected OS identity to derive its entry token, even without EFI vars.
          export SYSTEMD_OS_RELEASE=${config.environment.etc."os-release".source}
          exec ${installer} "$@"
        ''
      else
        installer;
  };
  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = config.boot.loader.systemd-boot.enable;
        message = "Installed mobile systems require U-Boot and systemd-boot.";
      }
      {
        assertion = cfg.persistentImage.enable;
        message = "Mobile UEFI requires a persistent ext4 root.";
      }
      {
        assertion = lib.hasPrefix "/dev/disk/by-part" esp && !(lib.hasInfix "super" esp);
        message = "Use an explicit physical GPT partition for mobile /boot.";
      }
      {
        assertion = !specialActions || config.boot.loader.systemd-boot.xbootldrMountPoint == null;
        message = "Mobile boot actions require their entries and EFI helper on the same ESP.";
      }
    ];
    system.boot.loader.kernelFile = lib.mkForce "Image";
    hardware.deviceTree = {
      enable = lib.mkForce true;
    };
    boot.loader = {
      systemd-boot = {
        enable = true;
        installDeviceTree = true;
        configurationLimit = lib.mkDefault 10;
        extraFiles = lib.optionalAttrs specialActions {
          ${helperPath} = "${actions.helperPackage}/mobile-boot-action.efi";
        };
        extraEntries =
          lib.optionalAttrs actions.bootloader {
            "android-bootloader.conf" = ''
              title Reboot to bootloader
              sort-key z-android-action
              efi /${helperPath}
              options bootloader
            '';
          }
          // lib.optionalAttrs actions.recovery {
            "android-recovery.conf" = ''
              title Reboot to recovery
              sort-key z-android-action
              efi /${helperPath}
              options ${if actions.recoveryTarget == "slot-b" then "recovery-b" else "recovery"}
            '';
          }
          // lib.optionalAttrs actions.android {
            "android-system.conf" = ''
              title Reboot to Android
              sort-key z-android-action
              efi /${helperPath}
              options android
            '';
          };
        extraInstallCommands = lib.mkAfter (
          lib.optionalString (loaderActions != "") ''
            ${pkgs.python3}/bin/python3 ${./loader-actions.py} /boot/loader/loader.conf ${loaderActionsFile}
          ''
          + lib.optionalString cfg.charger.enable ''
            ${pkgs.python3}/bin/python3 ${./install-charger.py} ${config.system.build.mobileChargerImage} /boot
          ''
        );
      };
      efi = {
        canTouchEfiVariables = false;
        efiSysMountPoint = "/boot";
      };
      timeout = lib.mkDefault 5;
    };
    fileSystems."/boot" = {
      device = esp;
      fsType = "vfat";
      options = [ "umask=0077" ];
    };
    system.systemBuilderCommands = ''
      touch $out/mobile-efi
      printf '%s\n' ${lib.escapeShellArg cfg.deviceName} > $out/mobile-device
      ln -s ${config.system.build.mobileBootImage} $out/mobile-boot.img
    '';
    system.build.mobileBootFiles =
      androidPackages.packaging.runCommand "${cfg.deviceName}-boot-files" { }
        ''
          mkdir -p $out/EFI/BOOT $out/EFI/nixos $out/loader/entries
          cp ${config.systemd.package}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi $out/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI
          cp ${config.system.build.kernel}/Image $out/EFI/nixos/kernel.efi
          cp ${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile} $out/EFI/nixos/initrd
          cp ${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name} $out/EFI/nixos/board.dtb
          cat > $out/loader/loader.conf <<EOF
          default nixos-generation-1.conf
          timeout 5
          editor no
          ${loaderActions}
          EOF
          cat > $out/loader/entries/nixos-generation-1.conf <<EOF
          title NixOS (${cfg.deviceName})
          linux /EFI/nixos/kernel.efi
          initrd /EFI/nixos/initrd
          devicetree /EFI/nixos/board.dtb
          options init=${config.system.build.toplevel}/init ${lib.concatStringsSep " " config.boot.kernelParams}
          EOF
          ${lib.concatStrings (lib.mapAttrsToList installExtra extraFiles)}
          ${lib.optionalString cfg.charger.enable ''
            install -Dm644 ${config.system.build.mobileChargerImage} $out/EFI/android-devices/charger.efi
          ''}
          ${lib.concatStrings (
            lib.mapAttrsToList (
              name: value: installExtra "loader/entries/${name}" (androidPackages.packaging.writeText name value)
            ) extraEntries
          )}
        '';
  };
}
