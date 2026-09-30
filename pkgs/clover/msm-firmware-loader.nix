{
  fetchFromGitLab,
  lib,
  python3,
  stdenvNoCC,
  runtimeShell,
}:
stdenvNoCC.mkDerivation {
  pname = "msm-firmware-loader-clover";
  version = "1.8.0";

  src = fetchFromGitLab {
    domain = "gitlab.postmarketos.org";
    owner = "postmarketOS";
    repo = "msm-firmware-loader";
    rev = "1.8.0";
    hash = "sha256-OVj/nuwY1vlAgVBnJ6Os9dhbnE1ycUhgfBTqLTanWeA=";
  };

  nativeBuildInputs = [ python3 ];

  postPatch = ''
    # Persist is unusually fragile on this device and is not needed for the
    # first GPU/Bluetooth/Venus tests. Never mount it from the generic scanner.
    sed -i '/^[[:space:]]*persist$/d' msm-firmware-loader.sh
    python3 ${./patch-msm-firmware-loader.py} msm-firmware-loader.sh
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 msm-firmware-loader.sh $out/bin/msm-firmware-loader-clover
    sed -i "1c#!${runtimeShell}" $out/bin/msm-firmware-loader-clover
    runHook postInstall
  '';

  meta = {
    description = "Read-only Qualcomm Android partition firmware loader for Clover";
    homepage = "https://gitlab.postmarketos.org/postmarketOS/msm-firmware-loader";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
