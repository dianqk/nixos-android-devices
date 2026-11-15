{
  fetchFromGitHub,
  lib,
  mkDerivation,
  qmake,
  qtbase,
  qtsvg,
  qtwebsockets,
  qtx11extras,
  buildQtbase ? null,
  wrapQtAppsHook ? null,
}:
mkDerivation (
  {
    pname = "xiaomi-pen-status";
    version = "0.2.3";
    src = fetchFromGitHub {
      owner = "ianchb";
      repo = "xiaomi-pen-status";
      rev = "fcf349109d2e69aedf7170479cc38b102ba1d4c0";
      hash = "sha256-UwRYo4nSElw14HRsuNlR7XimSA26RLmsB4iivf9IT6Y=";
    };
    nativeBuildInputs = if buildQtbase == null then [ qmake ] else [ wrapQtAppsHook ];
    buildInputs = [
      qtbase
      qtsvg
      qtwebsockets
      qtx11extras
    ];
    installPhase = ''
      runHook preInstall
      install -Dm755 xiaomi-pen-status $out/bin/xiaomi-pen-status
      install -Dm644 xiaomi-pen-status.desktop $out/share/applications/xiaomi-pen-status.desktop
      install -Dm644 xiaomi-pen-status.svg $out/share/icons/hicolor/scalable/apps/xiaomi-pen-status.svg
      runHook postInstall
    '';
    meta = with lib; {
      description = "Pen Status tray utility for Xiaomi Pad 6S Pro 12.4";
      license = licenses.mit;
      platforms = platforms.aarch64;
    };
  }
  // lib.optionalAttrs (buildQtbase != null) {
    # Run qmake/moc/rcc on the initiating host, but read the cached target Qt
    # module metadata and link the target libraries with the cross compiler.
    configurePhase = ''
      runHook preConfigure
      # Nixpkgs' qtPrepareTool searches PATH for moc/rcc/uic; target Qt's
      # setup hook also puts its ARM tools there. Prefer build executables.
      export PATH=${buildQtbase.dev}/bin:$PATH
      cat > qt-cross.conf <<EOF
      [Paths]
      Prefix=${qtbase}
      Headers=${qtbase.dev}/include
      Libraries=${qtbase.out}/lib
      ArchData=${qtbase.dev}
      Data=${qtbase.dev}
      HostData=${qtbase.dev}
      HostBinaries=${buildQtbase.dev}/bin
      EOF
      ${buildQtbase.dev}/bin/qmake -qtconf "$PWD/qt-cross.conf" \
        -spec linux-g++ CONFIG+=release CONFIG+=nostrip -early \
        QMAKE_CC="$CC" QMAKE_CXX="$CXX" QMAKE_LINK="$CXX" \
        QMAKE_AR="$AR cqs" QMAKE_STRIP="$STRIP"
      runHook postConfigure
    '';
  }
)
