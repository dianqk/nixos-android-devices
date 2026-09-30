#!/usr/bin/env python3
"""Validate the production layout filter with recognized userdata GPT types."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

FILTER = Path(__file__).resolve().parents[1] / "devices/ufs-linux-layout.jq"
LINUX = "0FC63DAF-8483-4772-8E79-3D69D8477DE4"
ANDROID = "1B81E7E6-F50D-419B-A739-2AEEF8DA3335"
LAYOUT = {"partitiontable": {
    "label": "gpt", "device": "/dev/sda", "sectorsize": 4096, "lastlba": 128584698,
    "partitions": [
        {"node": "/dev/sda29", "name": "userdata", "type": LINUX, "start": 3094784, "size": 62505728},
        {"node": "/dev/sda30", "name": "linux", "type": LINUX, "start": 65600512, "size": 62721792},
        {"node": "/dev/sda31", "name": "linux-boot", "type": "C12A7328-F81F-11D2-BA4B-00A0C93EC93B", "start": 128322304, "size": 262144},
    ],
}}


class Layout(unittest.TestCase):
    def check(self, layout, valid, esp_bytes=1073741824):
        result = subprocess.run(["jq", "-e", "--arg", "disk", "/dev/sda", "--arg", "node", "/dev/sda30",
                                 "--argjson", "espBytes", str(esp_bytes), "-f", str(FILTER)], input=json.dumps(layout), text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, valid, result.stderr)

    def test_both_known_userdata_types(self):
        for kind in (LINUX, ANDROID, LINUX.lower()):
            data = copy.deepcopy(LAYOUT)
            data["partitiontable"]["partitions"][0]["type"] = kind
            self.check(data, True)

    def test_invalid_partition_identity_and_overlap(self):
        for index, key, value in ((0, "name", "super"), (0, "type", "unknown"),
                                  (0, "size", 125000000), (1, "name", "userdata"),
                                  (1, "node", "/dev/sda31"), (1, "type", ANDROID),
                                  (1, "size", 62984186), (2, "size", 262143), (2, "type", LINUX), (2, "start", 128322303)):
            with self.subTest(index=index, key=key):
                data = copy.deepcopy(LAYOUT)
                data["partitiontable"]["partitions"][index][key] = value
                self.check(data, False)

    def test_configured_esp_size_and_order(self):
        data = copy.deepcopy(LAYOUT)
        data["partitiontable"]["partitions"][-1]["size"] = 131072
        self.check(data, False)
        self.check(data, True, 536870912)
        self.check(data, True, 0)
        # GPT entry order and partition numbers are not storage identity.
        data["partitiontable"]["partitions"].reverse()
        self.check(data, True, 0)
        # A duplicated role or overlapping unrelated partition remains unsafe.
        data["partitiontable"]["partitions"].append(copy.deepcopy(data["partitiontable"]["partitions"][0]))
        self.check(data, False, 0)

    def test_wrong_disk_or_geometry(self):
        for key, value in (("device", "/dev/sdb"), ("label", "dos"), ("sectorsize", 512)):
            data = copy.deepcopy(LAYOUT)
            data["partitiontable"][key] = value
            self.check(data, False)


if __name__ == "__main__":
    unittest.main()
