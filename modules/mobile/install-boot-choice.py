#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""NixOS bootstrap files only; native evidence always retains exclusive ownership.

The normal systemd-boot extra-files tracker MUST NOT contain these paths. This
hook never interprets receipts/journals, never updates an image and never grants
native authority. Even corrupt evidence means leave both files untouched.
"""
import fcntl
import os
import stat
import sys

HELPER = "EFI/android-devices/boot-choice.efi"
MENU = "loader/entries/android-same-slot.conf"
EVIDENCE = ["EFI/android-devices/" + n for n in
            ("boot-choice.installation", "boot-choice.install.undo", "boot-choice.undo")]


def protected(fd, device):
    m = os.fstat(fd)
    if (not stat.S_ISDIR(m.st_mode) or m.st_dev != device
            or m.st_uid != os.geteuid() or m.st_mode & 0o022):
        raise RuntimeError("protected same-device ESP directory required")


def parent(root, path, create=False):
    fd = os.dup(root)
    try:
        device = os.fstat(root).st_dev
        for name in path.split("/")[:-1]:
            try:
                child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            except FileNotFoundError:
                if not create:
                    raise
                os.mkdir(name, 0o700, dir_fd=fd)
                os.fsync(fd)
                child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            try:
                protected(child, device)
            except BaseException:
                os.close(child)
                raise
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


def present(root, path):
    try:
        fd = parent(root, path)
    except FileNotFoundError:
        return False
    try:
        try:
            os.stat(path.split("/")[-1], dir_fd=fd, follow_symlinks=False)
        except FileNotFoundError:
            return False
        return True  # Any type/content is evidence, NOT write authorization.
    finally:
        os.close(fd)


def deploy(root_path, helper, menu):
    root = os.open(root_path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        protected(root, os.fstat(root).st_dev)
        # The native Store holds this same directory lock for its entire session.
        fcntl.flock(root, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if any(present(root, name) for name in EVIDENCE):
            return "native evidence present; bootstrap pair left untouched"
        contents = [(HELPER, open(helper, "rb").read()), (MENU, open(menu, "rb").read())]
        for name, data in contents:
            fd = parent(root, name, create=True)
            leaf = name.split("/")[-1]
            scratch = leaf + ".bootstrap-new"
            created = False
            try:
                out = os.open(scratch, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
                created = True
                with os.fdopen(out, "wb") as stream:
                    stream.write(data)
                    stream.flush()
                    os.fsync(stream.fileno())
                os.replace(scratch, leaf, src_dir_fd=fd, dst_dir_fd=fd)
                created = False
                os.fsync(fd)
            finally:
                if created:
                    os.unlink(scratch, dir_fd=fd)
                os.close(fd)
        os.fsync(root)
        return "bootstrap helper/menu provisioned; no native receipt created"
    finally:
        os.close(root)


if __name__ == "__main__":
    print(deploy(*sys.argv[1:]))
