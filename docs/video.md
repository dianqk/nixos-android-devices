# Local video playback and encoding

[Configuration](configuration.md) · [中文](video.zh.md)

All device modules default `androidDevices.video.ffmpegPackage` to upstream
`pkgs.ffmpeg`. Use upstream `pkgs.mpv`/`pkgs.celluloid` without replacing libmpv's
FFmpeg dependency. VA-API support belongs in the separately configured driver
and kernel; the default does not imply hardware validation on every device.

## Optional VA-API driver

The device module exposes an opt-in Iris/Venus backend:

```nix
{ pkgs, ... }: {
  androidDevices.video.vaapi.enable = true;
  environment.systemPackages = [ pkgs.ffmpeg pkgs.libva-utils ];
}
```

`androidDevices.video.vaapi.package` can replace the backend. The module enables
graphics and installs the driver without changing FFmpeg, players or global
LIBVA environment variables. It is inactive in RAM recovery. The native AArch64
package is also exported as `libva-v4l2` on both build hosts. See the
[driver guide](../pkgs/libva-v4l2/README.md) for build platforms, hardware checks,
patches, codec limits and optional screen-recording VPP.

## Optional restricted FFmpeg

The retained Qualcomm profile is for direct V4L2 M2M diagnostics, backend
comparisons and local H.264/HEVC applications needing fewer native/cross build
dependencies. It is not selected by device modules. To explicitly select a
patched variant (replace `asphalt` with `polaris` for Venus):

```nix
{ androidPackages, config, ... }:
{
  androidDevices.video.ffmpegPackage = androidPackages.devices.asphalt.ffmpeg;
  environment.systemPackages = [ config.androidDevices.video.ffmpegPackage ];
}
```

This override selects the diagnostic FFmpeg only; it does not rebuild players.
The following functionality and dependency limits apply to this optional package,
not to the upstream defaults.

## Included functionality

- H.264/HEVC V4L2 M2M decoding and encoding; H.264/HEVC VAAPI decode hooks and
  encoders. VAAPI requires a separately installed compatible driver and kernel;
  enabling the API does not establish hardware support on a board.
- Local containers, parsers, bitstream filters and built-in audio/subtitle
  codecs. Native AAC encoding is available for recording audio.
- PNG/JPEG cover art and screenshots, raw frames, software pixel conversion,
  audio resampling and built-in filters. `ffmpeg`, `ffprobe` and the libav
  libraries remain available for players and capture applications.
- File/pipe/fd input and local helper protocols; lavfi for filters and diagnostic
  sources. Screen/audio capture must be supplied by the recorder, for example
  through PipeWire; this profile does not include FFmpeg's ALSA/Pulse inputs.

VAAPI decoding uses the native H.264/HEVC decoder frontends. Those decoders also
retain software fallback; selecting hardware decoding is player/application
policy. Other motion-video codecs and software video-encoder libraries such as
x264/x265 are omitted. See the board hardware notes for qualified formats and
limitations, including Polaris HEVC Main 10.

mpv renders subtitles with its own libass. FFmpeg still demuxes and decodes
embedded text/bitmap subtitles, so those codecs and Matroska compression remain.
FFmpeg's separate libass/font rendering filters are omitted; burning subtitles
with FFmpeg's `subtitles`/`ass` filters is unavailable.

## Dependency boundary

The profile removes ffplay/SDL and their GTK dependency chains, network playback
and TLS libraries, unrelated vendor GPU APIs, OpenCL/CUDA/Vulkan filters,
external video/audio codec libraries and documentation generators. The explicit
library inputs are libdrm, libva-minimal, libc iconv and zlib. libdrm disables
Intel/PCI and Valgrind support. The build platform follows `compilationPkgs`,
supporting native AArch64 and x86_64-to-AArch64 builds.

This boundary applies to FFmpeg. A player's own libass, graphics/audio backends
or GTK frontend still have their own dependencies. The repository-wide default
`pkgs.ffmpeg` is not changed. Direct V4L2 diagnostics that rely on board fixes
must explicitly select the patched variant above.

## Checks

The custom FFmpeg build disables `doCheck` and `doInstallCheck`. The following
smoke test is independent and opt-in; it adds no build dependency.

On a machine able to execute the target architecture, run
`python3 tests/ffmpeg-local-playback.py /path/to/ffmpeg/bin /path/to/test-directory`.
It checks codec/protocol boundaries, local audio/subtitle muxing and decoding,
and PNG screenshots without video hardware. Device checks must additionally
exercise the selected hardware backend; see [Asphalt encoding](asphalt/hardware.md#hardware-video-encoding).
