{ lib, stdenv, firmware-source }:
stdenv.mkDerivation {
  pname = "aurora-touch";
  version = "0.1.0";
  src = ./.;
  strictDeps = true;
  # The Android ELF is mapped by the adapter, never linked or patched by Nix.
  dontPatchELF = true;
  dontStrip = true;
  buildPhase = ''
    runHook preBuild
    $CC -O2 -Wall -Wextra -Werror stock-core.c sha256.c -lm -o aurora-touch
    runHook postBuild
  '';
  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  checkPhase = ''
    runHook preCheck
    $CC -O2 -Wall -Wextra -Werror test.c sha256.c -lm -o test-touch
    ./test-touch
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 aurora-touch $out/bin/aurora-touch
    (cd ${firmware-source}/android14/touch && sha256sum -c SHA256SUMS)
    install -Dm644 ${firmware-source}/android14/touch/libtouchreport.so $out/share/aurora-touch/libtouchreport.so
    install -Dm644 ${firmware-source}/android14/touch/aurora_syna_thp_config.ini $out/share/aurora-touch/aurora_syna_thp_config.ini
    install -Dm644 README.md $out/share/doc/aurora-touch/README.md
    install -Dm644 ORIGINS.md $out/share/doc/aurora-touch/ORIGINS.md
    install -Dm644 COPYING $out/share/doc/aurora-touch/COPYING
    runHook postInstall
  '';
  meta = {
    description = "Xiaomi 14 Ultra Android 14 touch host processor adapter";
    license = with lib.licenses; [
      mit
      isc
      unfree
    ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    platforms = [ "aarch64-linux" ];
    mainProgram = "aurora-touch";
  };
}
