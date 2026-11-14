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
  patches = [ ./umtp-nonroot-mqueue.patch ];
  makeFlags = [ "SYSTEMD=1" ];

  # Exercise the kernel-dependent queue test in the native workstation check.
  # A phone builder may still be running the old kernel without POSIX_MQUEUE.
  doCheck = false;
  checkPhase = ''
    runHook preCheck
    $CC -Iinc -ffunction-sections -fdata-sections -c src/msgqueue.c -o msgqueue-test.o
    $CC -Iinc -Wl,--gc-sections ${../../tests/umtp-mqueue.c} \
      msgqueue-test.o obj/logs_out.o -pthread -lrt -o mqueue-test
    ./mqueue-test 2>mqueue-test.stderr
    test ! -s mqueue-test.stderr
    runHook postCheck
  '';

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
