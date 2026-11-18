# SPDX-License-Identifier: MIT
"""Prepare private speaker firmware data; contains no device/control operation.

The CLI is root-only. All private inputs are runtime strings, never Nix paths.
The manifest establishes operator-selected identity, not acoustic safety.
"""

import argparse
import errno
import fcntl
import hashlib
import json
import os
import re
import secrets
import shutil
import stat
import sys


RUNTIME_DIRECTORY = "/run/unicorn-audio"
INPUTS = {
    "cs35l41-dsp1-spk-prot.wmfw": (4, 16 * 1024 * 1024),
    "T-cs35l41-dsp1-spk-prot.bin": (4, 16 * 1024 * 1024),
    "B-cs35l41-dsp1-spk-prot.bin": (4, 16 * 1024 * 1024),
    "crus_calr.bin": (8, 8),
    "t-music.be32": (300, 300),
    "b-music.be32": (64, 64),
}
OUTPUTS = {
    "cs35l41-dsp1-spk-prot-xiaomi-unicorn-t.wmfw": "cs35l41-dsp1-spk-prot.wmfw",
    "cs35l41-dsp1-spk-prot-xiaomi-unicorn-t.bin": "T-cs35l41-dsp1-spk-prot.bin",
    "cs35l41-dsp1-spk-prot-xiaomi-unicorn-b.wmfw": "cs35l41-dsp1-spk-prot.wmfw",
    "cs35l41-dsp1-spk-prot-xiaomi-unicorn-b.bin": "B-cs35l41-dsp1-spk-prot.bin",
    "cs35l41-xiaomi-unicorn-calibration.bin": "crus_calr.bin",
    "cs35l41-xiaomi-unicorn-t-music.be32": "t-music.be32",
    "cs35l41-xiaomi-unicorn-b-music.be32": "b-music.be32",
}


class PreparationError(Exception):
    """Messages must never contain calibration, coefficients or their hashes."""


def _production_input_directory(path, *, owner_uid=0, _anchor_fd=None):
    # An alternate anchor is for synthetic host tests only, not a CLI option.
    if (not isinstance(path, str)
            or not re.fullmatch(r"/var/lib/unicorn-audio/[A-Za-z0-9_.+-]+(?:/[A-Za-z0-9_.+-]+)*", path)
            or any(part in (".", "..") for part in path.split("/"))):
        raise PreparationError("input directory must be canonical and below /var/lib/unicorn-audio/")
    fd = (os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
          if _anchor_fd is None else os.dup(_anchor_fd))
    try:
        root_device = os.fstat(fd).st_dev
        for component in path.split("/")[1:]:
            next_fd = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                              dir_fd=fd)
            os.close(fd)
            fd = next_fd
            info = os.fstat(fd)
            if (info.st_dev != root_device or info.st_uid != owner_uid
                    or stat.S_IMODE(info.st_mode) & 0o022):
                raise PreparationError("input ancestry must be owned by root, unwritable by others and on the root filesystem")
        if stat.S_IMODE(info.st_mode) & 0o077:
            raise PreparationError("input directory must be root-only")
        result, fd = fd, None
        return result
    finally:
        if fd is not None:
            os.close(fd)


def _private_directory(path, owner_uid, *, dir_fd=None):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                 dir_fd=dir_fd)
    info = os.fstat(fd)
    if info.st_uid != owner_uid or stat.S_IMODE(info.st_mode) & 0o077:
        os.close(fd)
        raise PreparationError("directory must be owner-only and owned by the expected user")
    return fd


def _read_private(fd, name, owner_uid, maximum):
    # NONBLOCK prevents a FIFO or device substitution blocking before fstat.
    file_fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK,
                      dir_fd=fd)
    try:
        before = os.fstat(file_fd)
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != owner_uid
                or stat.S_IMODE(before.st_mode) & 0o077 or before.st_nlink != 1
                or before.st_dev != os.fstat(fd).st_dev):
            raise PreparationError("input must be a private, singly linked regular file on its directory filesystem")
        if before.st_size > maximum:
            raise PreparationError("input exceeds its bounded size")
        data = bytearray()
        while len(data) <= maximum:
            block = os.read(file_fd, min(65536, maximum + 1 - len(data)))
            if not block:
                break
            data.extend(block)
        after = os.fstat(file_fd)
        keys = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")
        if (len(data) > maximum or len(data) != before.st_size
                or any(getattr(before, key) != getattr(after, key) for key in keys)):
            raise PreparationError("input changed during its bounded read")
        return bytes(data)
    finally:
        os.close(file_fd)


def _unique_pairs(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise PreparationError("manifest contains a duplicate key")
        value[key] = item
    return value


def _manifest(data):
    try:
        manifest = json.loads(data, object_pairs_hook=_unique_pairs)
    except (ValueError, UnicodeError) as exc:
        raise PreparationError("manifest is not valid UTF-8 JSON") from exc
    if (not isinstance(manifest, dict) or set(manifest) != {"format", "files"}
            or manifest["format"] != "unicorn-speaker-runtime-v1"
            or not isinstance(manifest["files"], dict)
            or set(manifest["files"]) != set(INPUTS)):
        raise PreparationError("manifest must describe exactly the six fixed source files")
    for name, entry in manifest["files"].items():
        low, high = INPUTS[name]
        if (not isinstance(entry, dict) or set(entry) != {"bytes", "sha256"}
                or type(entry["bytes"]) is not int or not low <= entry["bytes"] <= high
                or not isinstance(entry["sha256"], str)
                or not re.fullmatch(r"[0-9a-f]{64}", entry["sha256"])):
            raise PreparationError("manifest entry has an invalid size or hash format")
    return manifest["files"]


def _validate_payloads(data):
    if not data["cs35l41-dsp1-spk-prot.wmfw"].startswith(b"WMFW"):
        raise PreparationError("WMFW signature is invalid")
    for prefix in ("T", "B"):
        if not data[prefix + "-cs35l41-dsp1-spk-prot.bin"].startswith(b"WMDR"):
            raise PreparationError("coefficient container signature is invalid")
    calibration = data["crus_calr.bin"]
    if len(calibration) != 8 or any(
        not 8000 <= int.from_bytes(calibration[at:at + 4], "little") <= 12000
        for at in (0, 4)
    ):
        raise PreparationError("calibration must have the exact original format and OEM range")
    for prefix, count in (("t", 75), ("b", 16)):
        music = data[prefix + "-music.be32"]
        if len(music) != count * 4 or int.from_bytes(music[:4], "big") != count:
            raise PreparationError("Music input has an invalid per-amplifier size or header")


def _existing_matches(runtime_fd, expected, owner_uid):
    try:
        firmware_fd = _private_directory("firmware", owner_uid, dir_fd=runtime_fd)
    except FileNotFoundError:
        return False
    try:
        if set(os.listdir(firmware_fd)) != {"cirrus"}:
            raise PreparationError("existing RAM tree is not the prepared layout")
        cirrus_fd = _private_directory("cirrus", owner_uid, dir_fd=firmware_fd)
        try:
            if set(os.listdir(cirrus_fd)) != set(expected):
                raise PreparationError("existing RAM tree is incomplete or contains unexpected files")
            for name, data in expected.items():
                if _read_private(cirrus_fd, name, owner_uid, len(data)) != data:
                    raise PreparationError("existing RAM data differs; stop consumers and reboot before replacement")
        finally:
            os.close(cirrus_fd)
    finally:
        os.close(firmware_fd)
    return True


def prepare(input_directory, runtime_directory=RUNTIME_DIRECTORY, *, owner_uid=0, input_fd=None):
    """Only CLI passes owner_uid=0; tests use their real host owner and private dirs."""
    input_fd = (_private_directory(input_directory, owner_uid)
                if input_fd is None else os.dup(input_fd))
    try:
        manifest = _manifest(_read_private(input_fd, "manifest.json", owner_uid, 32768))
        data = {}
        for name, entry in manifest.items():
            payload = _read_private(input_fd, name, owner_uid, entry["bytes"])
            if len(payload) != entry["bytes"] or hashlib.sha256(payload).hexdigest() != entry["sha256"]:
                raise PreparationError("private input does not match its operator-provisioned manifest")
            data[name] = payload
        _validate_payloads(data)
    finally:
        os.close(input_fd)

    expected = {destination: data[source] for destination, source in OUTPUTS.items()}
    runtime_fd = _private_directory(runtime_directory, owner_uid)
    lock_fd = None
    staging = None
    try:
        lock_fd = os.open(".prepare.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC,
                          0o600, dir_fd=runtime_fd)
        info = os.fstat(lock_fd)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != owner_uid
                or stat.S_IMODE(info.st_mode) & 0o077 or info.st_nlink != 1):
            raise PreparationError("preparation lock is not private")
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise PreparationError("another preparation owns the runtime lock") from exc
        if _existing_matches(runtime_fd, expected, owner_uid):
            return "unchanged"
        staging_name = ".prepare-" + secrets.token_hex(12)
        os.mkdir(staging_name, 0o700, dir_fd=runtime_fd)
        staging = staging_name
        stage_fd = _private_directory(staging, owner_uid, dir_fd=runtime_fd)
        try:
            os.mkdir("cirrus", 0o700, dir_fd=stage_fd)
            cirrus_fd = _private_directory("cirrus", owner_uid, dir_fd=stage_fd)
            try:
                for name, payload in expected.items():
                    fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                                 0o600, dir_fd=cirrus_fd)
                    try:
                        remaining = memoryview(payload)
                        while remaining:
                            written = os.write(fd, remaining)
                            if written <= 0:
                                raise PreparationError("RAM data write was incomplete")
                            remaining = remaining[written:]
                    finally:
                        os.close(fd)
            finally:
                os.close(cirrus_fd)
        finally:
            os.close(stage_fd)
        # Root-only runtime dir plus the retained flock serializes publishers.
        os.rename(staging, "firmware", src_dir_fd=runtime_fd, dst_dir_fd=runtime_fd)
        staging = None
        return "prepared"
    finally:
        if staging is not None:
            shutil.rmtree(staging, dir_fd=runtime_fd)
        if lock_fd is not None:
            os.close(lock_fd)
        os.close(runtime_fd)


def main():
    parser = argparse.ArgumentParser(description="Validate and publish private speaker runtime data only")
    parser.add_argument("--input-directory", required=True)
    args = parser.parse_args()
    try:
        if os.geteuid() != 0:
            raise PreparationError("this data preparer must run as root")
        fd = _production_input_directory(args.input_directory)
        try:
            # Keep the securely walked directory descriptor through every read.
            outcome = prepare(args.input_directory, input_fd=fd)
        finally:
            os.close(fd)
    except (PreparationError, OSError) as exc:
        if isinstance(exc, OSError):
            message = "filesystem preparation failed (errno=%d)" % (exc.errno or errno.EIO)
        else:
            message = str(exc)
        print("unicorn-audio-prepare: " + message, file=sys.stderr)
        return 1
    print("unicorn-audio-prepare: seven private RAM firmware files " + outcome)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
