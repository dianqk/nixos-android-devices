#!/usr/bin/env python3
"""Verify VA AV1 header reconstruction against software decoding of silent fixtures.

This uses the TEST-ONLY serializer created by make-av1-serializer.py. It does
not validate hardware, playback speed, or DMA-BUF interoperability.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--driver", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--render-node", default="/dev/dri/renderD128")
parser.add_argument("fixtures", nargs="+", type=Path)
args = parser.parse_args()
driver = args.driver.resolve()
if not (driver / ".av1-serializer-only").is_file():
    parser.error("--driver must point to a marked test-only serializer")
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
results = []


def hashes(path):
    if not path.exists():
        return []
    return [line.rsplit(",", 1)[-1].strip() for line in path.read_text().splitlines()
            if line and not line.startswith("#")]


def run(command, log, env=None):
    with log.open("w") as handle:
        return subprocess.run(command, stdout=handle, stderr=subprocess.STDOUT,
                              env=env, timeout=90).returncode


for index, fixture in enumerate(args.fixtures):
    stem = output / f"{index}-{fixture.stem}"
    def path(suffix):
        return Path(str(stem) + suffix)
    info = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
        "stream=codec_name,pix_fmt", "-of", "json", str(fixture)]))["streams"][0]
    if info["codec_name"] != "av1" or info["pix_fmt"] not in ("yuv420p", "yuv420p10le"):
        parser.error(f"{fixture}: expected AV1 Main 8/10-bit 4:2:0")
    fmt = "p010le" if info["pix_fmt"] == "yuv420p10le" else "nv12"
    env = os.environ | {
        "IRIS_VAAPI_DEBUG": "1", "IRIS_VAAPI_DUMP": str(path(".obu")),
        "LIBVA_DRIVER_NAME": "v4l2", "LIBVA_DRIVERS_PATH": str(driver),
    }
    serialize = run([
        "ffmpeg", "-nostdin", "-v", "warning", "-xerror", "-y",
        "-hwaccel", "vaapi", "-hwaccel_device", args.render_node,
        "-hwaccel_output_format", "vaapi", "-i", str(fixture), "-an",
        "-vf", "hwdownload,format=" + fmt, "-fps_mode", "passthrough", "-f", "null", "-",
    ], path(".serialize.log"), env)
    decode_status = []
    for input_path, suffix in [(path(".obu"), ".rebuilt"), (fixture, ".reference")]:
        decode_status.append(run([
            "ffmpeg", "-nostdin", "-v", "warning", "-xerror", "-y",
            "-hwaccel", "none", "-c:v", "libdav1d", "-i", str(input_path), "-an",
            "-vf", "format=" + fmt, "-fps_mode", "passthrough", "-f", "framemd5",
            str(path(suffix + ".md5")),
        ], path(suffix + ".log")))
    indices = [int(n) for n in re.findall(
        r"SERIALIZER_OUTPUT (\d+)", path(".serialize.log").read_text())]
    rebuilt, reference = hashes(path(".rebuilt.md5")), hashes(path(".reference.md5"))
    mapped = [rebuilt[n - 1] if 0 < n <= len(rebuilt) else None for n in indices]
    passed = serialize == 0 and decode_status == [0, 0] and bool(reference) and mapped == reference
    result = dict(fixture=str(fixture), passed=passed, displayed=len(indices),
                  reference=len(reference), decoder_submissions=len(rebuilt),
                  serialize_exit=serialize, software_exit=decode_status)
    results.append(result)
    print(json.dumps(result), flush=True)
(output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
raise SystemExit(0 if all(result["passed"] for result in results) else 1)
