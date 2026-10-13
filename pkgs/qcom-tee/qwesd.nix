# Qualcomm Wireless Edge Services daemon (qwesd), prebuilt by Qualcomm for
# Qualcomm Linux (meta-qcom recipes-security/qwes/qwes_1.1.bb). It hosts the QMI
# QTEE license service the modem uses for licensed features. Fetched from
# Qualcomm at build time; never vendored. The QTEE trusted applications in the
# tarball are for other SoCs and are not installed.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  patchelf,
  curl,
  openssl,
  minkipc,
  qcbor,
  qmi-framework,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "qwesd";
  version = "1.3-260620";

  # Qualcomm may remove this file (meta-qcom master no longer fetches it).
  # With a local copy, add it to the store under the same hash:
  #   nix-store --add-fixed sha256 qwes_1.0_armv8a.tar.gz
  src = fetchurl {
    url = "https://softwarecenter.qualcomm.com/nexus/generic/software/chip/component/sec-userspace.qclinux.0.0/260620/prebuilt_yocto/qwes_1.0_armv8a.tar.gz";
    hash = "sha256-e7INqpFuSxPlSUirkK+S6cLmEpzCLaGiO5JK2z8GENQ=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [
    autoPatchelfHook
    patchelf
  ];
  buildInputs = [
    curl
    openssl
    minkipc
    qcbor
    qmi-framework
    stdenv.cc.cc.lib
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 usr/bin/qwesd usr/bin/qwes_cli -t $out/bin
    install -Dm644 usr/share/doc/qwes/LICENSE.qcom-2 usr/share/doc/qwes/NOTICE.txt \
      usr/share/doc/qwes/CHANGELOG.md -t $out/share/doc/qwes
    install -Dm644 usr/lib/systemd/system/qwesd.service -t $out/share/doc/qwes/upstream
    # The QCBOR symbols it imports come from libminkadaptor's libqcbor; name
    # the library instead of relying on load order.
    patchelf --add-needed libqcbor.so.1 $out/bin/qwesd
    runHook postInstall
  '';

  meta = {
    description = "Qualcomm Wireless Edge Services daemon (prebuilt)";
    homepage = "https://github.com/qualcomm-linux/meta-qcom";
    license = {
      shortName = "qcom-2";
      fullName = "Qualcomm Technologies, Inc. Proprietary License (LICENSE.qcom-2)";
      url = "https://github.com/qualcomm-linux/meta-qcom/blob/master/licenses/LICENSE.qcom-2";
      free = false;
      redistributable = true;
    };
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "qwesd";
    platforms = [ "aarch64-linux" ];
  };
})
