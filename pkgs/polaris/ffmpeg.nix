{ ffmpeg }:
ffmpeg.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./ffmpeg-v4l2-keep-pending-packet.patch ];
})
