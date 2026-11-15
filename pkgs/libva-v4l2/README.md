# V4L2 VA-API backend

[中文](README.zh.md)

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

NixOS exposes `qcom_drv_video.so` and its `msm_drv_video.so` / legacy
`v4l2_drv_video.so` aliases under
`/run/opengl-driver/lib/dri`. Libva discovers it from the MSM DRM device without
a global `LIBVA_DRIVER_NAME` override. Users need DRM/render, video and system
DMA-heap access; the shared mobile module supplies the system-heap udev rule.

The package pins [qcom-va-driver 1.1.1](https://github.com/radxa-pkg/qcom-va-driver/tree/0980a1decf26d34c9aa71cd0a4a0d25703a7a17f).
Local extensions preserve system-heap CPU-upload coherency, fixed-orientation
GLES RGB-to-NV12 recording and Venus decoder/encoder compatibility. Upstream now
supplies AV1 reconstruction, YUV Vulkan VPP, capture-memory budgeting and hardware
test programs. GPU surface copying and Vulkan VPP are enabled; optional
proprietary CDSP VPP remains disabled. Existing RGB-base conversion keeps its GLES
path, while YUV/HDR/overlay operations use upstream Vulkan. Hardware capabilities
vary by kernel, firmware and board; installing the backend or listing profiles
is not working hardware decoding. See [Aurora's prior results and limits](../../docs/aurora/hardware.md#optional-va-api-backend).

The optional VA module sets `GST_VA_ALL_DRIVERS=1` for GStreamer discovery in the
session and user manager. No global libva driver name or path is forced. Services
started under an already-running user manager should set that variable explicitly
on their unit as well. Standard NixOS driver discovery uses the MSM alias.

## MediaTek T880 backend

Import the public T880 module and enable VA-API:

```nix
modules = [
  androidDevices.nixosModules.t880
  { androidDevices.video.vaapi.enable = true; }
];
```

The T880 backend recognizes `mtk-vcp-dec`, uses the Panthor render-node discovery
alias and requires GLES 3 for tiled-frame conversion. It exposes
progressive 8-bit H264 Constrained Baseline/Main/High, HEVC Main, VP9
profile 0 and AV1 Main decode with NV12 surfaces, CPU upload/download and
stable DMA-BUF exports. Experimental
H264 Main CAVLC and HEVC Main encoding use one reference, no B frames and a
finite GOP. H264 encoding supports up to 4096 pixels per axis and
4096x2176 pixels per frame; HEVC encoding supports 1920 pixels per axis and
1920x1080 pixels per frame (including 1080x1920 portrait). Encode widths start
at 160 pixels; heights start at 128. Larger HEVC frames are rejected before
hardware submission because they can trigger a firmware SMI timeout. 10-bit
and video processing are not exposed by this backend. Decode
bounds are 128–4096 pixels wide and 128–2176 high, with even dimensions.

Normal VA-API decode uses shared tiled DMA-BUF storage and one GPU pass to
produce stable linear NV12 surfaces, without CPU detiling or a CPU pixel copy.
The linear Panthor presentation allocation remains necessary for consumers
which import ordinary 2D textures, including Firefox. Read-only exports before
the first decode retain that same storage identity. Explicit upload/download
and image-map APIs still use CPU access with DMA-BUF synchronization and
reservation-fence waits; separately requested linear V4L2 output still uses
kernel CPU detiling.

Panthor allocations support sandboxed decoders which permit DRM/DMA-BUF access
without granting access to DMA-heap devices.
New upload and writable-export allocations continue to use the system DMA heap;
presentation buffers are independent storage, never borrowed firmware surfaces.

Decode synchronization consumes hardware completions without flushing live
references. H264/HEVC parameter sets request decode-order output while
preserving reference/DPB capacity; VA clients retain presentation ordering.
The kernel schedules output delivery even after the last compressed input
has returned. Independent keys preserve the active CAPTURE pool. Compressed
GOP prefixes are neither retained nor replayed; outstanding ownership is
bounded to 4096 pictures and each access unit to 4 MiB. Explicit EOS drains
normally, and restarting requires a fresh independent key with cached codec
parameters. Dynamic resolution changes require a new VA context; operations
have a 30-second deadline.

Stock FFmpeg VA-API download produced exact visible 1920x1080 pixels for bounded
16-frame H264 and HEVC streams, including B references and coded 1088-row storage.
A 48-frame VP9 alternate-reference stream also matches exactly; all 52 coded
pictures, including hidden references, complete in per-picture sync tests.
AV1 matches software output for a 48-frame alternate-reference sample, 90 frames
at 720p and 300 frames at 1080p, including GOP30 and GOP120 streams. Per-picture
synchronization also matches every frame. AV1 requires sequence-sized pictures; switch frames and in-context size
changes are rejected before submission. The kernel retains one immutable input
across firmware-requested output-buffer continuations, bounded by 32 attempts
and the original input deadline.
Forward/backward seeks, tail drain, EOF restart and stable exported/re-imported
surfaces match software pixels and timestamps. Eight-frame samples of all four
decoders also match at 4096x2176. These bounded results do not establish sustained
throughput.

### Encoding constraints

The encoder copies NV12 input into CPU-owned V4L2 MMAP buffers; the VPU performs
encoding. This uses memory bandwidth and is not a zero-copy path. Original input
DMA-BUF fences and cache synchronization remain active. Reconstruction surfaces
are logical reference identities; reading back or exporting their pixels is
unsupported. Ordinary input and decoded-surface exports remain available.

Stock FFmpeg can negotiate AVBR with a single target
bitrate, AVBR accuracy parameter 100 and 30-frame convergence/GOP 30. The accuracy
field specifies permitted rate error. Other buffering, peak,
QP-range and CQP requests are rejected. VBR with an explicit no-HRD caller is
also available for diagnostics. HRD buffering is not implemented or verified;
this does not establish that the SoC cannot support it. 360-frame moving-pattern tests at 512 kbit/s, 1 Mbit/s and 2 Mbit/s show
rate and quality response in both codecs. They do not establish a VBV guarantee
or a hard bitrate ceiling.

For an NV12 raw input at 160x128/30fps, the bounded transport configuration is:

```sh
ffmpeg -vaapi_device /dev/dri/renderD128 -f rawvideo -pixel_format nv12 \
  -video_size 160x128 -framerate 30 -i input.nv12 -vf hwupload -an \
  -c:v h264_vaapi -profile:v main -level:v 3 -coder cavlc -bf 0 -refs 1 \
  -g 30 -slices 1 -rc_mode AVBR -b:v 256000 -qmin -1 -qmax -1 \
  -frames:v 4 output.h264
```

For HEVC use `hevc_vaapi`, omit `-coder cavlc` and choose an HEVC output file.
Both codecs also produce software-decodable 1080p MP4 with default asynchronous
depth and forced IDRs; H264 has bounded landscape/portrait upper-size coverage.
Use the explicit AVBR/GOP/QP options above: the stock default VBR/HRD request
is unsupported. HEVC firmware still issues an unmatched FREE during
teardown; the kernel rejects and logs it, then independently quiesces hardware.
Successful output does not hide that closing protocol error.

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

Activate the selected NixOS graphics package before runtime checks, then use
standard libva discovery. Do not force a global driver name or search path.
Upstream supports `IRIS_VAAPI_DEVICE` and `IRIS_VAAPI_ENCODER_DEVICE` for choosing
video nodes when diagnosing discovery; their indices can change between boots.

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
The backend supplies no packed headers, so FFmpeg has no global header for
the stream: write MP4 (or a raw elementary stream); Matroska output fails with
"Could not write header", after which FFmpeg 9.0.2 can crash while closing
the encoder.
Driver enumeration alone does not prove encoding, decoding or screen capture.

## Support matrix

These are historical board results with the earlier 1.0.0-derived package and
then-current kernels, not validation of this 1.1.1 update. Updated Sheng checks
are listed separately below; no other board was rebuilt or deployed for this update.

"Verified" means pixel-exact comparison against software decoding with stock
FFmpeg (VA surfaces forced and downloaded as above) and playback in stock mpv
with software fallback disabled. A few display drops during mpv startup are
expected; decoder drops are not.

| Device | Decode (VA-API) | Encode (VA-API) | Not supported or not verified |
| --- | --- | --- | --- |
| Asphalt (Iris, SM8450) | H.264 High, HEVC Main and Main10, VP9 Profile 0 (8-bit) and Profile 2 (10-bit), including B-frame reorder and VP9 alt-ref, at 720p/1080p | H.264 High and Constrained Baseline, HEVC Main 8-bit; CQP, CBR and VBR; [screen recording](#basic-screen-recording) | AV1 and VP8 decode; VP9/AV1 encode; 10-bit encode; nonstandard encode widths (see [limitations](#limitations-and-kernel-requirements)) |
| Polaris (Venus, SDM845) | H.264 High, HEVC Main and Main10 at 720p/1080p | H.264 High, HEVC Main 8-bit; CQP and CBR at 720p/1080p, real-time 1080p30 | 10-bit encode (rejected); screen recording/VPP; arbitrary sizes; long-term CBR bitrate conformance |
| Sheng (Iris, SM8550) | AV1 Main 8/10-bit 4:2:0 at 720p/1080p, plus H.264, HEVC and VP9 | Not covered here | AV1 features listed under [AV1 Main](#av1-main-decoding-and-package-checks); 4K, high frame rates and long-duration thermal behavior |
| Marble (Iris VPU2, SM7475) | H.264 High, HEVC Main and Main10, VP9 Profile 0 (8-bit) at 720p, including B-frame reorder and VP9 alt-ref; 150 frames each pixel-identical to software | H.264 High 8-bit CBR at 720p (90 frames); HEVC Main 8-bit CQP and VBR at 720p, CQP at 1080p and 1280x768 (30 frames); clean software decode | HEVC CBR: with the kernel before Marble queue 0051 the firmware returns empty P frames and encoding fails after the first frame; 0051 is not yet verified on hardware; screen recording not checked; B-frame encoding, VP9 Profile 2 and AV1; mpv playback not yet checked |
| Aurora (Iris, SM8650) | See [Aurora's results and limits](../../docs/aurora/hardware.md#optional-va-api-backend) | | |

For strict VA-API playback checks, use
`mpv --hwdec=vaapi --hwdec-software-fallback=no input.mkv` and inspect
`hwdec-current`. Automatic selection alone is not evidence of hardware decoding.
Player defaults remain consumer policy.

### Sheng checks with the 1.1.1 update (2026-10-31)

- All six H.264/HEVC loop-filter controls appear with the companion kernel queue.
  A 900-frame, 30-second GStreamer H.264 hardware encode at 640×360@30 decodes
  all 900 frames independently in software and again with VA hardware decoding.
  The bitstream contains the requested alpha/beta deblocking offsets `2/2`.
- AV1 720p 8-bit and 10-bit samples each produce 60 displayed frames with every
  hardware-decoded frame hash matching libdav1d. Each sample includes 29 hidden
  and 24 show-existing pictures, exercising the new NOSHOW handling.
- BGRA/BGRX/RGBA/RGBX base conversion to NV12 matches software bytes exactly on
  synthetic SDR patterns. A separate NV12→Vulkan 90° transpose also matches;
  GLES RGB and upstream Vulkan YUV paths both run. RGB supports Explicit SDR
  BT.601/709 metadata; BT.2020/PQ/HLG requests are rejected rather than mapped
  silently. Range must match in software/hardware comparisons.
- No new Iris/SMMU/GPU fault was observed. Real application-call validation is
  still separate. The codec checks preceded a follow-up confined to the RGB
  parameter parser; codec code was unchanged. Native package tests cover MSM
  allocation, CAPTURE memory budgeting and the RGB parser's SDR/HDR boundaries.

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

### AV1 Main decoding and package checks

AV1 Main 8/10-bit reconstruction is supplied by upstream 1.1.1; the older local
AV1 patch and its implementation-specific serializer scripts have been removed.
Their earlier results applied to the previous package version and are not a
validation claim for this update. The updated Iris companion queue includes
NOSHOW buffer recycling needed for hidden AV1 references.

Native package builds run upstream's hardware-independent MSM allocation and
CAPTURE memory-budget tests. These are not codec or VPP hardware tests. Upstream
also provides optional hardware programs, disabled by default; validate the
actual board/kernel/firmware with complete decode and encode workloads.

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
  non-default requests without the loop-filter controls. The bundled Iris
  device queues include the companion control patch; external kernels must
  provide matching support.
- VA decoding requires Iris decode-order controls and adequate capture buffer
  pools. The Iris device queues include the complete companion patch set. Without them, H.264/HEVC VA context creation fails at
  `S_CTRL DISPLAY_DELAY` even though `vainfo` lists the profiles.
  Driver discovery alone is not decoding acceptance.
- Firmware and the existing Asphalt kernel encoding fixes are still required.
  This backend has its own V4L2 implementation; it does not use FFmpeg's repaired
  `hevc_v4l2m2m` wrapper, and results for that wrapper do not apply to it.

See the pinned upstream [requirements and tests](https://github.com/radxa-pkg/qcom-va-driver/tree/0980a1decf26d34c9aa71cd0a4a0d25703a7a17f/tests).

## Iris companion kernel patches

The Iris queues for Asphalt, Aurora, Marble and Sheng include all five companion
patches from [upstream commit `0980a1decf26`](https://github.com/radxa-pkg/qcom-va-driver/tree/0980a1decf26d34c9aa71cd0a4a0d25703a7a17f/patches): decode-order output, larger CAPTURE
pools, HFI gen2 H.264/HEVC deblocking controls, preserved error-buffer timestamps,
and internal recycling of non-display decoder pictures. Their stable patch IDs
match upstream's `patches/0001` through `0005`; source author, date and trailers
are retained. The deblocking controls allow clients such as GStreamer to request
nonzero filter offsets instead of failing driver parameter validation.

These are Iris changes. Clover/Polaris use Venus, which already exposes standard
H.264 loop-filter controls; they do not receive Iris patches. Queue application
is not hardware validation. Sheng synthetic codec/VPP results are listed above;
other boards were not built or deployed by this change.
