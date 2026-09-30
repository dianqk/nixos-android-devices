# ---
# Module: QRTR Sensor
# Description: QRTR routing configuration
# Scope: Host
# ---

{
  lib,
  stdenv,
  fetchurl,
  meson,
  ninja,
  pkg-config,
}:

stdenv.mkDerivation rec {
  pname = "qrtr";
  version = "1.2";

  src = fetchurl {
    url = "https://github.com/linux-msm/qrtr/archive/27d2c9dfb4e8653ac314ebe2b7980fed2f4bac2e.tar.gz";
    hash = "sha256-MVZB7ACwEBALHl2R6sHHYQXol4+4pywkKNd5GT5cYpA=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];

  meta = with lib; {
    description = "Qualcomm IPC Router utility libraries";
    license = licenses.bsd3;
    platforms = platforms.linux;
  };
}
