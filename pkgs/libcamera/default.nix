# Mobile sensor gain and properties for the simple software ISP pipeline.
{ libcamera }:
libcamera.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ./imx363.patch
    ./asphalt.patch
    ./sheng.patch
  ];
})
