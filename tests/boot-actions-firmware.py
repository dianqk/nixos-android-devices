"""Compile the actual firmware adapter with isolated interface mocks."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(dir=os.environ["MOBILE_TEST_TMP"]) as directory:
    temporary = Path(directory)
    for name in ("dm.h", "dm/device-internal.h", "irq_func.h", "linux/errno.h",
                 "linux/psci.h", "power/pmic.h", "asm/system.h", "efi_loader.h"):
        header = temporary / name
        header.parent.mkdir(parents=True, exist_ok=True)
        header.write_text('#include "boot-actions-uboot-mocks.h"\n')
    (temporary / "mobile_boot_action.h").write_text('#include "protocol.h"\n')
    (temporary / "mobile_pon_transaction.h").write_text('#include "pon-transaction.h"\n')
    executable = temporary / "test"
    subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter",
        f"-I{temporary}", f"-I{root / 'tests'}", f"-I{root / 'pkgs/mobile-boot-action'}",
        str(root / "tests/boot-actions-firmware.c"), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=10)
