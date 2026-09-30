#!/usr/bin/env python3
"""Root-only dummy_hcd test; refuses an existing emulator and cleans up its gadget."""
import os
from pathlib import Path
import select
import subprocess
import sys
import termios
import time

assert os.geteuid() == 0, 'Run as root on a local test host'
assert not Path('/sys/module/dummy_hcd').exists(), 'An existing USB emulator must not be disturbed'
fixture = str(Path(sys.argv[1]).resolve())
modules = ['dummy_hcd', 'usb_f_ncm', 'usb_f_acm', 'cdc_ncm', 'cdc_acm']
loaded = [m for m in modules if not Path('/sys/module', m).exists()]
process = None

def wait_for(predicate, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(.1)
    raise AssertionError('Timed out waiting for emulated USB device')

def raw(path):
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    t = termios.tcgetattr(fd)
    t[0] = t[1] = t[3] = 0
    t[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    t[4] = t[5] = termios.B115200
    t[6][termios.VMIN] = t[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, t)
    return fd

try:
    for module in modules:
        subprocess.run(['modprobe', module], check=True)
    udc = wait_for(lambda: next(iter(Path('/sys/class/udc').glob('dummy_udc.*')), None))
    for enabled in [False, True, False]:
        process = subprocess.Popen([fixture, udc.name, str(int(enabled))], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        while True:
            line = process.stdout.readline()
            assert line, f'Fixture exited before READY ({process.poll()})'
            print(line.rstrip(), flush=True)
            if line.startswith('READY '):
                break
        wait_for(lambda: (udc / 'state').read_text().strip() == 'configured')
        device = wait_for(lambda: next((p for p in Path('/sys/bus/usb/devices').glob('*')
                                       if (p/'serial').exists() and
                                       (p/'serial').read_text().strip() == 'signaller-acm-test'), None))
        interfaces = list(Path('/sys/bus/usb/devices').glob(device.name + ':*'))
        subclasses = [(p/'bInterfaceClass').read_text().strip() + ':' +
                      (p/'bInterfaceSubClass').read_text().strip() for p in interfaces]
        assert '02:0d' in subclasses, subclasses  # NCM always remains present
        assert ('02:02' in subclasses) == enabled, subclasses
        if enabled:
            host = wait_for(lambda: next((p for p in Path('/sys/class/tty').glob('ttyACM*')
                                           if str(device.resolve()) in str(p.resolve())), None))
            target = next(Path('/sys/kernel/config/usb_gadget/usb-signaller-acm-test/functions').glob('acm.*'))
            port = (target/'port_num').read_text().strip()
            a, b = raw('/dev/'+host.name), raw('/dev/ttyGS'+port)
            try:
                for sender, receiver, payload in [(a,b,b'host-to-device\n'), (b,a,b'device-to-host\n')]:
                    os.write(sender, payload)
                    received = b''
                    deadline = time.monotonic()+5
                    while len(received)<len(payload) and time.monotonic()<deadline:
                        if select.select([receiver],[],[],.2)[0]:
                            received += os.read(receiver,1024)
                    assert received == payload, (received,payload)
            finally:
                os.close(a); os.close(b)
        process.stdin.write('stop\n'); process.stdin.flush()
        out, _ = process.communicate(timeout=15)
        print(out, end='')
        assert process.returncode == 0
        process = None
        assert not Path('/sys/kernel/config/usb_gadget/usb-signaller-acm-test').exists()
        print(f'PASS ACM={enabled}: NCM, descriptors, mode detection, cleanup' + (' and bidirectional serial' if enabled else ''), flush=True)
finally:
    if process is not None and process.poll() is None:
        process.stdin.write('stop\n'); process.stdin.flush()
        process.communicate(timeout=15)
    for module in reversed(loaded):
        subprocess.run(['modprobe', '-r', module], check=True)
