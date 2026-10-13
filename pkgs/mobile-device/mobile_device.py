#!/usr/bin/env python3
"""Host-side Android and NixOS mobile maintenance tool."""

import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import time
import tomllib
import uuid

from boot_image import BOARDS, inspect_image


RECOVERY_COMMAND = "recovery"


class ToolError(Exception):
    pass


def run(argv, *, input_data=None, check=True, capture=True, timeout=None):
    try:
        result = subprocess.run(
            argv, input=input_data, stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE if capture else None, timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ToolError(f"{argv[0]}: {error}") from error
    if check and result.returncode:
        detail = (result.stderr or result.stdout or b"").decode(errors="replace").strip()
        raise ToolError(f"{' '.join(map(str, argv))}: {detail or f'exit {result.returncode}'}")
    return result


def output(argv, **kwargs):
    return run(argv, **kwargs).stdout.decode(errors="replace").strip().replace("\r", "")


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def local_file(value):
    path = Path(value).expanduser().resolve(strict=True)
    if not path.is_file():
        raise ToolError(f"Not a regular file: {path}")
    return path


def local_system(value):
    path = Path(value).expanduser().resolve(strict=True)
    if not path.is_dir() or not (path / "init").is_file() or not str(path).startswith("/nix/store/"):
        raise ToolError("Expected a built NixOS system in /nix/store with an init file")
    return path


def choose_serial(program, requested, state):
    listing = output([program, "devices"])
    devices = [fields[0] for line in listing.splitlines()
               if (fields := line.split()) and len(fields) > 1 and fields[1] == state]
    if requested:
        if devices.count(requested) != 1:
            raise ToolError(f"{program}: {requested} is not connected as {state}")
        return requested
    if len(devices) != 1:
        raise ToolError(f"{program}: select one device with --serial (found {devices})")
    return devices[0]


class Ssh:
    def __init__(self, target, ssh_config=None):
        if not target or target.startswith("-") or any(c.isspace() for c in target):
            raise ToolError("SSH requires an explicit --target HOST (or TOML target)")
        self.target = target
        self.serial = re.sub(r"[^A-Za-z0-9_.-]", "_", target)
        self.prefix = ["ssh", *(["-F", str(ssh_config)] if ssh_config else []), "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2", "-T", target]

    def command(self, command):
        return self.prefix + [command]

    def shell(self, *args, check=True, capture=True, stdin=None):
        command = shlex.join(map(str, args))
        argv = self.command(command)
        return run(argv, input_data=stdin, check=check, capture=capture)

    def script(self, command, *, check=True, capture=True, stdin=None):
        return run(self.command(command), input_data=stdin,
                   check=check, capture=capture)

    def text(self, *args):
        return self.shell(*args).stdout.decode(errors="replace").strip().replace("\r", "")

    def push(self, source, destination):
        with source.open("rb") as stream:
            process = subprocess.Popen(self.command("umask 077; cat > " + shlex.quote(destination)), stdin=stream)
            if process.wait():
                raise ToolError("SSH upload failed")
        if self.text("sha256sum", destination).split()[0] != digest(source):
            raise ToolError(f"SSH transfer checksum mismatch: {destination}")

    def temporary(self):
        directory = self.text("mktemp", "-d", "/tmp/mobile-device.XXXXXXXX")
        if not re.fullmatch(r"/tmp/mobile-device\.[A-Za-z0-9]+", directory):
            raise ToolError(f"Unexpected remote temporary directory: {directory}")
        return directory

    def recovery(self):
        if self.script("test \"$(id -u)\" = 0 && test -f /etc/mobile-ram-recovery").returncode:
            raise ToolError("SSH target is not a root RAM recovery")
        if self.shell("command", "-v", RECOVERY_COMMAND, check=False).returncode:
            raise ToolError(f"Recovery command is unavailable: {RECOVERY_COMMAND}")



def stream_file(transport, path, *remote):
    command = shlex.join(map(str, remote))
    with path.open("rb") as source:
        process = subprocess.Popen(transport.command(command), stdin=source)
        return process.wait()


def stream_export(transport, paths, command):
    if not paths:
        return transport.script(command, stdin=b"", capture=False).returncode
    exporter = subprocess.Popen(["nix-store", "--export", *paths], stdout=subprocess.PIPE)
    try:
        importer = subprocess.Popen(transport.command(command), stdin=exporter.stdout)
        exporter.stdout.close()
        imported = importer.wait()
        exported = exporter.wait()
    finally:
        if exporter.poll() is None:
            exporter.kill()
            exporter.wait()
    if exported:
        raise ToolError(f"nix-store --export failed with exit {exported}")
    return imported


def bootstrap_info(value, paths):
    directory = Path(value).expanduser().resolve(strict=True)
    if not directory.is_dir():
        raise ToolError(f"Expected a bootstrap-info directory: {directory}")
    registration = local_file(directory / "registration")
    listed = local_file(directory / "store-paths").read_text().splitlines()
    if len(listed) != len(paths) or set(listed) != set(paths):
        raise ToolError("Bootstrap registration does not describe the selected system closure")
    size_text = local_file(directory / "total-nar-size").read_text().strip()
    if not size_text.isdecimal() or int(size_text) <= 0:
        raise ToolError("Invalid bootstrap closure size")
    return registration, int(size_text)


def stream_closure_tar(transport, paths, command):
    with tempfile.TemporaryDirectory(prefix="mobile-bootstrap-") as directory:
        names = Path(directory) / "store-paths.nul"
        with names.open("wb") as listing:
            for path in paths:
                if not re.fullmatch(r"/nix/store/[a-z0-9]{32}-[^/\s]+", path):
                    raise ToolError(f"Invalid store path in closure: {path}")
                listing.write(path.lstrip("/").encode() + b"\0")
        exporter = subprocess.Popen(
            ["tar", "--create", "--file=-", "--directory=/", "--null",
             "--files-from", str(names), "--hard-dereference", "--numeric-owner"],
            stdout=subprocess.PIPE,
        )
        try:
            importer = subprocess.Popen(transport.command(command), stdin=exporter.stdout)
            exporter.stdout.close()
            imported = importer.wait()
            exported = exporter.wait()
        finally:
            if exporter.poll() is None:
                exporter.kill()
                exporter.wait()
        if exported:
            raise ToolError(f"tar export failed with exit {exported}")
        return imported


def fastboot_var(serial, name):
    result = run(["fastboot", "-s", serial, "getvar", name], timeout=30)
    text = (result.stdout + result.stderr).decode(errors="replace")
    values = re.findall(r"^(?:\(bootloader\)\s*)?" + re.escape(name) + r":\s*(\S+)\s*$",
                        text, re.MULTILINE)
    if len(values) != 1:
        raise ToolError(f"Cannot verify fastboot {name}")
    return values[0]


def fastboot_modelname(serial):
    result = run(["fastboot", "-s", serial, "getvar", "modelname"], check=False, timeout=30)
    text = (result.stdout + result.stderr).decode(errors="replace")
    values = re.findall(r"^(?:\(bootloader\)\s*)?modelname:[ \t]*([^\r\n]*)$",
                        text, re.MULTILINE)
    if len(values) == 1 and not result.returncode:
        return values[0].strip() or None
    if (not values and not re.search(r"(?im)^(?:\(bootloader\)\s*)?modelname\b", text)
            and result.returncode and re.search(
            r"FAILED \(remote: ['\"](?:GetVar Variable Not found|Variable not found|unknown variable)['\"]\)",
            text, re.IGNORECASE)):
        return None
    raise ToolError("Cannot verify fastboot modelname")


def fastboot_identity(args, board, serial, product):
    path = getattr(args, "device_identity", None)
    if not path:
        return False
    if not getattr(args, "serial_explicit", False):
        raise ToolError("A device identity record requires an explicit --serial")
    def unique_fields(pairs):
        fields = dict(pairs)
        if len(fields) != len(pairs):
            raise ValueError("duplicate identity fields")
        return fields
    try:
        with local_file(path).open("rb") as stream:
            blob = stream.read(16385)
        if len(blob) > 16384:
            raise ValueError("record is too large")
        record = json.loads(blob, object_pairs_hook=unique_fields)
        fields = {"version", "serial", "product", "compatible", "source", "collected_at", "boot_id"}
        if not isinstance(record, dict) or set(record) != fields or type(record["version"]) is not int or record["version"] != 1:
            raise ValueError("unsupported identity record")
        if any(not isinstance(record[key], str) or not record[key] for key in fields - {"version", "compatible"}):
            raise ValueError("invalid identity fields")
        compatible = record["compatible"]
        if not isinstance(compatible, list) or not compatible or any(not isinstance(c, str) or not c for c in compatible):
            raise ValueError("invalid compatible list")
        if record["source"] != "nixos-ram-recovery":
            raise ValueError("identity must come from an observed RAM recovery")
        if datetime.fromisoformat(record["collected_at"]).tzinfo is None:
            raise ValueError("collection time requires a timezone")
        uuid.UUID(record["boot_id"])
    except (OSError, ValueError, TypeError, KeyError) as error:
        raise ToolError(f"Invalid device identity record: {error}") from error
    if record["serial"] != serial or fastboot_var(serial, "serialno") != serial:
        raise ToolError("Device identity serial does not match fastboot")
    if record["product"] != product:
        raise ToolError("Device identity product does not match fastboot")
    if {BOARDS[c] for c in compatible if c in BOARDS} != {board}:
        raise ToolError("Device identity compatible does not match the image")
    # SoC product names need an independently observed, explicitly bound board.
    if (board, product) != ("asphalt", "taro") or "lenovo,asphalt" not in compatible:
        raise ToolError("This board/product identity supplement is unsupported")
    print(f"Observed RAM recovery identity: {record['serial']}, {record['collected_at']}, boot {record['boot_id']}")
    return True


def fastboot_erase(args):
    if (getattr(args, "device", None), args.partition) != ("asphalt", "dtbo_b"):
        raise ToolError("Erase requires --device asphalt and --partition dtbo_b")
    if args.image is not None:
        raise ToolError("Erase does not accept an image")
    if not getattr(args, "serial_explicit", False):
        raise ToolError("Erase requires an explicit --serial")
    serial = choose_serial("fastboot", args.serial, "fastboot")
    product = fastboot_var(serial, "product").lower()
    if product != "taro":
        raise ToolError("Asphalt DTBO erase requires the verified taro/TB320FC OEM identity")
    # Validate any supplied record; it cannot replace the required live model.
    fastboot_identity(args, "asphalt", serial, product)
    if fastboot_modelname(serial) != "TB320FC":
        raise ToolError("Asphalt DTBO erase requires live fastboot modelname TB320FC")
    if fastboot_var(serial, "serialno") != serial:
        raise ToolError("OEM model identity serial does not match fastboot")
    if fastboot_var(serial, "current-slot").removeprefix("_") != "b":
        raise ToolError("Select slot B explicitly before erasing dtbo_b; slot A must be preserved")
    capacity = fastboot_var(serial, "partition-size:dtbo_b")
    if not re.fullmatch(r"(?:0[xX][0-9a-fA-F]+|[0-9]+)", capacity):
        raise ToolError("Invalid fastboot partition size")
    if int(capacity, 16 if capacity.lower().startswith("0x") else 10) != 25165824:
        raise ToolError("Unexpected Asphalt dtbo_b capacity")
    operation = ["fastboot", "-s", serial, "erase", "dtbo_b"]
    print(shlex.join(operation))
    print(f"Verified Asphalt DTBO erase: product {product}, model TB320FC, serial {serial}, slot B, 25165824 bytes")
    if args.execute:
        run(operation, capture=False, timeout=900)
    else:
        print("Check only; add --execute to send the fastboot command.")


def fastboot(args):
    if args.operation == "erase":
        return fastboot_erase(args)
    if getattr(args, "device", None) is not None or args.partition == "dtbo_b":
        raise ToolError("Use fastboot erase --device asphalt --partition dtbo_b for Asphalt DTBO")
    if not args.image:
        raise ToolError("Fastboot boot and flash require an image")
    image = local_file(args.image)
    board, recovery = inspect_image(image.read_bytes())
    serial = choose_serial("fastboot", args.serial, "fastboot")
    product = fastboot_var(serial, "product").lower()
    products = {"clover": {"clover"}, "polaris": {"polaris"},
                "aurora": {"aurora"}, "sheng": {"sheng"}, "asphalt": {"asphalt", "tb320fc"}}
    identity = fastboot_identity(args, board, serial, product)
    if (board, product) == ("asphalt", "taro"):
        model = fastboot_modelname(serial)
        if model is not None and model != "TB320FC":
            raise ToolError(f"Asphalt requires fastboot modelname TB320FC, received {model}")
        if model == "TB320FC":
            if not getattr(args, "serial_explicit", False):
                raise ToolError("The OEM model identity requires an explicit --serial")
            if fastboot_var(serial, "serialno") != serial:
                raise ToolError("OEM model identity serial does not match fastboot")
            print(f"Verified OEM model identity: {model}, serial {serial}")
            identity = True
    if product not in products[board] and not identity:
        raise ToolError(f"Image is for {board}, connected fastboot product is {product}")
    ab = board in ("asphalt", "sheng", "aurora")
    if ab and fastboot_var(serial, "current-slot").removeprefix("_") != "b":
        raise ToolError("Select slot B explicitly before using this image; slot A must be preserved")
    operation = ["fastboot", "-s", serial, args.operation]
    if args.operation == "flash":
        expected = ("recovery" if recovery else "boot") + ("_b" if ab else "")
        if args.partition != expected:
            raise ToolError(f"This {board} image may only be flashed to {expected}")
        capacity = fastboot_var(serial, "partition-size:" + args.partition)
        if not re.fullmatch(r"(?:0[xX][0-9a-fA-F]+|[0-9]+)", capacity):
            raise ToolError("Invalid fastboot partition size")
        size = int(capacity, 16 if capacity.lower().startswith("0x") else 10)
        if image.stat().st_size > size or size <= 0:
            raise ToolError("Image does not fit the target partition")
        operation.append(args.partition)
    operation.append(str(image))
    print(shlex.join(operation))
    role = "RAM recovery" if recovery else "boot"
    print(f"Verified {board} {role} image and product {product}")
    print(f"Image: {image.stat().st_size} bytes, SHA-256 {digest(image)}")
    if args.execute:
        run(operation, capture=False, timeout=900)
    else:
        print("Check only; add --execute to send the fastboot command.")


def wait_recovery(transport, command, expected, *, timeout=900):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = transport.shell(RECOVERY_COMMAND, *command, check=False)
        message = (result.stdout + result.stderr).decode(errors="replace").strip().replace("\r", "")
        if result.returncode == 0:
            if expected is None or expected(message):
                return message
            raise ToolError(f"Unexpected recovery result: {message}")
        if "Another recovery storage or boot action is running" not in message:
            raise ToolError(f"Recovery operation failed: {message}")
        time.sleep(5)
    raise ToolError("Timed out waiting for recovery operation")


def closure_manifest(system):
    paths = sorted(set(output(["nix-store", "--query", "--requisites", str(system)]).splitlines()))
    if str(system) not in paths:
        raise ToolError("Nix closure does not contain the selected system")
    lines = []
    for path in paths:
        nar_hash = output(["nix-store", "--query", "--hash", path])
        if not nar_hash.startswith("sha256:"):
            raise ToolError(f"Unexpected NAR hash for {path}")
        lines.append(f"{nar_hash} {path}\n")
    return paths, "".join(lines).encode()


def recovery_daemon(transport):
    """Require the Rust recovery daemon; every supported recovery runs it."""
    probe = transport.shell("cat", "/etc/mobile-recovery-protocol", check=False)
    if probe.returncode or not probe.stdout.strip():
        raise ToolError("Recovery does not run the Rust recovery daemon; boot a current recovery image")
    if probe.stdout.strip() != b"1":
        raise ToolError("Unsupported recovery daemon protocol; update host tools")
    return True


def daemon_submit(transport, arguments):
    response = json.loads(transport.text(RECOVERY_COMMAND, "submit", *arguments))
    task = response.get("snapshot", {}).get("task", {})
    if response.get("version") != 1 or response.get("error") or not isinstance(task.get("id"), int) or not response.get("token"):
        raise ToolError("Invalid daemon submission response")
    return task["id"], shlex.join([RECOVERY_COMMAND, "input", str(task["id"]), response["token"]])


def daemon_wait(transport, task_id, *, timeout=3600):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        state = json.loads(transport.text(RECOVERY_COMMAND, "task", str(task_id)))
        task = state.get("task", {})
        if task.get("id") != task_id:
            raise ToolError("Recovery returned another task identity")
        if not task.get("active", True):
            if task.get("error"):
                raise ToolError(f"Recovery task {task_id} failed: {task['error']}")
            if not isinstance(task.get("result"), str):
                raise ToolError("Recovery task has no verified result")
            print(task["result"])
            return
        time.sleep(2)
    raise ToolError(f"Task {task_id} is still active; reconnect with recovery task {task_id}")


def recovery_deploy(args, transport):
    transport.recovery()
    system = local_system(args.system)
    paths, manifest = closure_manifest(system)
    with tempfile.TemporaryDirectory(prefix="mobile-device-") as directory:
        source = Path(directory) / "manifest"
        source.write_bytes(manifest)
        remote = transport.temporary()
        remote_manifest = remote + "/manifest"
        writer_running = False
        try:
            transport.push(source, remote_manifest)
            missing = sorted(set(transport.text(RECOVERY_COMMAND, "deploy-query", remote_manifest, system).splitlines()))
            if any(path not in paths for path in missing):
                raise ToolError("Recovery requested a path outside the selected closure")
            print(f"Closure: {len(paths)} paths; {len(missing)} missing on userdata")
            if not args.execute:
                print("Query only; add --execute to import and select the system.")
                return
            recovery_daemon(transport)
            task_id, command = daemon_submit(transport, ["deploy-offline", remote_manifest, str(system), str(len(missing)), "--confirm"])
            writer_running = True
            stream_export(transport, missing, command)
            daemon_wait(transport, task_id)
            writer_running = False
        finally:
            if writer_running:
                print(f"Recovery may still be using deployment inputs: {remote}; inspect its result before retrying.")
            else:
                transport.shell("rm", "-rf", remote, check=False)


def recovery_format_root(args, transport):
    transport.recovery()
    transport.shell(RECOVERY_COMMAND, "format-root", "--check", capture=False)
    if args.execute:
        transport.shell(RECOVERY_COMMAND, "format-root", "--confirm", capture=False)


def recovery_install_initial(args, transport):
    transport.recovery()
    system = local_system(args.system)
    device = transport.text("cat", "/etc/mobile-ram-recovery")
    if not (system / "mobile-efi").is_file() or (system / "mobile-device").read_text().strip() != device:
        raise ToolError("Initial system does not match the recovery device or lacks EFI support")
    if not (system / "mobile-boot.img").is_file():
        raise ToolError("Initial system lacks its matching U-Boot image")
    paths, manifest = closure_manifest(system)
    registration, size = bootstrap_info(args.bootstrap_info, paths)
    resume = getattr(args, "resume", False)
    recovery_daemon(transport)
    with tempfile.TemporaryDirectory(prefix="mobile-device-") as directory:
        source = Path(directory) / "manifest"
        source.write_bytes(manifest)
        remote = transport.temporary()
        remote_manifest = remote + "/manifest"
        remote_registration = remote + "/registration"
        writer_running = False
        try:
            transport.push(source, remote_manifest)
            transport.push(registration, remote_registration)
            arguments = [RECOVERY_COMMAND, "install-initial", remote_manifest,
                         remote_registration, str(system), str(size)]
            transport.shell(*arguments, "--resume-check" if resume else "--check", capture=False)
            if not args.execute:
                print("Check only; add --execute to install or resume the system closure.")
                return
            if resume:
                writer_running = True
                transport.shell(*arguments, "--resume-confirm", capture=False)
                writer_running = False
                return
            task_id, command = daemon_submit(transport, [*arguments[1:], "--confirm"])
            writer_running = True
            stream_closure_tar(transport, paths, command)
            daemon_wait(transport, task_id)
            writer_running = False
        finally:
            if writer_running:
                print(f"Recovery may still be installing from {remote}; query the recovery task before retrying.")
            else:
                transport.shell("rm", "-rf", remote, check=False)


def recovery_command(args, transport):
    transport.recovery()
    if args.command_action == "status":
        print(transport.text(RECOVERY_COMMAND, "status"))
    elif args.command_action == "reboot":
        if args.execute:
            result = transport.shell(RECOVERY_COMMAND, "reboot-" + args.destination,
                               "--confirm", check=False)
            message = (result.stdout + result.stderr).decode(errors="replace").strip()
            if message:
                print(message)
            acknowledgements = {"Rebooting.", f"Rebooting with argument '{args.destination}'."}
            if result.returncode and not acknowledgements.intersection(message.splitlines()):
                raise ToolError("Recovery reboot command failed or SSH disconnected before acknowledgement")
        else:
            print(f"Check only: {RECOVERY_COMMAND} reboot-{args.destination} --confirm")


def recovery_install_image(args, transport):
    transport.recovery()
    image = local_file(args.image)
    remote = transport.temporary()
    try:
        remote_image = remote + "/image"
        recovery_daemon(transport)
        operations = {"/dev/disk/by-partlabel/boot_b": "update-firmware",
                      "/dev/disk/by-partlabel/recovery_b": "update-recovery",
                      "/dev/disk/by-partlabel/boot": "update-firmware",
                      "/dev/disk/by-partlabel/recovery": "update-recovery"}
        operation = operations.get(args.partition)
        if operation is None:
            raise ToolError("Image updates require the boot or recovery PARTLABEL path of this device")
        transport.push(image, remote_image)
        if transport.text("sha256sum", remote_image).split()[0] != digest(image):
            raise ToolError("Uploaded image checksum mismatch")
        transport.shell(RECOVERY_COMMAND, operation, remote_image, "--check", capture=False)
        if args.execute:
            transport.shell(RECOVERY_COMMAND, operation, remote_image, "--confirm", capture=False)
    finally:
        transport.shell("rm", "-rf", remote, check=False)


def ssh_command(target, *args, stdin=None, capture=True):
    return run(["ssh", "-o", "BatchMode=yes", target, shlex.join(map(str, args))],
               input_data=stdin, capture=capture)


def system_script(args):
    source = local_file(args.script)
    unit = args.unit
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", unit):
        raise ToolError("Invalid systemd unit name")
    suffix = [] if args.execute else ["--check"]
    if not args.target:
        raise ToolError("SSH script requires --target")
    remote = ssh_command(args.target, "sudo", "-n", "mktemp", "-d", "/run/mobile-device.XXXXXXXX").stdout.decode().strip()
    if not re.fullmatch(r"/run/mobile-device\.[A-Za-z0-9]+", remote):
        raise ToolError("Unexpected SSH temporary directory")
    completed = False
    try:
        ssh_command(args.target, "sudo", "-n", "tee", remote + "/script.sh", stdin=source.read_bytes())
        service = ["systemd-run", f"--unit={unit}", "--service-type=exec", "--wait",
                   "--collect", "--setenv=PATH=/run/current-system/sw/bin:/run/wrappers/bin",
                   "bash", remote + "/script.sh", *suffix]
        ssh_command(args.target, "sudo", "-n", *service, capture=False)
        ssh_command(args.target, "sudo", "-n", "journalctl", "-u", unit + ".service",
                    "-n", "35", "--no-pager", capture=False)
        completed = True
    finally:
        if completed:
            ssh_command(args.target, "sudo", "-n", "rm", "-rf", remote)
        else:
            print(f"Inspect the device unit before removing {remote}", file=sys.stderr)


def parser_for_cli():
    parser = argparse.ArgumentParser(prog="mobile-device", description=__doc__)
    parser.add_argument("--serial",
                        help="fastboot serial; defaults to ANDROID_SERIAL or the sole connected device")
    parser.add_argument("--config", type=Path, help="optional TOML defaults for one device")
    commands = parser.add_subparsers(dest="mode", required=True)

    bootloader = commands.add_parser("fastboot", help="boot/flash an image or erase supported Asphalt DTBO")
    bootloader.add_argument("operation", choices=["boot", "flash", "erase"])
    bootloader.add_argument("image", nargs="?")
    bootloader.add_argument("--partition", help="partition name for flash or supported erase")
    bootloader.add_argument("--execute", action="store_true")
    bootloader.add_argument("--device", choices=["asphalt"],
                            help="explicit board for Asphalt dtbo_b erase only")
    bootloader.add_argument("--device-identity", type=Path,
                            help="observed RAM recovery identity record for supported OEM SoC product names")

    recovery = commands.add_parser("recovery", help="interact with a running RAM recovery")
    recovery.add_argument("--target", help="root SSH destination or configured alias")
    recovery.add_argument("--ssh-config", type=Path, help="explicit SSH configuration (including pinned recovery host key)")
    actions = recovery.add_subparsers(dest="action", required=True)
    for name in ("status", "reboot"):
        action = actions.add_parser(name)
        if name == "reboot":
            action.add_argument("destination", choices=["system", "recovery", "bootloader"])
            action.add_argument("--execute", action="store_true")
    for name in ("mount", "unmount", "target-status", "shell", "push", "pull", "exec", "rebuild"):
        action = actions.add_parser(name)
        if name == "mount":
            action.add_argument("--rw", action="store_true", help="explicit read-write mount; default read-only")
        if name in ("push", "pull"):
            action.add_argument("source")
            action.add_argument("destination")
        if name in ("exec", "rebuild"):
            action.add_argument("arguments", nargs=argparse.REMAINDER)
    prepare = actions.add_parser("prepare-boot", help="prepare the physical FAT boot filesystem in RAM recovery")
    prepare.add_argument("--execute", action="store_true")
    deploy = actions.add_parser("deploy", help="query or deploy a NixOS system from recovery")
    deploy.add_argument("system")
    deploy.add_argument("--execute", action="store_true")
    format_linux = actions.add_parser("format-root", help="explicitly format the device's Linux root partition")
    format_linux.add_argument("--execute", action="store_true")
    initial = actions.add_parser("install-initial", help="stream a closure to an empty root and install its boot image")
    initial.add_argument("system")
    initial.add_argument("--bootstrap-info", required=True, help="matching flake bootstrap-info output")
    initial.add_argument("--execute", action="store_true")
    initial.add_argument("--resume", action="store_true", help="resume EFI finalization of the same fully transferred, registered system; reverify all contents")
    image = actions.add_parser("install-image", help="write a checked firmware or recovery image from recovery")
    image.add_argument("image")
    image.add_argument("--partition", help="target /dev/disk/by-partlabel path (boot[_b] or recovery[_b])")
    image.add_argument("--execute", action="store_true")

    system = commands.add_parser("system", help="interact with a running NixOS mobile system")
    system.add_argument("--via", choices=["ssh"], default="ssh")
    system.add_argument("--target", help="SSH target when --via ssh")
    system_actions = system.add_subparsers(dest="action", required=True)
    script = system_actions.add_parser("script", help="run a device-specific script under systemd")
    script.add_argument("script")
    script.add_argument("--unit", default="mobile-device-script")
    script.add_argument("--execute", action="store_true")
    return parser


def main(argv=None):
    parser = parser_for_cli()
    args = parser.parse_args(argv)
    args.serial_explicit = bool(args.serial)
    if args.config:
        try:
            profile = tomllib.loads(args.config.read_text())
        except (OSError, tomllib.TOMLDecodeError) as error:
            parser.error(f"Cannot read device config: {error}")
        allowed = {"serial", "target", "ssh_config", "partition"}
        if not isinstance(profile, dict) or any(key not in allowed or not isinstance(value, str)
                                                   for key, value in profile.items()):
            parser.error("Device config must contain only supported string defaults")
        for key, value in profile.items():
            if hasattr(args, key) and not getattr(args, key):
                setattr(args, key, value)
    if not args.serial:
        args.serial = os.environ.get("ANDROID_SERIAL")
    if args.mode == "fastboot":
        if args.operation == "erase":
            if args.image is not None or args.device != "asphalt" or args.partition != "dtbo_b" or not args.serial_explicit:
                parser.error("fastboot erase requires explicit --serial, --device asphalt, --partition dtbo_b and no image")
        elif not args.image:
            parser.error("fastboot boot and flash require an image")
        elif args.device is not None or args.partition == "dtbo_b":
            parser.error("Use fastboot erase --device asphalt --partition dtbo_b for Asphalt DTBO")
        if args.operation == "flash" and not args.partition:
            parser.error("fastboot flash requires --partition")
        if args.operation == "boot" and args.partition:
            parser.error("fastboot boot has no partition")
    if args.mode == "recovery":
        required = {"deploy": [], "install-initial": [],
                    "install-image": ["partition"]}.get(args.action, [])
        for field in required:
            if not getattr(args, field):
                parser.error(f"recovery {args.action} requires --{field.replace('_', '-')}")
    try:
        if args.mode == "fastboot":
            fastboot(args)
        elif args.mode == "system":
            system_script(args)
        else:
            transport = Ssh(args.target, args.ssh_config)
            if args.action in ("mount", "unmount", "target-status", "shell", "push", "pull", "exec", "rebuild"):
                transport.recovery()
                if args.action == "mount":
                    transport.shell(RECOVERY_COMMAND, "mount-target", "--rw" if args.rw else "--ro", capture=False)
                elif args.action in ("unmount", "target-status"):
                    transport.shell(RECOVERY_COMMAND, "unmount-target" if args.action == "unmount" else "target-status", capture=False)
                elif args.action == "shell":
                    recovery_daemon(transport)
                    command = [*transport.prefix[:-2], "-tt", transport.target,
                               shlex.join([RECOVERY_COMMAND, "shell"])]
                    run(command, capture=False)
                elif args.action == "exec":
                    if not args.arguments:
                        raise ToolError("exec requires a command")
                    transport.shell(*args.arguments, capture=False)
                elif args.action == "rebuild":
                    if not args.arguments or args.arguments[0] != "boot":
                        raise ToolError("Offline recovery rebuild only supports boot")
                    transport.shell(RECOVERY_COMMAND, "rebuild", *args.arguments, capture=False)
                elif args.action == "push":
                    transport.push(local_file(args.source), args.destination)
                else:
                    destination = Path(args.destination)
                    with destination.open("xb") as stream:
                        process = subprocess.Popen(transport.command(shlex.join(["cat", args.source])), stdout=stream)
                        if process.wait():
                            raise ToolError("SSH download failed; local file is incomplete")
                    if digest(destination) != transport.text("sha256sum", args.source).split()[0]:
                        raise ToolError("SSH download checksum mismatch")
            elif args.action == "prepare-boot":
                transport.recovery()
                transport.shell(RECOVERY_COMMAND, "prepare-boot", "--confirm" if args.execute else "--check", capture=False)
            elif args.action == "deploy":
                recovery_deploy(args, transport)
            elif args.action == "format-root":
                recovery_format_root(args, transport)
            elif args.action == "install-initial":
                recovery_install_initial(args, transport)
            elif args.action == "install-image":
                recovery_install_image(args, transport)
            else:
                args.command_action = args.action
                recovery_command(args, transport)
        return 0
    except (ToolError, OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"mobile-device: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
