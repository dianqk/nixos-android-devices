# ---
# Module: DevAuth Sensor
# Description: Devauth sensor configuration
# Scope: Host
# ---

{
  stdenvNoCC,
  runtimeStdenv,
  lib,
  patchelf,
  firmware-source,
}:

# xiaomi_devauth is a precompiled aarch64 binary for Xiaomi sensor/keyboard authentication.
stdenvNoCC.mkDerivation {
  pname = "xiaomi-devauth";
  version = "1.0.0";

  src = "${firmware-source}/bin/xiaomi_devauth";

  nativeBuildInputs = [
    patchelf
  ];

  # No build required — this is a precompiled binary
  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp $src $out/bin/xiaomi_devauth
    chmod +wx $out/bin/xiaomi_devauth

    patchelf \
      --set-interpreter "${runtimeStdenv.cc.bintools.dynamicLinker}" \
      --set-rpath "${
        lib.makeLibraryPath [
          runtimeStdenv.cc.libc
          runtimeStdenv.cc.cc.lib
        ]
      }" \
      $out/bin/xiaomi_devauth

    runHook postInstall
  '';

  meta = with lib; {
    description = "Xiaomi Proprietary Sensor and Keyboard Authentication Daemon";
    platforms = [ "aarch64-linux" ];
    license = licenses.unfree;
  };
}
