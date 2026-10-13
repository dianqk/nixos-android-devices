# Qualcomm VA-API backend

Enable the shared module after importing a device module:

```nix
{
  androidDevices.video.vaapi.enable = true;
}
```

The module enables NixOS graphics support and adds the driver to
`hardware.graphics.extraPackages`. It defaults to disabled and has no effect in
RAM recovery. It does not select a desktop, player or FFmpeg variant. To replace
only the backend, set `androidDevices.video.vaapi.package` to your own derivation.
Use stock FFmpeg/mpv; add `pkgs.libva-utils` yourself for `vainfo`.

NixOS exposes `v4l2_drv_video.so` and its `msm_drv_video.so` alias under
`/run/opengl-driver/lib/dri`. Libva discovers it from the MSM DRM device without
a global `LIBVA_DRIVER_NAME` override. Users need DRM/render, video and system
DMA-heap access; the shared mobile module supplies the system-heap udev rule.

The package pins [upstream v1.0.0](https://github.com/radxa-pkg/libva-v4l2/tree/0e4ce1e05da1d0a92b342efc2090b9e4987035e1)
and retains five local patches: system-heap upload coherency, GLES VPP, AV1
reconstruction, Venus decoder discovery and Venus encoding. Patch metadata is
preserved. GPU VPP is enabled; optional proprietary FastCV/CDSP support is off.
Hardware capabilities vary by kernel, firmware and board; installing this backend
or listing profiles is not hardware acceptance. See [Aurora's results and limits](../../docs/aurora/hardware.md#optional-va-api-backend).

## Build and package reuse

```sh
nix build .#libva-v4l2 --out-link result-libva-v4l2
```

The mobile flake output targets native AArch64 on either initiating build host.
This small driver uses native target graphics libraries even when kernels are
cross compiled, preserving their binary-cache identities. An x86_64 initiator
needs an AArch64 builder or configured emulation for uncached native jobs; see
[build requirements](../../docs/configuration.md#build-platforms-and-remote-builders).
The public `lib.mkPackageSet { inherit pkgs; }` also exposes `libva-v4l2`; its
platform follows the supplied `pkgs`, including an explicitly cross package set.

## Runtime checks

On Asphalt, select the DRM render node belonging to MSM. The following examples
assume `/dev/dri/renderD128`; verify it on the device first. The user needs access
to both the DRM render node and the Iris video devices.

With `vainfo` from `libva-utils`, check driver discovery after activating the
Asphalt configuration:

```sh
vainfo --display drm --device /dev/dri/renderD128
```

Before system activation, a copied package can be tested with per-process
`LIBVA_DRIVERS_PATH=<package>/lib/dri` and `LIBVA_DRIVER_NAME=v4l2`. Upstream also
supports `IRIS_VAAPI_DEVICE` and `IRIS_VAAPI_ENCODER_DEVICE` to select the decoder
and encoder video nodes. Do not assume their numeric indices are stable.

For an 8-bit H.264 or HEVC input, explicitly require VA-API surfaces and download
them for a pixel comparison. Run from a work directory with a short `input.mkv`:

```sh
timeout --signal=INT --kill-after=5s 40s \
  env IRIS_VAAPI_DEBUG=1 ffmpeg -hide_banner -nostdin -n -xerror \
  -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 \
  -hwaccel_output_format vaapi -i input.mkv -map 0:v:0 -an \
  -vf hwdownload,format=nv12 -fps_mode passthrough -f framemd5 vaapi.md5

ffmpeg -hide_banner -nostdin -n -xerror -hwaccel none -i input.mkv \
  -map 0:v:0 -an -vf format=nv12 -fps_mode passthrough \
  -f framemd5 software.md5
```

Compare the complete frame count and per-frame hashes, and check the decoder
logs and new kernel messages. The software run is an independent reference;
it is not a VA-API implementation. Requiring `hwdownload` rejects a silent
fallback to software frames. `h264_v4l2m2m`/`hevc_v4l2m2m` bypass the VA backend
and do not validate this path. Use `p010le` for a supported Main10 input.

A separate HEVC encoding probe using generated frames:

```sh
mkdir -p tmp
timeout --signal=INT --kill-after=5s 30s \
  ffmpeg -hide_banner -nostdin -n \
  -vaapi_device /dev/dri/renderD128 \
  -f lavfi -i testsrc2=size=1280x720:rate=30 -frames:v 90 -an \
  -vf format=nv12,hwupload -c:v hevc_vaapi -profile:v main \
  -bf 0 -g 60 -rc_mode CBR -b:v 4M -async_depth 4 tmp/iris-hevc.mp4

ffprobe -v error -select_streams v:0 -count_frames \
  -show_entries stream=codec_name,width,height,nb_read_frames tmp/iris-hevc.mp4
ffmpeg -v error -hwaccel none -i tmp/iris-hevc.mp4 -f null -
```

Verify all 90 frames decode and inspect the kernel log for new Iris/IOMMU errors.
Repeat with `h264_vaapi -profile:v high` and a separate output file for H.264.
Driver enumeration alone does not prove encoding, decoding or screen capture.

## Support matrix

"Verified" means pixel-exact comparison against software decoding with stock
FFmpeg (VA surfaces forced and downloaded as above) and playback in stock mpv
with software fallback disabled. A few display drops during mpv startup are
expected; decoder drops are not.

| Device | Decode (VA-API) | Encode (VA-API) | Not supported or not verified |
| --- | --- | --- | --- |
| Asphalt (Iris, SM8450) | H.264 High, HEVC Main and Main10, VP9 Profile 0 (8-bit) and Profile 2 (10-bit), including B-frame reorder and VP9 alt-ref, at 720p/1080p | H.264 High and Constrained Baseline, HEVC Main 8-bit; CQP, CBR and VBR; [screen recording](#basic-screen-recording) | AV1 and VP8 decode; VP9/AV1 encode; 10-bit encode; nonstandard encode widths (see [limitations](#limitations-and-kernel-requirements)) |
| Polaris (Venus, SDM845) | H.264 High, HEVC Main and Main10 at 720p/1080p | H.264 High, HEVC Main 8-bit; CQP and CBR at 720p/1080p, real-time 1080p30 | 10-bit encode (rejected); screen recording/VPP; arbitrary sizes; long-term CBR bitrate conformance |
| Sheng (Iris, SM8550) | AV1 Main 8/10-bit 4:2:0 at 720p/1080p, plus H.264, HEVC and VP9 | Not covered here | AV1 features listed under [AV1 Main](#av1-main-decoding); 4K, high frame rates and long-duration thermal behavior |
| Aurora (Iris, SM8650) | See [Aurora's results and limits](../../docs/aurora/hardware.md#optional-va-api-backend) | | |

For strict VA-API playback checks, use
`mpv --hwdec=vaapi --hwdec-software-fallback=no input.mkv` and inspect
`hwdec-current`. Automatic selection alone is not evidence of hardware decoding.
Player defaults remain consumer policy.

## Implementation notes

### Venus decoding and encoding (Polaris)

The local `0004-discover-venus-decoders.patch` extends decoder discovery to
`qcom-venus`, retaining M2M and compressed OUTPUT-format checks. It does not
select camera/encoder nodes by their numeric indices. The kernel already
provides the required Venus decode-order controls.

The companion `0005-support-venus-encoding.patch` adapts Venus control handling,
requests sufficiently large coded buffers and restores the visible crop after
final format negotiation. Firmware rejects coded buffers below 942080 bytes for
720p, more than the kernel's default allocation, so the VA backend requests at
least one byte per aligned luma pixel through `sizeimage`, preserving any larger
driver minimum. FFmpeg/mpv and the kernel are unmodified.

### AV1 Main decoding

The local `0003-add-av1-main-decoding.patch` adds AV1 Main Profile 8/10-bit
4:2:0 decoding, advertised only when Iris enumerates the AV1 input format.
It negotiates NV12/P010 within the same VA profile and reconstructs AV1 OBUs
from VA picture/tile parameters. FFmpeg and mpv remain stock nixpkgs packages;
no additional runtime dependency or kernel change is required by this patch.

The VA API omits AV1's reference refresh flags. The adapter initially decodes
without refreshing the eight-slot reference map, then infers the exact refresh
from the next VA picture. Referenced pictures are decoded again into an internal
discard surface before dependent pictures. This preserves reference, entropy
and motion state, but adds decoding work (about 1.5 submissions per display
frame on typical streams). 1080p30 Main10 plays in real time on Sheng.

The backend itself does not synthesize film grain. Grain-bearing AV1 still plays
in stock mpv because mpv exports grain metadata and `gpu-next` applies it on the
GPU; that output is not pixel-verified. Super-resolution, intra-block copy,
hidden keyframes, switch frames, large-scale tiles, dynamic dimensions and
non-Main/4:2:0 formats are explicitly rejected. Automatic player fallback is not
verified for every unsupported boundary.

### Hardware-independent AV1 reconstruction checks

`nix build .#libva-v4l2` runs the pure header/reference-state tests on a native
build platform. The scripts in `tests/` additionally exercise stock FFmpeg's VA
parameter submission and compare the reconstructed stream against libdav1d.
Their test-only decoder records compressed packets and emits blank placeholders
solely to observe display order. **Never install this test driver**; it does not
decode video or validate hardware. A DRM render node is needed for libva display
initialization, but no V4L2 video device is opened.

Prepare a patched source and build the test serializer from the repository root:

```sh
nix develop .#libva-v4l2 --command bash -c '
  set -e
  mkdir -p tmp
  test ! -e tmp/av1-roundtrip-source
  cp -R "$src" tmp/av1-roundtrip-source
  chmod -R u+w tmp/av1-roundtrip-source
  for patch_file in $patches; do
    patch -d tmp/av1-roundtrip-source -p1 < "$patch_file"
  done
  python3 pkgs/libva-v4l2/tests/make-av1-serializer.py \
    --source tmp/av1-roundtrip-source --work-dir tmp/av1-roundtrip/test
'

python3 pkgs/libva-v4l2/tests/av1-roundtrip.py \
  --driver tmp/av1-roundtrip/test/harness-build \
  --output tmp/av1-roundtrip/results \
  path/to/av1-8bit.mkv path/to/av1-10bit.mkv
```

Supply `--render-node` if needed. The verifier ignores audio, checks command
exit status, full display-frame counts and every frame hash, and exits nonzero
on any mismatch. Its JSON result distinguishes display frames from extra
reference-refresh submissions.

### Upload coherency

The local `0001-use-system-heap-for-upload-surfaces.patch` replaces MSM
cached-coherent GEM allocations for unbacked/uploaded surfaces with system
DMA heap allocations. MSM GPU coherency does not guarantee visibility of CPU
writes to Iris, and the kernel's MSM PRIME exporter lacks CPU-access callbacks;
the system heap synchronizes mapped device attachments through the existing
VA image map/unmap `DMA_BUF_IOCTL_SYNC` calls. Without it, encoder input can be
intermittently corrupt even when the output looks decodable; a whole-stream
average SSIM can hide this. FFmpeg is unmodified.

The upload allocation requires `/dev/dma_heap/system`. Asphalt exposes it as
`root:video` mode `0660`; the desktop user needs that access as well as DRM and
Iris access. The allocation retains its layout and fd lifetime, and encoding
still imports it directly: no software encoding or CPU staging copy is used.
Screen capture and VA VPP require the separate GPU extension described below;
codec support alone does not establish recording support.

## Basic screen recording

Recording on Asphalt uses unmodified upstream `wl-screenrec` (linked to its own
stock FFmpeg). The local
`0002-add-gles-screen-recording-vpp.patch` supplies the missing VPP path:
Niri writes an exported linear RGB DMA-BUF, Adreno converts/scales it to NV12,
and a second GPU pass applies any static screen rotation before Iris VA-API
encoding. VPP matrix/range metadata reaches Iris so encoded VUI agrees with
the conversion and container tags. No full-frame CPU download/conversion is used. Synchronization,
command submission, compositor capture and muxing still consume CPU.
The GPU path requires GLES 3.2, renderable DMA-BUF imports and the system DMA
heap; software EGL renderers are rejected.

Start recording **after** setting and locking the desired screen orientation.
Keep it fixed until recording stops. On a 270-degree landscape screen
(2560x1600), record the whole display at half resolution without stretching:

```sh
wl-screenrec --output DSI-1 --codec hevc --low-power off \
  --encode-pixfmt nv12 --encode-resolution 1280x800 --max-fps 30 --no-damage \
  --ffmpeg-encoder-options 'bf=0,rc_mode=CQP,qp=18,colorspace=bt709,color_primaries=bt709,color_trc=bt709,color_range=tv' \
  --filename recording.mp4
```

Stop with Ctrl-C to finalize the MP4. Use `--codec avc` for H.264 (the CLI name
is `avc`, not `h264`). For native/180-degree portrait orientation, use HEVC size
`1280x2048`; changing the encode size does not preserve the aspect ratio
automatically. Arbitrary widths and full native resolution are not supported.
Specify the codec/pixel format instead of relying on automatic defaults.
Do not pass `--no-hw`. The preset uses `--no-damage` to retain idle screen time;
without it the recorder can shorten a final unchanged interval. Continuous
capture runs at approximately 30 fps; an exact constant frame rate is not
guaranteed.

Use MP4: with this recorder and its FFmpeg, direct MKV output fails before
recording because the VA encoder cannot provide the required global header at
muxer startup. Record to MP4 and remux later if needed. Audio capture and
dynamic orientation changes are not supported by this preset.

## Limitations and kernel requirements

- Nonstandard encoding widths remain unverified/unsupported on this kernel and
  firmware: widths such as 642, 644, 648, 656, 672 and 704 fail with Iris
  session error `0x1000005` and no usable output, and padding the raw input
  does not help. Use the verified
  640x480, 1280x720, 1920x1080, or the recording sizes documented above.
- FastCV/CDSP is disabled. The local GLES VPP path supports SDR 8-bit RGB
  conversion/scaling and static NV12 rotation, not general-purpose VA video
  processing. NV12 rotation cannot resize or change color range/matrix. RGB
  PRIME import and CPU image mapping are not implemented; the recorder uses
  allocated/exported linear RGB surfaces. Mirroring, HDR, Main10 recording,
  audio and rotation changes during recording are not supported.
- The upstream encoder supports HEVC Main 8-bit, not Main10 or B frames.
  On older Iris kernels it accepts the default deblocking settings, but rejects
  non-default requests without the loop-filter controls. The package does not
  install upstream's optional deblocking kernel patch.
- VA decoding requires Iris decode-order controls and adequate capture buffer
  pools. Asphalt's kernel patch series includes libva-v4l2's companion patches
  as 0027/0028. Without them, H.264/HEVC VA context creation fails at
  `S_CTRL DISPLAY_DELAY` even though `vainfo` lists the profiles.
  Driver discovery alone is not decoding acceptance.
- Firmware and the existing Asphalt kernel encoding fixes are still required.
  This backend has its own V4L2 implementation; it does not use FFmpeg's repaired
  `hevc_v4l2m2m` wrapper, and results for that wrapper do not apply to it.

See the pinned upstream [requirements and tests](https://github.com/radxa-pkg/libva-v4l2/tree/0e4ce1e05da1d0a92b342efc2090b9e4987035e1/tests).
