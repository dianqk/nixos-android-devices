{
  lib,
  buildUBoot,
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
  # The board's platform selects the upstream defconfig, base fragment,
  # environment directory and the shared patches that apply to it.
  platform =
    (import ./platforms.nix).${board.platform or "qualcomm"}
      or (throw "Unsupported U-Boot platform: ${board.platform}");
  bootActionProfile = board.bootActionProfile or "none";
  firmware =
    (buildUBoot {
      pname = "u-boot-${device}";
      inherit (platform) defconfig;
      extraPatches = platform.patches ++ board.patches;
      extraConfig =
        import (directory + "/../config.nix")
        + import ./boot-actions.nix {
          profile =
            assert lib.assertMsg (
              platform.bootActions || bootActionProfile == "none"
            ) "U-Boot boot actions are unavailable on the ${board.platform} platform";
            bootActionProfile;
          confirmationNonGptLunMask = board.bootActionConfirmationNonGptLunMask or 0;
          androidNonGptLunMask = board.bootActionAndroidNonGptLunMask or 0;
          nonSlotPartitionNames = board.bootActionNonSlotPartitionNames or [ ];
          chargerConfirmationPath = board.bootActionChargerConfirmationPath or "";
        }
        + board.config;
      configurePhase = ''
        runHook preConfigure
        make ${platform.defconfig}
        ${lib.optionalString (
          platform.baseConfig != null
        ) "scripts/kconfig/merge_config.sh -m .config ${platform.baseConfig}"}
        printf '%s' "$extraConfig" >> .config
        make olddefconfig
        cat ${board.environment} ${
          lib.optionalString (board.chargerEnvironment or false) "${./charger.env}"
        } > ${platform.environmentDirectory}/${device}.env
        runHook postConfigure
      '';
      filesToInstall = [
        "u-boot-nodtb.bin"
        "u-boot.dtb"
        ".config"
      ]
      ++ lib.optional (board ? payload) board.payload
      ++ (board.extraFirmwareFiles or [ ]);
      extraMeta.platforms = [ "aarch64-linux" ];
    }).overrideAttrs
      (old: {
        # Retain buildUBoot's build-time interpreter fixes for scripts and tools.
        postPatch =
          (old.postPatch or "")
          + ''
            cp ${../mobile-boot-action/firmware.c} lib/efi_loader/efi_mobile_boot_action.c
            cp ${../mobile-boot-action/protocol.h} include/mobile_boot_action.h
            cp ${../mobile-boot-action/pon-transaction.h} lib/efi_loader/mobile_pon_transaction.h
            cp ${../mobile-boot-action/qcom-ab.h} lib/efi_loader/mobile_qcom_ab.h
            cp ${../mobile-boot-action/qcom-ab-firmware.h} lib/efi_loader/mobile_qcom_ab_firmware.h
            cp ${../mobile-boot-action/qcom-ab-confirm.h} lib/efi_loader/mobile_qcom_ab_confirm.h
          ''
          + lib.optionalString (board.bootChoiceContext or false) ''
            cp ${../boot-choice-context/durable-io.h} lib/efi_loader/boot_choice_durable_io.h
            cp ${../boot-choice-context/firmware.c} lib/efi_loader/efi_boot_choice_context.c
            cp ${../boot-choice-context/context.h} include/boot-choice-context.h
            cp ${../../tools/boot-choice/context-wire.h} include/boot-choice-context-wire.h
            cp ${../../tools/early-entry/commit-intent.c} lib/efi_loader/boot_choice_wire.c
            cp ${../../tools/early-entry/commit-intent.h} include/commit-intent.h
          '';
        nativeBuildInputs = old.nativeBuildInputs ++ [ buildPackages.xxd ];
      });
  # The DTB that the bootloader merges dtbo overlays into. Boards listing the
  # labels a stock dtbo references get them redirected to sink nodes, so the
  # merge succeeds without changing the real nodes (abl-dtbo-sink.py).
  controlDtb =
    if board ? ablDtboSinkLabels then
      runCommand "${device}-u-boot-dtb"
        {
          nativeBuildInputs = [ (packagingTools.python3.withPackages (ps: [ ps.libfdt ])) ];
        }
        ''
          python3 -I ${./abl-dtbo-sink.py} ${firmware}/u-boot.dtb $out ${board.ablDtboSinkLabels}
        ''
    else
      "${firmware}/u-boot.dtb";
  # Legacy LZ4 frames match kernels that MediaTek LK decompresses itself.
  lz4Kernel = (board.kernelCompression or "gzip") == "lz4-legacy";
  payload =
    runCommand "${device}-u-boot-payload"
      {
        nativeBuildInputs = [ packagingTools.gzip ] ++ lib.optional lz4Kernel packagingTools.lz4;
      }
      ''
        mkdir -p $out
        ${
          if lz4Kernel then
            "lz4 -l -9 -c ${firmware}/${board.payload or "u-boot-nodtb.bin"} > $out/u-boot.gz"
          else if board.compressKernel or true then
            "gzip -n -c ${firmware}/${board.payload or "u-boot-nodtb.bin"} > $out/u-boot.gz"
          else
            "cp ${firmware}/${board.payload or "u-boot-nodtb.bin"} $out/u-boot.gz"
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
  mkImage =
    { name, initrd }:
    mkAndroidBootImage (
      {
        inherit name initrd;
        kernel = "${payload}/u-boot.gz";
        # A board whose payload already carries its control DTB (OF_SEPARATE
        # u-boot.bin) receives no second, appended DTB unless its loader
        # selects the image by the appended DTB's identifiers.
        dtbs = lib.optional (board.appendDeviceTree or (!(board ? payload))) "${controlDtb}";
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
  image = mkImage {
    name = "${device}-u-boot.img";
    # Header v4 boards may ship no boot ramdisk, like their stock boot image.
    initrd = if board.emptyRamdisk or false then null else "${payload}/ramdisk.gz";
  };
in
if !(board.standaloneBootImage or true) then
  firmware
else
  image.overrideAttrs (old: {
    passthru = (old.passthru or { }) // {
      inherit firmware;
      # The same boot image carrying a payload (such as a recovery FIT) as its
      # ramdisk, for boards whose U-Boot boots that payload.
      withRamdisk =
        { name, ramdisk }:
        (mkImage {
          inherit name;
          initrd = ramdisk;
        }).overrideAttrs
          (old: {
            passthru = (old.passthru or { }) // {
              inherit firmware;
              payload = ramdisk;
            };
          });
    };
  })
