{
  lib,
  alsa-ucm-conf,
  fetchFromGitHub,
}:
alsa-ucm-conf.overrideAttrs (old: {
  version = "sheng-2026-07-20";
  src = fetchFromGitHub {
    owner = "map220v";
    repo = "alsa-ucm-conf";
    rev = "d28a4484c81088c8ea51d44fb1535cef40f4a475";
    hash = "sha256-/wBABGCEgttKAR9fYHKXFOq+IjulH5tNumMveN722Co=";
  };
  patches = lib.unique ((old.patches or [ ]) ++ [ ./patches/sheng-alsa-ucm-debian-routing.patch ]);
})
