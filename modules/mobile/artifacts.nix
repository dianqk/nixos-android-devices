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
        dtbs
        ;
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
  };
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
      description = "Board-supplied firmware image providing UEFI for the installed system.";
    };
    directKernel.enable = lib.mkEnableOption "the supplemental Android-format direct-kernel boot artifact";
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.recovery.enable || cfg.boot.firmwarePackage != null;
        message = "Installed mobile systems require androidDevices.boot.firmwarePackage.";
      }
    ];
    system.build = {
      mobileBootImage = if cfg.recovery.enable then bootImage else cfg.boot.firmwarePackage;
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
