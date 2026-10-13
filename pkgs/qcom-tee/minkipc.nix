# MinkIPC userspace for QTEE: qtee_supplicant with its listeners (time, TA
# autoload, fs, gpfs, RPMB) and libminkadaptor. PKCS#11, MinkTEEC, the RPMB
# client tool and the bundled prebuilt TAs are not built or installed.
# withDebugLogs enables the fs/gpfs and time listeners' debug messages (every
# resolved path and request).
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  qcbor,
  qcomtee,
  mink-idl-compiler,
  linuxHeaders,
  withDebugLogs ? false,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "minkipc";
  version = "1.2.10";

  src = fetchFromGitHub {
    owner = "qualcomm";
    repo = "minkipc";
    tag = "v${finalAttrs.version}";
    hash = "sha256-WFA7bP0W2C8jFMKOcJva1Lb012BB9ZAnFph8hmFTFAg=";
  };

  # The supplicant dlopen()s its listeners by soname; use absolute paths.
  # Its messages and those of most listeners are printf()s: line-buffer stdout
  # so that they reach the journal when written.
  postPatch = ''
    substituteInPlace qtee_supplicant/src/listener_mngr.c \
      --replace-fail '"lib' "\"$out/lib/lib"
    substituteInPlace qtee_supplicant/src/qtee_supplicant.c \
      --replace-fail 'int main() {' 'int main() {
    setvbuf(stdout, NULL, _IOLBF, 0);'
  ''
  + lib.optionalString withDebugLogs ''
    substituteInPlace listeners/libfsservice/cmn/cmn.h \
      --replace-fail '#define MSGV(...)' '#define MSGV printf' \
      --replace-fail '#define MSGD(...)' '#define MSGD printf'
    substituteInPlace listeners/libtimeservice/time_msg.h \
      --replace-fail '#define MSGD(...)' '#define MSGD printf'
  '';

  nativeBuildInputs = [
    cmake
    pkg-config
    mink-idl-compiler
  ];
  buildInputs = [
    qcbor
    qcomtee
    # The RPMB listener uses the UFS BSG UAPI header (scsi/scsi_bsg_ufs.h).
    linuxHeaders
  ];

  cmakeFlags = [
    (lib.cmakeFeature "MINKIDLC_BIN_DIR" "${mink-idl-compiler}/bin")
    (lib.cmakeFeature "QCBOR_DIR_HINT" "${qcbor}")
    (lib.cmakeFeature "QCOMTEE_DIR_HINT" "${qcomtee}")
    (lib.cmakeBool "BUILD_MINKTEEC" false)
    (lib.cmakeBool "BUILD_PKCS11" false)
    (lib.cmakeBool "BUILD_RPMB_CLIENT" false)
    (lib.cmakeBool "BUILD_UNITTEST" false)
  ];

  meta = {
    description = "Qualcomm MinkIPC: QTEE supplicant, listeners and MinkCom adaptor library";
    homepage = "https://github.com/qualcomm/minkipc";
    license = with lib.licenses; [
      bsd3Clear
      bsd3
    ];
    mainProgram = "qtee_supplicant";
    platforms = [ "aarch64-linux" ];
  };
})
