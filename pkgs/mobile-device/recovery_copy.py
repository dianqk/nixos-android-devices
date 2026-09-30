#!/usr/bin/env python3
"""Copy a Nix closure through SSH-forwarded recovery sockets.

The device-side Nix daemon and recovery screen must already listen on their
sockets. This tool does not mount, format, switch profiles, or write boot
partitions.
"""

import json
import re
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

DEVICE_STORE = "/run/mobile-recovery/recovery.sock"
DEVICE_STATUS = "/run/mobile-recovery/status.sock"
COPY_COUNT = re.compile(r"copying (\d+) paths?\b")
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def clean(value):
    return ANSI.sub("", str(value)).replace("\t", " ").replace("\n", " ").replace("\r", " ")[:180]


class Progress:
    def __init__(self, connection):
        self.connection = connection
        self.total = 0
        self.done = 0
        self.finished_paths = 0
        self.path_bytes = 0
        self.path_total = 0
        self.copy_id = None
        self.path_id = None
        self.active_paths = set()
        self.last_send = 0.0
        self.last_path_log = 0.0

    def send(self, command, *fields):
        if self.connection is not None:
            try:
                self.connection.sendall(("\t".join([command, *map(clean, fields)]) + "\n").encode())
            except (BrokenPipeError, ConnectionResetError):
                print("Recovery status display disconnected; copy continues", file=sys.stderr)
                self.connection = None

    def report(self, force=False):
        now = time.monotonic()
        if force or now - self.last_send >= 0.25:
            self.send("progress", self.done, self.total, self.path_bytes, self.path_total)
            self.last_send = now

    def finish(self):
        # A successful nix copy is authoritative even when Nix never emits a
        # final parent progress result (observed with the Unix daemon bridge).
        self.done = self.total
        self.path_bytes = self.path_total = 0
        self.report(force=True)

    def accept(self, line):
        if not line.startswith("@nix "):
            if line.strip():
                self.send("log", line.strip())
            return
        try:
            event = json.loads(line[5:])
        except json.JSONDecodeError:
            self.send("log", line.strip())
            return
        action = event.get("action")
        kind = event.get("type")
        event_id = event.get("id")
        if action == "start" and kind == 103:
            match = COPY_COUNT.search(event.get("text", ""))
            if match:
                self.copy_id = event_id
                self.total = int(match.group(1))
                self.done = 0
                self.finished_paths = 0
                self.active_paths.clear()
                self.send("stage", "Copying Nix store")
                self.send("log", event["text"])
                self.report(force=True)
        elif action == "start" and kind == 100:
            self.path_id = event_id
            self.active_paths.add(event_id)
            self.path_bytes = self.path_total = 0
            fields = event.get("fields", [])
            if fields and time.monotonic() - self.last_path_log >= 1.0:
                self.send("log", "Copying " + str(fields[0]).rsplit("/", 1)[-1])
                self.last_path_log = time.monotonic()
        elif action == "result" and kind == 105:
            fields = event.get("fields", [])
            if len(fields) >= 2 and all(isinstance(x, int) and x >= 0 for x in fields[:2]):
                if event_id == self.copy_id:
                    self.done = max(self.finished_paths, fields[0])
                    self.total = fields[1]
                    self.report()
                elif event_id == self.path_id:
                    self.path_bytes, self.path_total = fields[:2]
                    self.report()
        elif action == "stop" and event_id in self.active_paths:
            self.active_paths.remove(event_id)
            if event_id == self.path_id:
                self.path_id = None
                self.path_bytes = self.path_total = 0
            self.finished_paths += 1
            self.done = min(self.total, max(self.done, self.finished_paths))
            self.report(force=True)
        elif action == "msg" and event.get("level", 0) <= 3:
            self.send("log", event.get("raw_msg", event.get("msg", "")))


def copy_closure(transport, system, log_path=None):
    log_path = log_path or Path(tempfile.gettempdir()) / f"mobile-recovery-copy-{transport.serial}.jsonl"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["nix", "path-info", str(system)], check=True, stdout=subprocess.DEVNULL)
    transport.shell("test", "-S", DEVICE_STORE)
    transport.shell("test", "-S", DEVICE_STATUS)
    with tempfile.TemporaryDirectory(prefix="mobile-recovery-") as directory:
        store = str(Path(directory) / "store.sock")
        status = str(Path(directory) / "status.sock")
        control = str(Path(directory) / "ssh-control")
        forwarded = False
        try:
            subprocess.run(transport.prefix[:-1] + ["-M", "-S", control, "-f", "-N",
                "-o", "ExitOnForwardFailure=yes",
                "-L", store + ":" + DEVICE_STORE,
                "-L", status + ":" + DEVICE_STATUS, transport.target], check=True)
            forwarded = True
            connection = None
            try:
                connection = socket.socket(socket.AF_UNIX)
                connection.connect(status)
                with log_path.open("w") as log:
                    progress = Progress(connection)
                    progress.send("start", "Starting Nix store copy")
                    command = ["nix", "copy", "--no-check-sigs", "--log-format", "internal-json", "--to", "unix://" + store, str(system)]
                    with subprocess.Popen(command, stderr=subprocess.PIPE, text=True, bufsize=1) as process:
                        for line in process.stderr:
                            log.write(line)
                            progress.accept(line.rstrip("\n"))
                        result = process.wait()
                    if result == 0:
                        progress.finish()
                        progress.send("done")
                        print(f"Nix store copy complete; full log: {log_path}")
                    else:
                        progress.send("error", f"nix copy exited {result}; see host log")
                        print(f"Nix store copy failed ({result}); full log: {log_path}", file=sys.stderr)
                    if result:
                        raise RuntimeError(f"Nix copy exited {result}; see {log_path}")
                    return
            finally:
                if connection is not None:
                    connection.close()
        finally:
            if forwarded:
                subprocess.run(transport.prefix[:-1] + ["-S", control, "-O", "exit", transport.target],
                               check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
