{
  config,
  lib,
  androidPackages,
  extendModules,
  ...
}:
let
  cfg = config.androidDevices;
  android = cfg.boot.android;
  kernel = config.system.build.kernel;
  recoveryDtb =
    if cfg.boot.recoveryDeviceTree != null then
      cfg.boot.recoveryDeviceTree
    else
      "${kernel}/${builtins.head android.dtbs}";
  mkBootImage =
    {
      name,
      initrd,
      cmdline,
      dtbs ? map (dtb: "${kernel}/${dtb}") android.dtbs,
    }:
    androidPackages.mkAndroidBootImage {
      inherit
        name
        initrd
        cmdline
        ;
      dtbs = map (
        dtb:
        if android.dtbProperties == { } then
          dtb
        else
          androidPackages.packaging.runCommand "${cfg.deviceName}-loader.dtb"
            {
              nativeBuildInputs = [ androidPackages.buildPackages.dtc ];
            }
            (
              ''
                cp ${lib.escapeShellArg dtb} "$out"
                chmod u+w "$out"
              ''
              + lib.concatStringsSep "\n" (
                lib.mapAttrsToList (
                  property: values:
                  "fdtput -t x \"$out\" / ${lib.escapeShellArg property} ${
                    lib.concatMapStringsSep " " lib.toHexString values
                  }"
                ) android.dtbProperties
              )
            )
      ) dtbs;
      kernel = "${kernel}/${android.kernelFile}";
      inherit (android)
        headerVersion
        osVersion
        osPatchLevel
        base
        kernelOffset
        arm64LoadOffset
        ramdiskOffset
        secondOffset
        tagsOffset
        pageSize
        dtbPlacement
        dtbOffset
        maximumBytes
        avbFooter
        ;
    };
  bootImage = mkBootImage {
    name = "${cfg.deviceName}-${cfg.role}-boot.img";
    initrd = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
    cmdline = lib.concatStringsSep " " config.boot.kernelParams;
    dtbs =
      if cfg.recovery.enable && cfg.boot.recoveryDeviceTree != null then
        [ recoveryDtb ]
      else
        map (dtb: "${kernel}/${dtb}") android.dtbs;
  };
  # The FIT kernel as LZMA (`lzma_alone`, the format U-Boot decompresses),
  # for bootloaders that limit the size of the ramdisk carrying the FIT.
  recoveryFitKernel =
    if cfg.boot.recoveryFitKernelCompression == "lzma" then
      androidPackages.packaging.runCommand "${cfg.deviceName}-recovery-kernel.lzma"
        { nativeBuildInputs = [ androidPackages.packaging.xz ]; }
        ''
          xz --format=lzma -9e -c ${kernel}/Image > $out
        ''
    else
      "${kernel}/${android.kernelFile}";
  # Recovery as a FIT in the ramdisk of the board's U-Boot boot image.
  recoveryFit =
    (androidPackages.mkRecoveryFit {
      name = "${cfg.deviceName}-${cfg.role}.itb";
      kernel = recoveryFitKernel;
      kernelCompression = cfg.boot.recoveryFitKernelCompression;
      initrd = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
      dtb = recoveryDtb;
      cmdline = lib.concatStringsSep " " config.boot.kernelParams;
      maximumBytes = cfg.boot.recoveryFitMaximumBytes;
    }).overrideAttrs
      (old: {
        passthru = (old.passthru or { }) // {
          initialRamdisk = config.system.build.initialRamdisk;
          kernelPackage = kernel;
        };
      });
  chainloadedImage = cfg.boot.firmwarePackage.withRamdisk {
    name = "${cfg.deviceName}-${cfg.role}-boot.img";
    ramdisk = recoveryFit;
  };
  chainloaded = cfg.boot.recoveryLoader == "u-boot-fit";
  rawFit = cfg.boot.recoveryLoader == "fit";
  direct =
    (extendModules {
      modules = [ (import ./direct-boot-initrd.nix { systemPath = config.system.build.toplevel; }) ];
    }).config;
  directImage = mkBootImage {
    name = "${cfg.deviceName}-boot-kernel.img";
    dtbs = [ "${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}" ];
    initrd = "${direct.system.build.initialRamdisk}/${direct.system.boot.loader.initrdFile}";
    cmdline = lib.concatStringsSep " " (
      config.boot.kernelParams ++ [ "init=${config.system.build.toplevel}/init" ]
    );
  };
in
{
  options.androidDevices.boot = {
    firmwarePackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Board-supplied firmware providing UEFI, as a standalone image or raw embedding inputs selected by the board.";
    };
    standaloneFirmwareImage = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Expose an installed standalone firmware boot image. Embedding-only boards disable this; raw firmware and RAM recovery remain separate.";
    };
    directKernel.enable = lib.mkEnableOption "the supplemental Android-format direct-kernel boot artifact";
    recoveryDeviceTree = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional board-supplied DTB for RAM recovery; defaults to the first boot.android.dtbs entry from the selected kernel.";
    };
    recoveryFitMaximumBytes = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Largest accepted recovery FIT, such as the U-Boot fastboot download buffer.";
    };
    recoveryFitKernelCompression = lib.mkOption {
      type = lib.types.enum [
        "gzip"
        "lzma"
      ];
      default = "gzip";
      description = "Kernel compression inside the `u-boot-fit` recovery FIT; `lzma` needs U-Boot LZMA support and keeps the FIT smaller.";
    };
    recoveryLoader = lib.mkOption {
      type = lib.types.enum [
        "kernel"
        "u-boot-fit"
        "fit"
      ];
      default = "kernel";
      description = ''
        How the bootloader starts RAM recovery: `kernel` puts the recovery
        kernel, initrd and DTB directly in an Android boot image; `u-boot-fit`
        builds the board's U-Boot boot image (boot.firmwarePackage) with a FIT
        of kernel, initrd and the first boot.android.dtbs entry as its ramdisk,
        which that U-Boot boots. `fit` exports a raw host-supplied FIT for an
        already running U-Boot, without an Android boot-image wrapper.
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.recovery.enable || cfg.boot.firmwarePackage != null;
        message = "Installed mobile systems require androidDevices.boot.firmwarePackage.";
      }
      {
        assertion =
          !chainloaded
          || (
            cfg.boot.firmwarePackage != null && cfg.boot.firmwarePackage ? withRamdisk && android.dtbs != [ ]
          );
        message = "u-boot-fit recovery requires a U-Boot firmwarePackage that accepts a ramdisk payload and a recovery DTB.";
      }
    ];
    system.build =
      lib.optionalAttrs (cfg.recovery.enable || cfg.boot.standaloneFirmwareImage) {
        mobileBootImage =
          if cfg.recovery.enable then
            (
              if rawFit then
                recoveryFit
              else if chainloaded then
                chainloadedImage
              else
                bootImage
            )
          else
            cfg.boot.firmwarePackage;
      }
      // lib.optionalAttrs cfg.recovery.enable {
        mobileRecoveryFit = recoveryFit;
      }
      // lib.optionalAttrs (!cfg.recovery.enable && cfg.boot.directKernel.enable) {
        mobileDirectBootImage = directImage.overrideAttrs (old: {
          passthru = (old.passthru or { }) // {
            targetSystem = config.system.build.toplevel;
            initrd = direct.system.build.initialRamdisk;
            inherit kernel;
          };
        });
      };
  };
}
