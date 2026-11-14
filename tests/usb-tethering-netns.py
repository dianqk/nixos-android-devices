#!/usr/bin/env python3
"""Exercise evaluated nft rules inside a disposable user/network namespace.

Run: unshare -Urnm python3 tests/usb-tethering-netns.py RULES.nft
RULES.nft must wrap the usb-modes.nix rules in `table inet mobile_usb { ... }`.
"""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sharing", ROOT / "modules/mobile/usb-tethering.py")
sharing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sharing)


def run(*args, check=True):
    return subprocess.run(args, check=check, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=5)


def ns(name, *args, **kwargs):
    return run("ip", "netns", "exec", name, *args, **kwargs)


def ping(namespace, address, succeeds, *extra):
    result = ns(namespace, "ping", "-n", "-c", "1", "-W", "1", *extra, address, check=False)
    assert (result.returncode == 0) == succeeds, (namespace, address, succeeds, result.stdout, result.stderr)


def main():
    assert os.getuid() == 0
    mapping = Path("/proc/self/uid_map").read_text().split()
    assert mapping[0] == "0" and mapping[1] != "0" and mapping[2] == "1", "requires an isolated unprivileged user namespace"
    run("mount", "-t", "tmpfs", "tmpfs", "/run")
    for name, local, addr, peer in [
        ("client", "usb0", "172.16.47.1/24", "172.16.47.2/24"),
        ("wan", "wlan0", "192.0.2.1/24", "192.0.2.2/24"),
        ("lan", "lan0", "10.7.0.1/24", "10.7.0.2/24"),
    ]:
        run("ip", "netns", "add", name)
        run("ip", "link", "add", local, "type", "veth", "peer", "name", "eth0", "netns", name)
        run("ip", "addr", "add", addr, "dev", local)
        run("ip", "link", "set", local, "up")
        ns(name, "ip", "addr", "add", peer, "dev", "eth0")
        ns(name, "ip", "link", "set", "eth0", "up")
        ns(name, "ip", "link", "set", "lo", "up")
    run("ip", "route", "add", "default", "via", "192.0.2.2")
    ns("client", "ip", "route", "add", "default", "via", "172.16.47.1")
    ns("wan", "ip", "route", "add", "172.16.47.0/24", "via", "192.0.2.1")
    ns("lan", "ip", "route", "add", "172.16.47.0/24", "via", "10.7.0.1")
    ns("wan", "ip", "addr", "add", "8.8.8.8/32", "dev", "eth0")
    ns("wan", "ip", "addr", "add", "192.168.1.9/32", "dev", "eth0")
    Path("/proc/sys/net/ipv4/ip_forward").write_text("1")
    ping("client", "8.8.8.8", True)  # Prove the fixture can route before applying policy.
    run("nft", "-c", "-f", sys.argv[1])
    run("nft", "-f", sys.argv[1])
    ping("client", "8.8.8.8", False)  # Global ip_forward=1 never opens developer mode.
    sharing.set_uplink("wlan0")
    ping("client", "8.8.8.8", True)
    ping("client", "10.7.0.2", False)  # Another LAN interface is never an upstream.
    ping("client", "192.168.1.9", False)  # Nor a private destination on the allowed upstream.
    ping("wan", "172.16.47.2", False)  # Unsolicited ingress is blocked.
    ns("client", "ip", "addr", "add", "172.17.0.2/32", "dev", "eth0")
    ping("client", "8.8.8.8", False, "-I", "172.17.0.2")
    server_code = 'import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.bind(("8.8.8.8",9876)); print("ready",flush=True); b,p=s.recvfrom(64); s.sendto(p[0].encode(),p)'
    server = subprocess.Popen(["ip", "netns", "exec", "wan", sys.executable, "-u", "-c", server_code], stdout=subprocess.PIPE, text=True)
    try:
        assert server.stdout.readline().strip() == "ready"
        reply = ns("client", sys.executable, "-c", 'import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.settimeout(2); s.sendto(b"test",("8.8.8.8",9876)); print(s.recv(64).decode())')
        assert reply.stdout.strip() == "192.0.2.1", reply.stdout  # Actual masquerading.
        server.wait(timeout=3)
    finally:
        if server.poll() is None:
            server.kill()
            server.wait()
    sharing.set_uplink(None)
    ping("client", "8.8.8.8", False)
    print("nft syntax, ip_forward regression, NAT, LAN isolation, spoofing, ingress and exit cleanup: passed")


if __name__ == "__main__":
    main()
