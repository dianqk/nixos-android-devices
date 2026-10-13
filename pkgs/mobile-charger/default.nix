{ stdenv, lib }:
stdenv.mkDerivation {
  pname = "mobile-charger";
  version = "0.1.0";
  src = ./.;
  makeFlags = [ "PREFIX=$(out)" ];
  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  meta = {
    description = "Minimal VT charging display and off-mode power controller";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "mobile-charger";
  };
}
