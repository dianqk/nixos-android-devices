# libqcomtee: object interface to QTEE through the Linux QCOMTEE driver.
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  qcbor,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "qcomtee";
  version = "1.0.2";

  src = fetchFromGitHub {
    owner = "quic";
    repo = "quic-teec";
    tag = "v${finalAttrs.version}";
    hash = "sha256-i3rj0DmFPlch5E/9P5wxQ9aiBYtFxaKVjo0tR4UoV7o=";
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [ qcbor ];
  cmakeFlags = [
    (lib.cmakeBool "BUILD_SHARED_LIBS" true)
    (lib.cmakeFeature "QCBOR_DIR_HINT" "${qcbor}")
  ];

  meta = {
    description = "Library for communicating with QTEE through the QCOMTEE driver";
    homepage = "https://github.com/quic/quic-teec";
    license = lib.licenses.bsd3;
    platforms = [ "aarch64-linux" ];
  };
})
