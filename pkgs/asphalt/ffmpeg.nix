{ ffmpeg }:
ffmpeg.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./ffmpeg-v4l2-p010.patch ];
})
