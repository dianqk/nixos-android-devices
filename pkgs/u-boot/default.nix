{
  lib,
  buildUBoot,
  fetchzip,
  buildPackages,
  mkAndroidBootImage,
  runCommand,
  packagingTools ? buildPackages,
}:
{ device }:
let
  boards = import ./devices.nix;
  directory = boards.${device} or (throw "Unsupported U-Boot device: ${device}");
  board = import directory;
  firmware =
    (buildUBoot {
      pname = "u-boot-${device}";
      version = "2026.10-rc5";
      src = fetchzip {
        url = "https://git.u-boot-project.org/u-boot/u-boot/-/archive/a06e89ab05eaa2b8344d521319399333cd760ae5/u-boot-a06e89ab05eaa2b8344d521319399333cd760ae5.tar.gz";
        hash = "sha256-P8/MBaIueMPC5cuCBcWfYLPKDhyZHVwEcEimoYC3tGE=";
      };
      defconfig = "qcom_defconfig";
      extraPatches = [
        ./patches/0001-acm-stop-cancelled-rx.patch
        ./patches/0002-acm-nonblocking-console.patch
        ./patches/0003-button-kbd-events.patch
        ./patches/0004-spmi-single-byte.patch
        ./patches/0005-pmic-gpio-input-state.patch
        ./patches/0006-simplefb-optional-properties.patch
        ./patches/0007-mobile-boot-action-protocol.patch
        ./patches/0008-mobile-ufs-boot-lun.patch
        ./patches/0009-mobile-qcom-ab-efi-confirm.patch
        ./patches/0010-acm-initialize-stdio.patch
      ]
      ++ board.patches;
      extraConfig =
        import (directory + "/../config.nix")
        + import ./boot-actions.nix {
          profile = board.bootActionProfile or "none";
          confirmationNonGptLunMask = board.bootActionConfirmationNonGptLunMask or 0;
          androidNonGptLunMask = board.bootActionAndroidNonGptLunMask or 0;
          chargerConfirmationPath = board.bootActionChargerConfirmationPath or "";
        }
        + board.config;
      configurePhase = ''
        runHook preConfigure
        make qcom_defconfig
        scripts/kconfig/merge_config.sh -m .config board/qualcomm/qcom-phone.config
        printf '%s' "$extraConfig" >> .config
        make olddefconfig
        cat ${board.environment} ${
          lib.optionalString (board.chargerEnvironment or false) "${./charger.env}"
        } > board/qualcomm/${device}.env
        runHook postConfigure
      '';
      filesToInstall = [
        "u-boot-nodtb.bin"
        "u-boot.dtb"
        ".config"
      ];
      extraMeta.platforms = [ "aarch64-linux" ];
    }).overrideAttrs
      (old: {
        # Retain buildUBoot's build-time interpreter fixes for scripts and tools.
        postPatch = (old.postPatch or "") + ''
          cp ${../mobile-boot-action/firmware.c} lib/efi_loader/efi_mobile_boot_action.c
          cp ${../mobile-boot-action/protocol.h} include/mobile_boot_action.h
          cp ${../mobile-boot-action/pon-transaction.h} lib/efi_loader/mobile_pon_transaction.h
          cp ${../mobile-boot-action/qcom-ab.h} lib/efi_loader/mobile_qcom_ab.h
          cp ${../mobile-boot-action/qcom-ab-firmware.h} lib/efi_loader/mobile_qcom_ab_firmware.h
          cp ${../mobile-boot-action/qcom-ab-confirm.h} lib/efi_loader/mobile_qcom_ab_confirm.h
        '';
        nativeBuildInputs = old.nativeBuildInputs ++ [ buildPackages.xxd ];
      });
  payload = runCommand "${device}-u-boot-payload" { nativeBuildInputs = [ packagingTools.gzip ]; } ''
    mkdir -p $out
    ${
      if board.compressKernel or true then
        "gzip -n -c ${firmware}/u-boot-nodtb.bin > $out/u-boot.gz"
      else
        "cp ${firmware}/u-boot-nodtb.bin $out/u-boot.gz"
    }
    ${lib.optionalString (board ? minimumKernelBytes) ''
      # Do not truncate a future payload that already exceeds this floor.
      if [ "$(stat -c %s $out/u-boot.gz)" -lt ${toString board.minimumKernelBytes} ]; then
        chmod u+w $out/u-boot.gz
        truncate -s ${toString board.minimumKernelBytes} $out/u-boot.gz
      fi
    ''}
    printf 'unused' | gzip -n > $out/ramdisk.gz
  '';
  image = mkAndroidBootImage (
    {
      name = "${device}-u-boot.img";
      kernel = "${payload}/u-boot.gz";
      initrd = "${payload}/ramdisk.gz";
      dtbs = [ "${firmware}/u-boot.dtb" ];
      cmdline = "";
      base = "0x00000000";
      kernelOffset = "0x00008000";
      ramdiskOffset = "0x01000000";
      secondOffset = "0x00000000";
      tagsOffset = "0x00000100";
      pageSize = "4096";
      maximumBytes = 67108864;
    }
    // (board.android or { })
  );
in
image.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    inherit firmware;
  };
})
