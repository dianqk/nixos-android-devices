#!/usr/bin/env python3
"""Exercise the shared charging environment with the pinned U-Boot sandbox.

Usage: charger-boot.py SANDBOX_DIRECTORY OUTPUT_DIRECTORY [asphalt|polaris|aurora]
The output directory holds logs; no device or disk image is accessed.
"""
import os
from pathlib import Path
import subprocess
import sys


repo = Path(__file__).resolve().parents[1]
firmware, work = (Path(arg).resolve() for arg in sys.argv[1:3])
board = sys.argv[3] if len(sys.argv) == 4 else 'asphalt'
boards = {'asphalt': ('sm8475', 'linux-boot'), 'polaris': ('sdm845', 'system'), 'aurora': ('sm8650', 'linux-boot')}
family, esp = boards[board]
work.mkdir(parents=True, exist_ok=True)
source = (repo / f'pkgs/u-boot/{family}/{board}/{board}.env').read_text()
source += (repo / 'pkgs/u-boot/charger.env').read_text()
source = source.replace('\\\n\t', '')
entries = [line.split('=', 1) for line in source.splitlines() if line and not line.startswith('#')]
env = dict(entries)
assert len(entries) == len(env), 'Duplicate environment variables'
assert env['boot_esp'] == esp
assert '${boot_esp}' in env['boot_charger']


def quote(value):
    assert "'" not in value
    return "'" + value + "'"


def sandbox(name, commands, timeout=15, keys=None):
    result = subprocess.run(
        [str(firmware / 'u-boot'), '-d', str(firmware / 'u-boot.dtb'),
         '-c', '; '.join(commands)], cwd=work, capture_output=True,
        timeout=timeout, input=keys,
        env=os.environ | {'SDL_VIDEODRIVER': 'dummy'})
    output = (result.stdout + result.stderr).decode(errors='replace')
    (work / (name + '.log')).write_text(output)
    assert result.returncode == 0, output
    return output


# Copy the DT before changing /chosen; never alter sandbox's control tree.
setup = [
    'fdt move ${fdtcontroladdr} 1000000 10000',
    'setenv fdtcontroladdr 1000000',
    'setenv fdt_addr_r 1000000',
    'fdt rm /chosen',
    'fdt mknode / chosen',
    'setenv detect_boot_mode ' + quote(env['detect_boot_mode']),
    'setenv bootcmd ' + quote(env['bootcmd']),
    # Stop at the branch boundary, before real EFI/menu execution.
    "setenv boot_linux 'echo TEST_EFI; poweroff'",
    "setenv boot_charger 'echo TEST_CHARGER; poweroff'",
    "setenv menucmd 'echo TEST_MENU; poweroff'",
    # A previous successful match must not survive a new detection.
    'setenv charger_mode 1',
    'setenv abl_bootargs androidboot.mode=charger',
]
cases = [
    ('charger-only', 'androidboot.mode=charger', True),
    ('charger-first', 'androidboot.mode=charger androidboot.serialno=example', True),
    ('charger-last', 'rootwait androidboot.mode=charger', True),
    ('charger-middle', 'rootwait  androidboot.mode=charger  ro', True),
    ('normal-usb', 'androidboot.mode=normal androidboot.usbcontroller=a600000.usb', False),
    ('ordinary', 'androidboot.slot_suffix=_b rootwait ro init=/init', False),
    ('value-suffix', 'androidboot.mode=charger_debug', False),
    ('key-prefix', 'other.androidboot.mode=charger', False),
    ('embedded-value', 'reason=androidboot.mode=charger', False),
    ('empty', '', False),
    ('missing', None, False),
]
for name, args, charger in cases:
    prop = ('fdt rm /chosen bootargs' if args is None else
            'fdt set /chosen bootargs ' + quote(args))
    output = sandbox(name, setup + [prop, 'run detect_boot_mode',
                                    'printenv charger_mode', 'run bootcmd'])
    assert f'charger_mode={int(charger)}' in output, output
    assert ('TEST_CHARGER' in output) == charger, output
    assert ('TEST_EFI' in output) != charger, output

output = sandbox('missing-chosen', setup + ['fdt rm /chosen',
                 'run detect_boot_mode', 'printenv charger_mode', 'run bootcmd'])
assert 'charger_mode=0' in output and 'TEST_EFI' in output, output

# The actual menu command must wait indefinitely and must not fall back to EFI
# when the user exits to the shell. With no console input, 8 seconds exceeds
# both the board's bootretry and the usual EFI menu timeout.
commands = setup + [
    'setenv menucmd ' + quote(env['menucmd']),
    'setenv bootmenu_0 ' + quote(env['bootmenu_0']),
    'setenv bootretry -1',
    'run menucmd',
    'echo TEST_MENU_RETURNED',
    'poweroff',
]
proc = subprocess.Popen(
    [str(firmware / 'u-boot'), '-d', str(firmware / 'u-boot.dtb'),
     '-c', '; '.join(commands)], cwd=work, stdin=subprocess.PIPE,
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    env=os.environ | {'SDL_VIDEODRIVER': 'dummy'})
try:
    output, _ = proc.communicate(timeout=8)
except subprocess.TimeoutExpired:
    proc.kill()
    output, _ = proc.communicate()
else:
    raise AssertionError('Menu exited without user input: ' + output.decode(errors='replace'))
(work / 'menu-wait.log').write_bytes(output)
assert b'Boot NixOS' in output, output
assert b'TEST_EFI' not in output and b'TEST_MENU_RETURNED' not in output, output
assert env['menucmd'].endswith('setenv bootcmd run menucmd; bootmenu -1')
assert 'run boot_linux' in env['bootmenu_0']
assert 'run detect_boot_mode' in env['preboot']
assert '/EFI/android-devices/charger.efi' in env['boot_charger']
assert 'run boot_linux' not in env['boot_charger']
assert 'setenv bootargs; bootefi' in env['boot_charger']
assert 'poweroff; run menucmd' in env['boot_charger']
output = sandbox('menu-manual-boot', commands, keys=b'\r')
assert 'TEST_EFI' in output and 'TEST_MENU_RETURNED' not in output, output
print(f'{len(cases) + 1} boot-mode cases, indefinite menu wait and manual boot passed')

# With no SCSI disk, the actual loader must power off without invoking EFI.
output = sandbox('missing-payload', setup + [
    'setenv boot_esp ' + quote(esp),
    'setenv boot_charger ' + quote(env['boot_charger']),
    'run boot_charger', 'echo TEST_RETURNED', 'poweroff'])
assert 'Charging environment unavailable' in output, output
assert 'TEST_EFI' not in output and 'TEST_RETURNED' not in output, output
print('Missing payload requests shutdown without normal boot')
