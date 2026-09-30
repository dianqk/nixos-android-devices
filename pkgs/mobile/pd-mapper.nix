{
  stdenv,
  lib,
  fetchFromGitHub,
  qrtr,
}:
stdenv.mkDerivation {
  pname = "pd-mapper";
  version = "unstable-2022-02-08";
  src = fetchFromGitHub {
    owner = "andersson";
    repo = "pd-mapper";
    rev = "9d78fc0c6143c4d1b7198c57be72a6699ce764c4";
    hash = "sha256-vQZZ3WtZGh5OEw0EmlmT/My/cY6VRruuicsFR0YCQOw=";
  };
  buildInputs = [ qrtr ];
  postPatch = ''
    substituteInPlace pd-mapper.c \
      --replace-fail '/lib/firmware/' \
        '/run/current-system/sw/share/uncompressed-firmware/'
  '';
  installFlags = [ "prefix=$(out)" ];
  meta = {
    description = "Qualcomm protection-domain mapper";
    homepage = "https://github.com/andersson/pd-mapper";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.aarch64;
  };
}
