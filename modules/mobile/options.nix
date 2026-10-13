{
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  inherit (lib) mkOption types;
in
{
  options.androidDevices = {
    camera.package = mkOption {
      type = types.package;
      default = androidPackages.libcamera;
      description = "Libcamera with the supported mobile sensors and software ISP helpers.";
    };
    video.ffmpegPackage = mkOption {
      type = types.package;
      default = pkgs.ffmpeg;
      description = "FFmpeg for media applications; defaults to upstream nixpkgs. Device-patched builds are opt-in.";
    };
    role = mkOption {
      type = types.enum [
        "system"
        "recovery"
      ];
      default = "system";
    };
    kernelPackage = mkOption { type = types.package; };
    initrdFirmware = mkOption {
      type = types.listOf types.package;
      default = [ ];
    };
    usb = {
      enable = mkOption {
        type = types.bool;
        default = true;
      };
      vendorId = mkOption {
        type = types.str;
        default = "18d1";
      };
    };
    boot.android = {
      kernelFile = mkOption {
        type = types.str;
        default = "Image.gz";
      };
      headerVersion = mkOption {
        type = types.ints.between 0 4;
        default = 0;
      };
      osVersion = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Android boot header OS version for bootloaders that require it; this is firmware compatibility metadata, not the Linux kernel version.";
      };
      osPatchLevel = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Android boot header security patch date (YYYY-MM-DD) matching the selected factory firmware baseline.";
      };
      base = mkOption { type = types.str; };
      kernelOffset = mkOption { type = types.str; };
      arm64LoadOffset = mkOption {
        type = types.nullOr (types.ints.between 4096 2093056);
        default = null;
        description = "Legacy firmware load offset within a 2 MiB boundary. Wrap the arm64 payload so the unchanged kernel starts at the next boundary; direct Android boot only, not EFI.";
      };
      ramdiskOffset = mkOption { type = types.str; };
      secondOffset = mkOption { type = types.str; };
      tagsOffset = mkOption { type = types.str; };
      pageSize = mkOption { type = types.str; };
      dtbs = mkOption { type = types.listOf types.str; };
      dtbPlacement = mkOption {
        type = types.enum [
          "append-to-kernel"
          "boot-image"
        ];
        default = "append-to-kernel";
      };
      dtbOffset = mkOption {
        type = types.str;
        default = "0x00000000";
      };
      avbFooter = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              partitionName = mkOption {
                type = types.strMatching "[a-zA-Z0-9_]+";
                description = "AVB partition name without the A/B slot suffix.";
              };
              partitionSize = mkOption {
                type = types.ints.positive;
                description = "Physical partition size in bytes, including the AVB footer.";
              };
            };
          }
        );
        default = null;
        description = "Append deterministic unsigned AVB metadata for an unlocked bootloader, padding to the partition size.";
      };
      maximumBytes = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
      };
    };
  };
}
