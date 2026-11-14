#!/usr/bin/env python3
"""Private-bus latency and duplicate-start regression; no host hardware access.

Run: unshare -Urnm python3 tests/usb-signaller-dbus.py NATIVE_USB_SIGNALLER
"""
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time


def main():
    mapping = Path("/proc/self/uid_map").read_text().split()
    assert mapping[0] == "0" and mapping[1] != "0" and mapping[2] == "1"
    # Hide both the host system bus and all real controllers/configfs nodes.
    for target in ("/run", "/sys"):
        subprocess.run(["mount", "-t", "tmpfs", "tmpfs", target], check=True)
    Path("/run/systemd/system").mkdir(parents=True)
    connected = threading.Event()
    private = socket.socket(socket.AF_UNIX)
    private.bind("/run/systemd/private")
    private.listen(8)
    clients = []

    def hold_private_bus():
        while True:
            try:
                client, _ = private.accept()
            except OSError:
                return
            clients.append(client)
            connected.set()

    threading.Thread(target=hold_private_bus, daemon=True).start()
    Path("/run/dbus").mkdir()
    config = Path("/run/test-bus.conf")
    config.write_text('''<busconfig>
      <type>system</type><listen>unix:path=/run/dbus/system_bus_socket</listen><auth>EXTERNAL</auth>
      <policy context="default"><allow own="*"/><allow send_destination="*"/><allow receive_sender="*"/></policy>
    </busconfig>''')
    env = os.environ | {"DBUS_SYSTEM_BUS_ADDRESS": "unix:path=/run/dbus/system_bus_socket"}
    processes = []
    elapsed = {}
    with tempfile.TemporaryFile() as logs:
        try:
            bus = subprocess.Popen(["dbus-daemon", "--nofork", "--config-file=" + str(config)], env=env,
                                   stdout=logs, stderr=logs, start_new_session=True)
            processes.append(bus)
            deadline = time.monotonic() + 3
            while not Path("/run/dbus/system_bus_socket").exists():
                assert time.monotonic() < deadline
                time.sleep(0.01)
            manager = subprocess.Popen([sys.argv[1]], env=env, stdout=logs, stderr=logs, start_new_session=True)
            processes.append(manager)

            def call(method, *args, success=True):
                start = time.monotonic()
                result = subprocess.run(["busctl", "--system", "--json=short", "call", "com.meego.usb_moded",
                                         "/com/meego/usb_moded", "com.meego.usb_moded", method, *args],
                                        env=env, capture_output=True, text=True, timeout=3)
                elapsed[method if success else method + ":rejected"] = time.monotonic() - start
                assert (result.returncode == 0) == success, result.stderr
                return json.loads(result.stdout)["data"][0] if success else None

            # Wait for registration while the single worker is blocked in a child.
            deadline = time.monotonic() + 3
            while True:
                ready = subprocess.run(["busctl", "--system", "status", "com.meego.usb_moded"], env=env,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if ready.returncode == 0:
                    break
                assert time.monotonic() < deadline
                time.sleep(0.01)
            if not connected.wait(2):
                logs.seek(0)
                raise AssertionError("fixture failed to block systemctl: " + logs.read().decode())
            assert call("get_status")["busy"] == "true"
            assert "developer_mode" in call("get_modes")
            assert call("mode_request") == "unknown_mode"
            assert call("set_mode", "s", "charging_only") == "charging_only"
            call("set_mode", "s", "unsupported_mode", success=False)
            duplicate = subprocess.run([sys.argv[1]], env=env, capture_output=True, text=True, timeout=2)
            assert duplicate.returncode != 0 and "Another usb-signaller manager" in duplicate.stderr
            assert max(elapsed.values()) < 3
            print(json.dumps({"private_bus": "passed", "blocked_worker": True, "duplicate_start": "rejected",
                              "command_seconds": elapsed}, indent=2))
        finally:
            private.close()
            for client in clients:
                client.close()
            for process in reversed(processes):
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=3)


if __name__ == "__main__":
    main()
