{ lib, androidPackages, ... }:
{
  androidDevices.video.ffmpegPackage = lib.mkDefault androidPackages.devices.polaris.ffmpeg;
}
