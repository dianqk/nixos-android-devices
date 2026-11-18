{
  fetchurl,
  python3,
  systemd,
  writeShellApplication,
  lib,
}:
let
  upstream = fetchurl {
    url = "https://raw.githubusercontent.com/ianchb/xiaomi-mipps-auth/9176efbdf276b874fc0a97912a914449a88155fb/xiaomi-mipps-auth";
    hash = "sha256-W0Ka7+jD9ZfsQFV3VBbgUEeWVSAFOdBHOHxR2V3v1i4=";
  };
in
writeShellApplication {
  name = "unicorn-mipps-auth";
  text = ''
    export USB_SIGNALLER_BUSCTL=${systemd}/bin/busctl
    export XIAOMI_MIPPS_UPSTREAM=${upstream}
    exec ${lib.getExe python3} ${./mipps-auth.py} "$@"
  '';
  passthru.upstream = upstream;
  meta = {
    description = "Unicorn Xiaomi charger authentication and input telemetry";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
    mainProgram = "unicorn-mipps-auth";
  };
}
