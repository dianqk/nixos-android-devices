# Optional Qualcomm local-media/recording profile for H.264/HEVC experiments
# and reduced native/cross build dependencies. Retains V4L2 M2M and VA-API,
# built-in audio/subtitle codecs, and no GTK/network dependency chain.
# Device variants add direct V4L2 fixes for diagnostics and backend comparisons.
# Normal device configurations use upstream FFmpeg/libmpv with a separate
# VA-API driver; this profile is deliberately not selected by device modules.
{
  ffmpeg,
  lib,
  libdrm,
  libva-minimal,
}:
let
  drm = libdrm.override {
    withIntel = false;
    withValgrind = false;
  };
  minimal = ffmpeg.override {
    # Do not inherit nixpkgs' "small" desktop/multi-vendor dependency set.
    withHeadlessDeps = false;
    withSmallDeps = false;
    withFullDeps = false;

    buildFfmpeg = true;
    buildFfprobe = true;
    buildAvcodec = true;
    buildAvdevice = true;
    buildAvfilter = true;
    buildAvformat = true;
    buildAvutil = true;
    buildSwresample = true;
    buildSwscale = true;
    withSafeBitstreamReader = true;
    withHardcodedTables = true;
    withPixelutils = true;

    # V4L2 M2M talks directly to the kernel; it does not need libv4l2.
    # VAAPI uses nixpkgs' libva-minimal, without X11/Wayland dependencies.
    withV4l2M2m = true;
    withVaapi = true;
    withDrm = true;
    libdrm = drm;
    libva-minimal = libva-minimal.override { libdrm = drm; };
    # Matroska compression, PNG screenshots and compressed bitmap subtitles.
    withZlib = true;
    withIconv = true;
  };
in
minimal.overrideAttrs (old: {
  doCheck = false;
  doInstallCheck = false;
  # nixpkgs adds texinfo even when all documentation outputs are disabled.
  nativeBuildInputs = builtins.filter (p: lib.getName p != "texinfo") old.nativeBuildInputs;
  configureFlags = old.configureFlags ++ [
    "--disable-autodetect"
    "--disable-decoders"
    "--disable-encoders"
    "--disable-hwaccels"
    # VAAPI's decode hooks require the native H.264/HEVC decoder frontends.
    "--enable-decoder=h264,hevc,h264_v4l2m2m,hevc_v4l2m2m"
    "--enable-encoder=h264_v4l2m2m,hevc_v4l2m2m,h264_vaapi,hevc_vaapi"
    "--enable-hwaccel=h264_vaapi,hevc_vaapi"
    # mpv screenshots/cover art and raw frames supplied by capture tools.
    "--enable-decoder=rawvideo,wrapped_avframe,png,mjpeg"
    "--enable-encoder=rawvideo,wrapped_avframe,png,mjpeg"
    "--disable-indevs"
    "--disable-outdevs"
    "--enable-indev=lavfi"
    "--disable-protocols"
    "--enable-protocol=file,pipe,fd,crypto,data,concat,subfile"
  ];
  # FFmpeg currently lists the HDR image codec in the audio section.
  preConfigure = (old.preConfigure or "") + ''
    # Keep built-in audio and subtitle codecs, including PCM/ADPCM. mpv renders
    # subtitles with its own libass but still uses libavcodec to decode them.
    # Read the upstream category boundaries so new audio/subtitle codecs do not
    # need a duplicated allowlist here. Fail if upstream changes that layout.
    mediaCodecs=$(sed -n '/^\/\* audio codecs \*\//,/^\/\* external libraries \*\//p' \
      libavcodec/allcodecs.c)
    for kind in decoder encoder; do
      codecs=$(printf '%s\n' "$mediaCodecs" |
        sed -n "s/^extern const FFCodec ff_\(.*\)_$kind;.*/\1/p" |
        sed '/^hdr$/d' |
        paste -sd, -)
      test -n "$codecs" || { echo "Cannot find built-in audio/subtitle $kind list" >&2; exit 1; }
      configureFlagsArray+=("--enable-$kind=$codecs")
    done
  '';
})
