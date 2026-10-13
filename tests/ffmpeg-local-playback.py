"""Exercise the restricted FFmpeg without video hardware.

Usage: python3 tests/ffmpeg-local-playback.py /path/to/ffmpeg/bin WORK_DIRECTORY
The caller must be able to execute the target architecture (native or binfmt).
"""

import json
from pathlib import Path
import subprocess
import sys


bin_dir = Path(sys.argv[1]).resolve()
work = Path(sys.argv[2]).resolve()
work.mkdir(parents=True, exist_ok=True)


def run(program, *args):
    result = subprocess.run(
        [str(bin_dir / program), "-hide_banner", *args],
        cwd=work,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode:
        print(result.stderr, file=sys.stderr)
        result.check_returncode()
    return result.stdout


def codecs(kind, media):
    return {
        fields[1]
        for line in run("ffmpeg", "-" + kind).splitlines()
        if len(fields := line.split()) > 1
        and fields[0].startswith(media)
        and fields[1] != "="
    }


images = {"png", "mjpeg", "rawvideo", "wrapped_avframe"}
assert codecs("encoders", "V") == images | {
    "h264_v4l2m2m", "hevc_v4l2m2m", "h264_vaapi", "hevc_vaapi"
}
assert codecs("decoders", "V") == images | {
    "h264", "hevc", "h264_v4l2m2m", "hevc_v4l2m2m"
}
assert {"aac", "flac", "mp3", "opus", "vorbis"} <= codecs("decoders", "A")
assert {"ass", "subrip", "mov_text", "pgssub", "dvdsub", "dvbsub"} <= codecs(
    "decoders", "S"
)
protocols = set(run("ffmpeg", "-protocols").split())
assert {"file", "pipe", "fd"} <= protocols
assert not {"http", "https", "tcp", "udp", "rtmp", "srt"} & protocols
assert not (bin_dir / "ffplay").exists()

(work / "captions.srt").write_text(
    "1\n00:00:00,000 --> 00:00:01,000\nLocal subtitle playback\n", encoding="utf-8"
)
run(
    "ffmpeg", "-v", "error", "-y",
    "-f", "lavfi", "-i", "testsrc2=size=128x96:rate=5:duration=1",
    "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
    "-i", "captions.srt", "-map", "0:v", "-map", "1:a", "-map", "2:s",
    "-c:v", "png", "-pix_fmt", "rgb24", "-c:a", "aac", "-c:s", "ass",
    "sample.mkv",
)
probe = json.loads(run("ffprobe", "-v", "error", "-show_streams", "-of", "json", "sample.mkv"))
assert [s["codec_name"] for s in probe["streams"]] == ["png", "aac", "ass"]
run("ffmpeg", "-v", "error", "-xerror", "-i", "sample.mkv", "-f", "null", "-")
subtitle = run("ffmpeg", "-v", "error", "-i", "sample.mkv", "-map", "0:s", "-f", "srt", "-")
assert "Local subtitle playback" in subtitle
run("ffmpeg", "-v", "error", "-y", "-i", "sample.mkv", "-frames:v", "1", "screenshot.png")
assert (work / "screenshot.png").read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
print("PASS: codec/protocol boundaries, local mux/demux, audio, subtitles and PNG screenshots")
