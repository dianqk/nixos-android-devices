#!/usr/bin/env python3
"""Exercise the installed care script with fake battery sysfs attributes."""
from pathlib import Path
import subprocess
import tempfile

script = Path(__file__).resolve().parents[2] / 'modules/devices/dodge/wireless-care.sh'
with tempfile.TemporaryDirectory() as tmp:
    battery = Path(tmp)
    hold = battery / 'wireless_care_hold'
    voltage = battery / 'wireless_voltage_max'
    for previous, sample, expected in [
        (0, '4299999', 0), (0, '4300000', 1), (1, '4270000', 1),
        (1, '4250000', 1), (0, '', 1), (0, 'bad', 1), (0, None, 1),
        (1, '4200000', 1), (1, '4400000', 1),
    ]:
        hold.write_text(f'{previous}\n')
        if sample is None:
            voltage.unlink(missing_ok=True)
        else:
            voltage.write_text(sample + '\n')
        subprocess.run(['bash', '-eu', str(script), str(battery), '4300000', '4250000', 'once'], check=True)
        assert hold.read_text() == f'{expected}\n', (previous, sample)
print('care policy: fresh thresholds, hysteresis, sticky error hold and fake sysfs passed')

# Exercise the exact stateful decision with a fake monotonic clock, without waiting.
prefix = script.read_text().split('while :; do', 1)[0]
subprocess.run(['bash', '-eu', '-c', prefix + r"""
care_decide 100 0 4350000; [ "$hold" = 1 ]
care_decide 101 1 4300000; [ "$hold" = 1 ]
care_decide 129 1 4300000; [ "$hold" = 1 ]
care_decide 130 1 4300000; [ "$hold" = 0 ]
held_since=
care_decide 200 1 4200000; [ "$hold" = 1 ]
care_decide 230 1 4200000; [ "$hold" = 0 ]
care_decide 240 0 bad; [ "$hold" = 1 ]
care_decide 269 1 4200000; [ "$hold" = 1 ]
care_decide 270 1 4200000; [ "$hold" = 0 ]
""", 'test', '/unused', '4350000', '4300000', 'once'], check=True)
print('care policy: monotonic30s hold, inherited hold and error-hold timing passed')
