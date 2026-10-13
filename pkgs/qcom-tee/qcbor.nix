# QCBOR CBOR encoder/decoder, required by qcomtee and minkipc's libminkadaptor.
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "qcbor";
  version = "1.6.1";

  src = fetchFromGitHub {
    owner = "laurencelundblade";
    repo = "QCBOR";
    tag = "v${finalAttrs.version}";
    hash = "sha256-tpCW0YjTipdpYwgFVVV0pSb4OH3QoJSbhbb48/WhTFw=";
  };

  nativeBuildInputs = [ cmake ];
  cmakeFlags = [
    (lib.cmakeBool "BUILD_SHARED_LIBS" true)
  ];

  meta = {
    description = "Comprehensive, powerful, commercial-quality CBOR encoder/decoder";
    homepage = "https://github.com/laurencelundblade/QCBOR";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
})
