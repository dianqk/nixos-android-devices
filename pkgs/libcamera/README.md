# Sensor-adapted libcamera runtime

[中文](README.zh.md)

`androidDevices.camera.package` exposes libcamera with the existing mobile
sensor gain/properties patches. It includes the GStreamer libcamera provider and
`libcamerasrc`; consumers can add that package's `lib/gstreamer-1.0` directory
to their own plugin search path. Camera selection belongs to consumers; use
provider identities and standard location properties instead of video-node numbers.

This patched upstream runtime builds natively for the target, like the VA driver,
under both mobile initiating-platform selections. Its upstream GStreamer and
other library identities stay native and reusable from binary caches. Project
applications and kernels still use their selected native/cross compilation paths.
This does not change the system PipeWire or Snapshot library selection.

Build/discovery does not establish capture quality or calibration. Device guides
record the sensor-specific hardware results and remaining limitations.

The GPU software ISP also carries the merged
[GLES matrix fix](https://gitlab.freedesktop.org/camera/libcamera/-/commit/1df5cbe722a839ce4e257093550fa8107c02cf8b)
and experimental backports for
[centered cropping](https://patchwork.libcamera.org/patch/28704/),
[visible-sensor metering](https://patchwork.libcamera.org/patch/28707/) and its
[geometry test](https://patchwork.libcamera.org/patch/28708/).
The latter v5 series is rejected/unmerged upstream; these are local experimental
backports, not an upstream release guarantee. They correct the sensor-coordinate
statistics window when GPU output is cropped or scaled, including matching
360p/720p aspect ratios. The focused geometry check includes packed-Bayer border
cases and runs during the native package build. They do not provide sensor noise,
colour or lens calibration.

A local simple-pipeline fix disables competing media links without trusting the
cached link state. Without it, a camera that another process (for example
`cam`) routed to a shared CAMSS receiver blocks PipeWire from switching to a
different sensor until WirePlumber restarts.
