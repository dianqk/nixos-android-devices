{
  fetchFromGitHub,
  lib,
  stdenv,
  systemd,
}:

stdenv.mkDerivation {
  pname = "umtp-responder";
  version = "0-unstable-2026-06-05";

  src = fetchFromGitHub {
    owner = "viveris";
    repo = "uMTP-Responder";
    rev = "153f76d65608c184a972ad7d0b4ae605e56c0972";
    hash = "sha256-ccpS7ZrZ7GsajnBlurXlDUNYFJY879GjPI/jssjmcqw=";
  };

  buildInputs = [ systemd ];
  makeFlags = [ "SYSTEMD=1" ];

  # Keep resolved children within the storage directory. Upstream's prefix-only
  # check also accepted siblings such as /share-private for a /share root.
  postPatch = ''
    substituteInPlace src/fs_handles_db.c \
      --replace-fail \
        'if( strncmp(root_path, retpath, root_path_len ) )' \
        "if( strncmp(root_path, retpath, root_path_len ) || (root_path_len > 1 && retpath[root_path_len] != '\\0' && retpath[root_path_len] != '/') )"
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 umtprd "$out/bin/umtprd"
    runHook postInstall
  '';

  meta = {
    description = "Lightweight USB Media Transfer Protocol responder";
    homepage = "https://github.com/viveris/uMTP-Responder";
    license = lib.licenses.gpl3Only;
    mainProgram = "umtprd";
    platforms = lib.platforms.linux;
  };
}
