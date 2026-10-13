#!/usr/bin/env python3
"""Build a TEST-ONLY VA parameter serializer, never an installable video driver.

Run inside the libva-v4l2 development environment. The supplied source must
already have this package's patches applied. Generated files go in --work-dir.
"""
import argparse
from pathlib import Path
import re
import shutil
import subprocess

DECODER_SINK = r'''
// Test-only sink: serialize VA pictures without decoding or video hardware.
std::string find_device() { return "TEST_SERIALIZER_ONLY"; }
bool device_supports_av1(const std::string &) { return true; }
Decoder::Decoder(const std::string &, unsigned w, unsigned h, unsigned,
                 VAProfile, int fd, unsigned f)
    : width_(w), height_(h), fourcc_(f), copier_(fd) {
    dump_ = fopen(getenv("IRIS_VAAPI_DUMP"), "wb");
    check(dump_, "open serializer output");
}
Decoder::~Decoder() { if (dump_) fclose(dump_); }
void Decoder::submit(const std::vector<uint8_t> &bytes, const std::shared_ptr<Surface> &s) {
    check(fwrite(bytes.data(), 1, bytes.size(), dump_) == bytes.size(), "write serializer output");
    fflush(dump_);
    s->token = next_token_++;
    auto m = std::make_shared<Memory>();
    m->width = width_;
    m->height = m->storage_height = height_;
    m->stride = width_ * (fourcc_ == VA_FOURCC_P010 ? 2 : 1);
    m->fourcc = fourcc_;
    m->size = m->stride * height_ * 3 / 2;
    m->fd = memfd_create("AV1_SERIALIZER_TEST_ONLY", MFD_CLOEXEC);
    check(m->fd >= 0 && ftruncate(m->fd, m->size) == 0, "allocate test-only blank output");
    s->memory = m;
    s->pending = false;
    s->status = VA_STATUS_SUCCESS;
}
void Decoder::sync(const std::shared_ptr<Surface> &) {}
void Decoder::finish() {}
void Decoder::refresh() {}
} // namespace irisva
'''

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", type=Path, required=True)
parser.add_argument("--work-dir", type=Path, required=True)
args = parser.parse_args()
work = args.work_dir.resolve()
source = args.source.resolve()
if source == work / "harness" or work.is_relative_to(source):
    parser.error("work directory must be outside the supplied source")
work.mkdir(parents=True, exist_ok=True)
harness = work / "harness"
shutil.copytree(source, harness, dirs_exist_ok=True)
for path in harness.rglob("*"):
    if not path.is_symlink():
        path.chmod(path.stat().st_mode | 0o200)

path = harness / "src/decoder.cpp"
original = path.read_text()
# Retain ordinary memfd map/unmap management, replace all V4L2 decoder calls.
includes = original[:original.index("namespace irisva {")]
memory = original[original.index("Memory::~Memory()"):original.index("std::string find_device()")]
path.write_text(includes + "namespace irisva {\n" + memory + DECODER_SINK)

path = harness / "src/backend.cpp"
original = path.read_text()
encoder_probe = "d->encoder_device = find_encoder_device();"
image_lookup = "VAImageID image_id),\n    auto s = surface(d, id);"
if original.count(encoder_probe) != 1 or original.count(image_lookup) != 1:
    raise SystemExit("Backend layout changed; inspect the test-only injection points")
modified = original.replace(encoder_probe, 'd->encoder_device = "";')
# Test outputs are anonymous memory, so their DMA-BUF synchronization is inapplicable.
modified, count = re.subn(r"ioctl\((memory|m)->fd, DMA_BUF_IOCTL_SYNC, &sync\)",
                         "0 /* test memfd, not a DMA-BUF */", modified)
if count != 5:
    raise SystemExit("DMA-BUF call sites changed; inspect the test-only substitutions")
modified = modified.replace(image_lookup, image_lookup +
    '\n    fprintf(stderr,"SERIALIZER_OUTPUT %llu\\n",(unsigned long long)s->token);')
path.write_text(modified)

build = work / "harness-build"
command = ["meson", "setup", str(build), str(harness), "-Dfastcv=disabled", "-Dgpu-vpp=true"]
if (build / "meson-private").exists():
    command.append("--reconfigure")
subprocess.run(command, check=True)
subprocess.run(["ninja", "-C", str(build)], check=True)
(build / ".av1-serializer-only").write_text("Not a hardware driver. Do not install.\n")
print(f"Serializer test driver: {build}")
