# Optional direct V4L2 M2M diagnostic build: Venus pending-packet handling.
# Retained for explicit use; normal playback uses upstream FFmpeg via VA-API.
{ ffmpeg }:
ffmpeg.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./ffmpeg-v4l2-keep-pending-packet.patch ];
})
