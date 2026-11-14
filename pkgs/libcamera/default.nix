# Mobile sensor gain and properties for the simple software ISP pipeline.
{ libcamera }:
libcamera.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ./imx363.patch
    ./asphalt.patch
    ./sheng.patch
    ./unicorn.patch
    ./aurora.patch
    ./marble.patch
    ./0001-libcamera-software_isp-debayer_egl-Use-untransposed-.patch
    ./0002-libcamera-software_isp-Centre-the-crop-the-GPU-debay.patch
    ./0003-software-isp-Align-statistics-with-the-visible-senso.patch
    ./0004-tests-Validate-the-visible-sensor-crop.patch
    ./0005-tests-cover-Sheng-packed-Bayer-crop-at-360p-and-720p.patch
    ./0006-pipeline-simple-Do-not-trust-cached-link-flags.patch
  ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    meson test --no-rebuild --print-errorlogs debayer-geometry
    runHook postCheck
  '';
})
