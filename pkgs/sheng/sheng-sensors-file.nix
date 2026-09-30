# ---
# Module: Sensors File
# Description: Sensors file definition
# Scope: Host
# ---

{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

stdenvNoCC.mkDerivation rec {
  pname = "sheng-sensors-file";
  version = "0-unstable-2026-02-07";

  src = fetchFromGitHub {
    owner = "alghiffaryfa19";
    repo = "sheng-sensors-file";
    rev = "199754bb37ae6d4706bd8d4b23e9e6fec2d959cc";
    hash = "sha256-yXX8QUxQ45yS0zCkpXQneiOhinOVCZrjNJVc824dHqQ=";
  };

  installPhase = ''
    mkdir -p $out
    cp -a usr/* $out/
  '';

  meta = with lib; {
    description = "Sensor configuration files for Xiaomi Pad 6S Pro (sheng)";
    # Upstream currently publishes no license. Do not imply permission that
    # the upstream author has not granted.
    license = licenses.unfree;
    platforms = platforms.linux;
  };
}
