#!/usr/bin/env python3
"""Exercise the evaluated closure selector in an isolated initrd filesystem.

Pass the .x86_64-linux.clover.selector.text from tests/direct-boot.nix as a file.
Requires Linux bubblewrap, Bash and coreutils; no image build or device access.
"""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


selector = Path(sys.argv[1]).resolve()
bash = os.path.realpath(shutil.which("bash"))
coreutils = str(Path(os.path.realpath(shutil.which("cat"))).parent)
closure = "/nix/store/" + "a" * 32 + "-nixos-system-clover-test"
scratch = Path(__file__).resolve().parents[1] / "tmp" / "direct-boot"
scratch.mkdir(parents=True, exist_ok=True)

with tempfile.TemporaryDirectory(dir=scratch) as temporary:
    base = Path(temporary)
    etc = base / "etc"
    root = base / "sysroot"
    etc.mkdir()
    root.mkdir()
    (etc / "mobile-direct-system").write_text(closure + "\n")
    init = root / closure.lstrip("/") / "init"
    init.parent.mkdir(parents=True)
    init.write_text("#!/bin/sh\nexit 0\n")
    init.chmod(0o755)
    profile = root / "nix/var/nix/profiles/system"
    profile.parent.mkdir(parents=True)
    profile.symlink_to("/nix/store/another-generation")
    cmdline = base / "cmdline"

    def run():
        return subprocess.run(
            [
                "bwrap", "--unshare-user", "--unshare-pid", "--die-with-parent",
                "--tmpfs", "/", "--ro-bind", "/nix", "/nix",
                "--bind", str(etc), "/etc", "--bind", str(root), "/sysroot",
                "--ro-bind", str(selector), "/selector",
                "--proc", "/proc", "--ro-bind", str(cmdline), "/proc/cmdline",
                "--setenv", "PATH", coreutils, bash, "-c",
                f'{bash} /selector && readlink /nixos-closure && cat /etc/switch-root.conf',
            ],
            text=True, capture_output=True,
        )

    for params in [
        "init=/wrong/init root=/dev/dm-0",
        "_nit=/wrong/init _oot=/wrong root=/dev/dm-0",
        "",
    ]:
        cmdline.write_text(params + "\n")
        result = run()
        assert result.returncode == 0, result.stderr
        assert result.stdout == closure + "\nNEW_INIT=\n", result.stdout

    init.unlink()
    result = run()
    assert result.returncode != 0, "Missing selected closure must fail"
    assert result.stdout == "", result.stdout

print("PASS: pinned closure despite changed profile/replaced/missing cmdline; missing closure fails")
