{ mkFirmwareArchive }:
# Alldocube iPlay 80 mini Ultra stock Android 14 connsys payload.
mkFirmwareArchive {
  name = "t880-firmware-source";
  url = "https://github.com/dianqk/nixos-android-devices/releases/download/firmware/t880-firmware-UP1A.231005.007-1781075581-20261022.tar.zst";
  hash = "sha256-nxtkVSiGLFA4KzUnjAWd8eK9NosFvuXGXQCUeXaUH+k=";
}
