"""Exercise evaluated initial scripts and upstream extra-file cleanup in fixtures.

Usage: MOBILE_TEST_TMP=<isolated directory> python3 tests/boot-actions-install.py
       <boot-actions.nix JSON> <nixpkgs source>
No Nix build, mount, device access or real installer is executed.
"""
import ast
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("loader_actions", root / "modules/mobile/loader-actions.py")
loader_actions = importlib.util.module_from_spec(spec)
spec.loader.exec_module(loader_actions)
evaluations = json.loads(Path(sys.argv[1]).read_text())
builder_path = Path(sys.argv[2]) / "nixos/modules/system/boot/loader/systemd-boot/systemd-boot-builder.py"
builder = ast.parse(builder_path.read_text())
cleanup_ast = ast.Module(body=[next(node for node in builder.body
    if isinstance(node, ast.FunctionDef) and node.name == "remove_extra_files")], type_ignores=[])


def initial(config: dict, destination: Path, sources: Path) -> None:
    command = config["initial"]
    paths = set(re.findall(r"/nix/store/[^\s'\"$;]+", command))
    for path in sorted(paths, key=len, reverse=True):
        fixture = sources / path.removeprefix("/nix/store/")
        fixture.parent.mkdir(parents=True, exist_ok=True)
        contents = "fixture payload\n"
        for name, entry in config["entries"].items():
            if path.endswith("-" + name):
                contents = entry
        fixture.write_text(contents)
        command = command.replace(path, str(fixture))
    subprocess.run(["bash", "-eu", "-c", command],
        env={**os.environ, "out": str(destination)}, check=True, timeout=10)


cases = 0
with tempfile.TemporaryDirectory(dir=os.environ["MOBILE_TEST_TMP"]) as directory:
    temporary = Path(directory)
    for platform, values in evaluations.items():
        for device in ("polaris", "clover", "asphalt", "sheng"):
            config = values["devices"][device]
            disabled = values["disabled"][device]
            esp = temporary / platform / device
            initial(config, esp, esp.parent / (device + "-sources"))
            loader = esp / "loader/loader.conf"
            expected = "auto-reboot yes\nauto-poweroff yes\n"
            assert expected in loader.read_text()
            for name, entry in config["entries"].items():
                assert (esp / "loader/entries" / name).read_text() == entry
                assert (esp / "EFI/nixos/.extra-files/loader/entries" / name).exists()
            helper = "EFI/android-devices/mobile-boot-action.efi"
            assert (esp / helper).exists()
            assert (esp / "EFI/nixos/.extra-files" / helper).exists()

            # Installer hook preserves other loader settings and deduplicates
            # its own settings on repeated calls.
            loader.write_text("default nixos-generation-3.conf\ntimeout 9\neditor no\n"
                              "auto-reboot no\nauto-reboot yes\nauto-poweroff no\n")
            loader_actions.update(loader, expected)
            loader_actions.update(loader, expected)
            assert loader.read_text() == "default nixos-generation-3.conf\ntimeout 9\neditor no\n" + expected

            # Run the exact upstream cleanup function against initial markers:
            # disabling on the first update must delete initial helper/entries.
            namespace = {"BOOT_MOUNT_POINT": esp, "NIXOS_DIR": Path("EFI/nixos")}
            exec(compile(cleanup_ast, str(builder_path), "exec"), namespace)
            namespace["remove_extra_files"]()
            assert not (esp / helper).exists()
            assert not (esp / "loader/entries/android-bootloader.conf").exists()
            assert not (esp / "loader/entries/android-recovery.conf").exists()
            assert not (esp / "loader/entries/android-system.conf").exists()
            assert (esp / "loader/entries/nixos-generation-1.conf").exists()
            assert (esp / "EFI/BOOT/BOOTAA64.EFI").exists()
            assert (esp / "EFI/nixos/kernel.efi").exists()
            if device == "asphalt":
                assert (esp / "EFI/android-devices/charger.efi").exists()
                assert not (esp / "EFI/nixos/.extra-files/EFI/android-devices/charger.efi").exists()

            disabled_esp = esp.parent / (device + "-disabled")
            initial(disabled, disabled_esp, esp.parent / (device + "-disabled-sources"))
            assert "auto-reboot" not in (disabled_esp / "loader/loader.conf").read_text()
            assert "auto-poweroff" not in (disabled_esp / "loader/loader.conf").read_text()
            assert not (disabled_esp / helper).exists()
            assert not list((disabled_esp / "loader/entries").glob("android-*.conf"))
            cases += 1
print(f"PASS {cases} native/cross initial, repeat update and enable-to-disable cases")
