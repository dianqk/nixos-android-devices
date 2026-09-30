{
  stdenvNoCC,
  lib,
  makeWrapper,
  python3,
  android-tools,
  nix,
  openssh,
  gnutar,
}:
stdenvNoCC.mkDerivation {
  pname = "mobile-device";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 mobile_device.py $out/bin/mobile-device
    install -Dm644 boot_image.py $out/bin/boot_image.py
    install -Dm644 recovery_copy.py $out/bin/recovery_copy.py
    install -Dm644 README.md $out/share/doc/mobile-device/README.md
    install -Dm644 README.zh.md $out/share/doc/mobile-device/README.zh.md
    wrapProgram $out/bin/mobile-device --prefix PATH : ${
      lib.makeBinPath [
        python3
        android-tools
        nix
        openssh
        gnutar
      ]
    }
    runHook postInstall
  '';
  meta = {
    description = "Host CLI for Android fastboot, RAM recovery, and NixOS updates";
    mainProgram = "mobile-device";
    platforms = lib.platforms.linux;
  };
}
