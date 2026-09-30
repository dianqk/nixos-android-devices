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
in
{
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
            # Reserve a full new payload before invoking the standard installer.
            # This is conservative when generations share kernel/initrd files.
            needed=16777216
            for payload in ${config.system.build.kernel}/Image \
              ${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile} \
              ${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name} \
              ${config.systemd.package}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi; do
              bytes=$(${pkgs.coreutils}/bin/stat -Lc %s "$payload")
              needed=$((needed + bytes))
            done
            available=$(${pkgs.coreutils}/bin/df -B1 --output=avail /boot | ${pkgs.coreutils}/bin/tail -n 1)
            test "$available" -ge "$needed" || {
              echo "${cfg.deviceName} /boot needs $needed free bytes for this update; available: $available" >&2; exit 1;
            }
          ''}
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
          EOF
          cat > $out/loader/entries/nixos-generation-1.conf <<EOF
          title NixOS (${cfg.deviceName})
          linux /EFI/nixos/kernel.efi
          initrd /EFI/nixos/initrd
          devicetree /EFI/nixos/board.dtb
          options init=${config.system.build.toplevel}/init ${lib.concatStringsSep " " config.boot.kernelParams}
          EOF
        '';
  };
}
