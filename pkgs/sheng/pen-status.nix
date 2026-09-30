{
  fetchFromGitHub,
  lib,
  mkDerivation,
  qmake,
  qtbase,
  qtsvg,
  qtwebsockets,
  qtx11extras,
}:
mkDerivation {
  pname = "xiaomi-pen-status";
  version = "0.2.3";
  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "xiaomi-pen-status";
    rev = "fcf349109d2e69aedf7170479cc38b102ba1d4c0";
    hash = "sha256-UwRYo4nSElw14HRsuNlR7XimSA26RLmsB4iivf9IT6Y=";
  };
  nativeBuildInputs = [ qmake ];
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
