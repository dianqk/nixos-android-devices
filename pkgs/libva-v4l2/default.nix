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
  vulkan-loader,
  glslang,
  t880 ? false,
}:

stdenv.mkDerivation {
  pname = "libva-v4l2";
  version = "1.1.1";

  src = fetchFromGitHub {
    owner = "radxa-pkg";
    repo = "qcom-va-driver";
    rev = "0980a1decf26d34c9aa71cd0a4a0d25703a7a17f";
    hash = "sha256-jBqsPU/xReoQLyI01N83w848nNj+87w0ol5ESNUwI9E=";
  };

  patches =
    if t880 then
      [
        ./0001-use-system-heap-for-upload-surfaces.patch
        ./0004-discover-venus-decoders.patch
        ./0005-support-venus-encoding.patch
        ./0006-t880-cpu-decoder.patch
        ./0007-t880-cpu-encoder.patch
        ./0008-t880-av1-implicit-frame-size.patch
        ./0009-t880-hevc-encode-bounds.patch
        ./0010-t880-av1-asynchronous-display.patch
        ./0011-t880-panthor-presentation-surfaces.patch
        ./0012-t880-gpu-tiled-decoder.patch
        ./0013-t880-av1-continuous-anchors.patch
        ./0014-t880-vp9-asynchronous-display.patch
        ./0015-t880-h26x-decode-order-output.patch
        ./0016-t880-remove-prefix-replay.patch
      ]
    else
      [
        ./0001-use-system-heap-for-upload-surfaces.patch
        ./0004-discover-venus-decoders.patch
        ./0005-support-venus-encoding.patch
        ./0002-add-gles-screen-recording-vpp.patch
      ];

  nativeBuildInputs =
    if t880 then
      [
        meson
        ninja
        pkg-config
      ]
    else
      [
        meson
        ninja
        pkg-config
        (lib.getBin glslang)
      ];
  buildInputs =
    if t880 then
      [
        libva
        libdrm
        libglvnd
        libgbm
      ]
    else
      [
        libva
        libdrm
        libglvnd
        libgbm
        vulkan-loader
      ];

  # Encoding does not require the optional proprietary CDSP scaling libraries.
  mesonFlags = [
    (lib.mesonEnable "gpu_copy" (!t880))
    (lib.mesonEnable "cdsp_vpp" false)
    (lib.mesonEnable "vulkan_vpp" (!t880))
  ];

  # Allocation, CAPTURE-budget and RGB parameter tests do not require Iris hardware.
  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;

  # Full codec/playback acceptance still needs a live Qualcomm Iris/MSM device.
  doInstallCheck = true;
  installCheckPhase =
    if t880 then
      ''
        runHook preInstallCheck
        test -f "$out/lib/dri/qcom_drv_video.so"
        test "$(readlink "$out/lib/dri/panthor_drv_video.so")" = qcom_drv_video.so
        runHook postInstallCheck
      ''
    else
      ''
        runHook preInstallCheck
        test -f "$out/lib/dri/qcom_drv_video.so"
        test "$(readlink "$out/lib/dri/v4l2_drv_video.so")" = qcom_drv_video.so
        test "$(readlink "$out/lib/dri/msm_drv_video.so")" = qcom_drv_video.so
        runHook postInstallCheck
      '';

  meta = {
    description = "Experimental VA-API backend for Qualcomm Iris/Venus stateful V4L2 codecs";
    homepage = "https://github.com/radxa-pkg/qcom-va-driver";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
