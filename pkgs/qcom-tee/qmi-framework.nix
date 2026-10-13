# Qualcomm QMI client/service framework over QRTR (libqcci, libqcsi,
# libqmi_common, libqencdec).
{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  pkg-config,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "qmi-framework";
  version = "0.1.4";

  src = fetchFromGitHub {
    owner = "quic";
    repo = "qmi-framework";
    tag = "v${finalAttrs.version}";
    hash = "sha256-+HqgrCVg1VkfjhE9uEtLas0JWeEjYMssZGjR+2ofrbE=";
  };

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
  ];

  meta = {
    description = "Qualcomm QMI client and service framework over QRTR";
    homepage = "https://github.com/quic/qmi-framework";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
})
