#!/usr/bin/env python3
"""Download and remux two silent, 180-second Big Buck Bunny test clips."""
import argparse
import hashlib
import json
import pathlib
import subprocess
import sys

sys.dont_write_bytecode = True
from run import validate_media

SOURCES = {
    "h264": ("h264", "e131ad42621442758a3acb899bfbdfeeab0b40c7e2f7c7e66683f58a09a99aee"),
    "hevc": ("h265", "8c9460e1791765030aa39dda710d709c69aaddee92eda82f3920b8c2d7b4b613"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=pathlib.Path, help="New host media directory")
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=False)
    for codec, (url_codec, digest) in SOURCES.items():
        source = args.directory / f"source-{codec}.mp4"
        video = args.directory / f"{codec}.mp4"
        url = f"https://test-videos.co.uk/vids/bigbuckbunny/mp4/{url_codec}/1080/Big_Buck_Bunny_1080_10s_5MB.mp4"
        subprocess.run(["curl", "--fail", "--location", "--retry", "2", "--output", str(source), url], check=True)
        with source.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != digest:
                raise RuntimeError("Source checksum mismatch: " + str(source))
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-stream_loop", "-1", "-i", str(source),
                        "-t", "180", "-map", "0:v:0", "-c:v", "copy", "-an", "-sn", "-dn",
                        "-movflags", "+faststart", str(video)], check=True)
        info = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_streams", "-show_format",
                                                  "-of", "json", str(video)], text=True))
        validate_media(info, codec)
        (args.directory / f"{codec}.json").write_text(json.dumps(info, indent=2) + "\n")
        print(f"Prepared {video}: {info['streams'][0]['nb_frames']} frames", flush=True)


if __name__ == "__main__":
    main()
