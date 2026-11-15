{
  alsa-ucm-conf,
  fetchFromGitHub,
  fetchurl,
}:
alsa-ucm-conf.overrideAttrs (old: {
  version = "sheng-2026-10-23";
  src = fetchFromGitHub {
    owner = "map220v";
    repo = "alsa-ucm-conf";
    rev = "d28a4484c81088c8ea51d44fb1535cef40f4a475";
    hash = "sha256-/wBABGCEgttKAR9fYHKXFOq+IjulH5tNumMveN722Co=";
  };
  # Keep map220v's complete configurations from the community Sheng adaptation.
  # https://github.com/ianchb/debian-sheng/tree/da1d2761dbc1ccaea0122f8b0c2dce2d52edaeb2/alsa-xiaomi-sheng
  patches = old.patches or [ ];
  postPatch = (old.postPatch or "") + ''
    cp ${fetchurl {
      url = "https://raw.githubusercontent.com/ianchb/debian-sheng/da1d2761dbc1ccaea0122f8b0c2dce2d52edaeb2/alsa-xiaomi-sheng/usr/share/alsa/ucm2/Xiaomi/sheng/HiFi.conf";
      hash = "sha256-j55P9r5QEmBiK7Ecg3ykshcQEOw+Ua6YkvWnGGzl3YE=";
    }} ucm2/Xiaomi/sheng/HiFi.conf
    cp ${fetchurl {
      url = "https://raw.githubusercontent.com/ianchb/debian-sheng/da1d2761dbc1ccaea0122f8b0c2dce2d52edaeb2/alsa-xiaomi-sheng/usr/share/alsa/ucm2/Xiaomi/sheng/Xiaomi-Pad6SPro.conf";
      hash = "sha256-bW8FgNsM7ORJbCuEs/wZDmFYrZmIIVOT3GpUFsdvegg=";
    }} ucm2/Xiaomi/sheng/Xiaomi-Pad6SPro.conf
  '';
  postInstall = (old.postInstall or "") + ''
    ln -s ../../Xiaomi/sheng/Xiaomi-Pad6SPro.conf \
      "$out/share/alsa/ucm2/conf.d/sm8550/xiaomi-XiaomiPad6SPro12.4.conf"
  '';
})
