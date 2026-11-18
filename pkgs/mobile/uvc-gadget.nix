{
  lib,
  stdenv,
  fetchzip,
  meson,
  ninja,
  pkg-config,
  libcamera,
  libjpeg,
}:
stdenv.mkDerivation {
  pname = "uvc-gadget";
  version = "0.4.0-unstable-04c18aa";
  src = fetchzip {
    url = "https://chromium.googlesource.com/chromiumos/third_party/uvc-gadget/+archive/04c18aa6c4a7017957e2dfe88c3ff7ef34a1b3a0.tar.gz";
    stripRoot = false;
    hash = "sha256-EaOwfqkQBo1jTvcYQqLGoV+6kaGpc6NEsE0OTsC9HbQ=";
  };
  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];
  buildInputs = [
    libcamera
    libjpeg
  ];
  # This pinned upstream predates GCC 15's additional C++/fortify warnings.
  mesonFlags = [ "-Dwerror=false" ];
  patches = [ ./uvc-source-lifecycle.patch ];
  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  checkPhase = ''
    runHook preCheck
    $CC -I../include/uvcgadget -I../lib ${../../tests/uvc-source.c} \
      -Llib -Wl,-rpath,"$PWD/lib" -luvcgadget -o uvc-source-test
    ./uvc-source-test
    runHook postCheck
  '';
  meta = {
    description = "UVC gadget with libcamera, V4L2 and test-pattern sources";
    homepage = "https://gitlab.freedesktop.org/camera/uvc-gadget";
    license = [
      lib.licenses.lgpl21Plus
      lib.licenses.gpl2Plus
    ];
    platforms = lib.platforms.linux;
    mainProgram = "uvc-gadget";
  };
}
