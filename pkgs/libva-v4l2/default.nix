{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  libva,
  libdrm,
  libglvnd,
  libgbm,
}:

stdenv.mkDerivation {
  pname = "libva-v4l2";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "radxa-pkg";
    repo = "libva-v4l2";
    rev = "0e4ce1e05da1d0a92b342efc2090b9e4987035e1";
    hash = "sha256-teSvDsbyUYDgeAYuUAFWqbLDtBVOypR1mDZssMr0Igw=";
  };

  patches = [
    ./0001-use-system-heap-for-upload-surfaces.patch
    ./0002-add-gles-screen-recording-vpp.patch
    ./0003-add-av1-main-decoding.patch
    ./0004-discover-venus-decoders.patch
    ./0005-support-venus-encoding.patch
  ];

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];
  buildInputs = [
    libva
    libdrm
    libglvnd
    libgbm
  ];

  # Encoding does not require the optional proprietary CDSP scaling libraries.
  mesonFlags = [
    (lib.mesonEnable "fastcv" false)
    (lib.mesonBool "gpu-vpp" true)
  ];

  # Header/state tests are independent of Iris hardware.
  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;

  # Full codec/playback acceptance still needs a live Qualcomm Iris/MSM device.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -f "$out/lib/dri/v4l2_drv_video.so"
    test "$(readlink "$out/lib/dri/msm_drv_video.so")" = v4l2_drv_video.so
    runHook postInstallCheck
  '';

  meta = {
    description = "Experimental VA-API backend for Qualcomm Iris/Venus stateful V4L2 codecs";
    homepage = "https://github.com/radxa-pkg/libva-v4l2";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
