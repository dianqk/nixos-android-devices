"""Merge module-owned loader settings after the standard installer rewrites them."""
from pathlib import Path
import os
import sys
import tempfile


def update(path: Path, fragment: str) -> None:
    keys = {"auto-reboot", "auto-poweroff"}
    lines = [line for line in path.read_text().splitlines()
             if not line.split() or line.split()[0] not in keys]
    contents = "\n".join(lines) + "\n" + fragment
    fd, temporary = tempfile.mkstemp(prefix=".loader-actions-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as output:
            output.write(contents)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


if __name__ == "__main__":
    update(Path(sys.argv[1]), Path(sys.argv[2]).read_text())
