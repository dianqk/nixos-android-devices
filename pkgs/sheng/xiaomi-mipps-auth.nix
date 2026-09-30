{
  fetchurl,
  glib,
  lib,
  python3,
  systemd,
  writeShellApplication,
}:
let
  src = fetchurl {
    url = "https://raw.githubusercontent.com/ianchb/xiaomi-mipps-auth/9176efbdf276b874fc0a97912a914449a88155fb/xiaomi-mipps-auth";
    hash = "sha256-W0Ka7+jD9ZfsQFV3VBbgUEeWVSAFOdBHOHxR2V3v1i4=";
  };
in
writeShellApplication {
  name = "xiaomi-mipps-auth";
  runtimeInputs = [
    glib
    systemd
  ];
  text = ''
    exec ${lib.getExe python3} ${src} "$@"
  '';
  meta = {
    description = "Automatic Xiaomi MiPPS/PPS charger authentication for sheng";
    homepage = "https://github.com/ianchb/xiaomi-mipps-auth";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
    mainProgram = "xiaomi-mipps-auth";
  };
}
