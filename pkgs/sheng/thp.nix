{
  stdenv,
  fetchFromGitHub,
  pkg-config,
  glib,
  libssc,
}:
stdenv.mkDerivation {
  pname = "xiaomi-sheng-thp";
  version = "0.3.9";
  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "xiaomi-sheng-thp";
    rev = "34046210932d654a4c0df0121ecc31c008f8148c";
    hash = "sha256-+eSthfDjeP4nueqDuR88ZuWsWFs/4yxMH6iSlnujJpA=";
  };
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    glib
    libssc
  ];
  NIX_CFLAGS_COMPILE = "-I${libssc}/include/libssc";
  makeFlags = [ "PREFIX=${placeholder "out"}" ];
  installPhase = ''
    runHook preInstall
    install -Dm755 -s build/xiaomi-sheng-thp $out/libexec/xiaomi-sheng-thp/xiaomi-sheng-thp
    install -Dm644 systemd/xiaomi-sheng-thp.service $out/lib/systemd/system/xiaomi-sheng-thp.service
    runHook postInstall
  '';
}
