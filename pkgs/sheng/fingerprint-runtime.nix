{
  stdenvNoCC,
  autoPatchelfHook,
  runtimeStdenv,
  shengFingerprint,
}:
stdenvNoCC.mkDerivation {
  pname = "xiaomi-sheng-fingerprint";
  version = "0.1.4";
  src = shengFingerprint;
  dontBuild = true;
  dontStrip = true;
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ runtimeStdenv.cc.cc.lib ];
  installPhase = ''
    runHook preInstall
    install -Dm0755 prebuilt/aarch64/qteesupplicant $out/libexec/qteesupplicant
    install -Dm0755 prebuilt/aarch64/sfs_config $out/libexec/fpc-sfs-config
    for lib in prebuilt/aarch64/qtee-listeners/*.so.1.0.0; do
      name=$(basename "$lib")
      short=''${name%.0.0}
      install -Dm0644 "$lib" $out/lib/qtee-listeners/$name
      ln -s $name $out/lib/qtee-listeners/$short
    done
    runHook postInstall
  '';
}
