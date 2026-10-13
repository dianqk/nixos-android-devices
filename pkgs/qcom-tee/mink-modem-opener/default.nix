# IMinkModemOpener bridge: QRTR service 5013 for the modem's QTEE sessions
# (Smart Transmit licensing), built from minkipc's MinkSocket transport and
# MinkModemOpener without the Android-only parts of the HLOS Mink daemon.
{
  lib,
  stdenv,
  meson,
  ninja,
  pkg-config,
  minkipc,
  mink-idl-compiler,
  qrtr,
}:
stdenv.mkDerivation {
  pname = "mink-modem-opener";
  version = "0.1.0-minkipc${minkipc.version}";

  inherit (minkipc) src;

  patches = [ ./0001-minksocket-build-on-glibc-without-remote-shared-memory.patch ];

  postPatch = ''
    cp -r ${./src} mink-modem-opener
    chmod -R u+w mink-modem-opener
    cp mink-modem-opener/meson.build meson.build
  '';

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    mink-idl-compiler
  ];
  buildInputs = [
    minkipc
    qrtr
  ];

  meta = {
    description = "QRTR IMinkModemOpener service that lets the modem reach QTEE";
    license = with lib.licenses; [
      bsd3Clear
      bsd3
    ];
    mainProgram = "mink-modem-opener";
    platforms = [ "aarch64-linux" ];
  };
}
