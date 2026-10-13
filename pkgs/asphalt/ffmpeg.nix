# Optional direct V4L2 M2M diagnostic build: Iris P010/NV12 layout and encoder draining.
# Retained for explicit use; normal playback uses upstream FFmpeg via VA-API.
{ ffmpeg, buildPackages }:
ffmpeg.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ./ffmpeg-v4l2-p010.patch
    ./ffmpeg-v4l2-nv12-copy.patch
    ./ffmpeg-v4l2-encoder-drain.patch
  ];
  passthru = (old.passthru or { }) // {
    tests = (old.passthru.tests or { }) // {
      encoder-drain =
        buildPackages.runCommand "ffmpeg-v4l2-encoder-drain-test"
          {
            nativeBuildInputs = [
              buildPackages.stdenv.cc
              buildPackages.patch
              buildPackages.python3
            ];
          }
          ''
            mkdir -p libavcodec
            cp ${ffmpeg.src}/libavcodec/v4l2_context.c libavcodec/
            cp ${ffmpeg.src}/libavcodec/v4l2_m2m.h libavcodec/
            chmod u+w libavcodec/*
            patch -p1 < ${./ffmpeg-v4l2-encoder-drain.patch}
            python3 ${../../tests/ffmpeg-v4l2-drain-extract.py} \
              libavcodec/v4l2_context.c ffmpeg-drain-functions.inc
            cc -D_GNU_SOURCE -std=c11 -Wall -Wextra -Werror -I. \
              ${../../tests/ffmpeg-v4l2-drain.c} -o encoder-drain-test
            ./encoder-drain-test
            touch "$out"
          '';
      nv12-copy =
        buildPackages.runCommand "ffmpeg-v4l2-nv12-copy-test"
          {
            nativeBuildInputs = [
              buildPackages.stdenv.cc
              buildPackages.patch
            ];
          }
          ''
            mkdir -p libavcodec
            cp ${ffmpeg.src}/libavcodec/v4l2_buffers.c libavcodec/
            chmod u+w libavcodec/v4l2_buffers.c
            patch -p1 < ${./ffmpeg-v4l2-nv12-copy.patch}
            cc -std=c11 -Wall -Wextra -Werror -Ilibavcodec \
              ${../../tests/ffmpeg-v4l2-nv12.c} -o nv12-copy-test
            ./nv12-copy-test
            touch "$out"
          '';
    };
  };
})
