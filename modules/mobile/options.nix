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
      description = "FFmpeg with device decoder fixes, for use by media players and applications.";
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
      base = mkOption { type = types.str; };
      kernelOffset = mkOption { type = types.str; };
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
