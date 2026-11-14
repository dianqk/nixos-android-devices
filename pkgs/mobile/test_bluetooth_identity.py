import importlib.util
import os
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "identity", Path(__file__).with_name("bluetooth-identity.py"))
bt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bt)
ADDRESS = bytes.fromhex("665544332202")


class Client:
    def __init__(self, configured=False, missing=2, readback=ADDRESS):
        self.configured, self.missing, self.readback = configured, missing, readback
        self.writes = []

    def indices(self, opcode):
        return (7,) if self.configured == (opcode == bt.READ_INDEX_LIST) else ()

    def request(self, opcode, index, payload=b""):
        assert index == 7
        if opcode == bt.READ_CONFIG_INFO:
            return struct.pack("<HII", 29, 2, self.missing)
        if opcode == bt.SET_PUBLIC_ADDRESS:
            self.writes.append(payload)
            self.configured = True
            return bytes(4)
        if opcode == bt.READ_INFO:
            return self.readback + bytes(11)
        raise AssertionError(opcode)


class IdentityTests(unittest.TestCase):
    def test_runtime_file_validation(self):
        with tempfile.TemporaryDirectory() as folder:
            file = Path(folder) / "identity"
            file.write_bytes(b"02:22:33:44:55:66\n")
            file.chmod(0o600)
            # The test runner need not run as root.
            real_stat = os.fstat
            def root_stat(fd):
                fields = list(real_stat(fd))
                fields[4] = 0
                return os.stat_result(fields)
            with patch.object(bt.os, "fstat", root_stat):
                self.assertEqual(bt.read_identity(file), ADDRESS)
                for data in (b"00:00:00:00:00:00", b"01:22:33:44:55:66",
                             b"02:22:33:44:55", b"02:22:33:44:55:66\n\n",
                             bytes(6), b"02:22:33:44:55:66 extra"):
                    file.write_bytes(data)
                    with self.assertRaises(bt.IdentityError):
                        bt.read_identity(file)
                file.write_bytes(b"02:22:33:44:55:66")
                file.chmod(0o644)
                with self.assertRaises(bt.IdentityError):
                    bt.read_identity(file)
                file.chmod(0o600)
                link = Path(folder) / "link"
                link.symlink_to(file)
                with self.assertRaises(OSError):
                    bt.read_identity(link)
                with self.assertRaises(bt.IdentityError):
                    bt.read_identity(folder)
            with patch.object(bt.os, "fstat", return_value=os.stat_result(
                    (0o100600, 0, 0, 1, 1000, 0, 17, 0, 0, 0))):
                with self.assertRaises(bt.IdentityError):
                    bt.read_identity(file)

    def test_only_missing_public_address_is_written(self):
        client = Client()
        bt.provision(client, 7, ADDRESS, 100)
        self.assertEqual(client.writes, [ADDRESS])
        for missing in (0, 1, 3, 4):
            client = Client(missing=missing)
            with self.assertRaises(bt.IdentityError):
                bt.provision(client, 7, ADDRESS, 100)
            self.assertEqual(client.writes, [])

    def test_configured_same_address_is_untouched(self):
        client = Client(configured=True)
        bt.provision(client, 7, ADDRESS, 100)
        self.assertEqual(client.writes, [])

    def test_configured_different_address_is_untouched(self):
        client = Client(configured=True, readback=bytes(6))
        with self.assertRaises(bt.IdentityError):
            bt.provision(client, 7, ADDRESS, 100)
        self.assertEqual(client.writes, [])

    def test_write_requires_exact_readback(self):
        client = Client(readback=bytes(6))
        with self.assertRaises(bt.IdentityError):
            bt.provision(client, 7, ADDRESS, 100)
        self.assertEqual(client.writes, [ADDRESS])

    def test_missing_controller_wait_is_bounded(self):
        client = Client()
        client.indices = lambda opcode: ()
        with self.assertRaises(bt.IdentityError):
            bt.provision(client, 7, ADDRESS, 1, clock=lambda: 1)
        self.assertEqual(client.writes, [])

    def test_async_configuration_wait_is_bounded(self):
        client = Client()
        def request(opcode, index, payload=b""):
            if opcode == bt.READ_CONFIG_INFO:
                return struct.pack("<HII", 29, 2, 2)
            if opcode == bt.SET_PUBLIC_ADDRESS:
                client.writes.append(payload)
                return bytes(4)
            raise AssertionError(opcode)
        client.request = request
        with self.assertRaises(bt.IdentityError):
            bt.provision(client, 7, ADDRESS, 1, clock=lambda: 1)
        self.assertEqual(client.writes, [ADDRESS])

    def test_controller_selection_uses_compatible_and_rejects_ambiguity(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for index, compatible in ((3, b"qcom,other\0"), (7, b"qcom,wcn6855-bt\0")):
                node = root / f"hci{index}/device/of_node"
                node.mkdir(parents=True)
                (node / "compatible").write_bytes(compatible)
            self.assertEqual(bt.controller_index("qcom,wcn6855-bt", root), 7)
            self.assertIsNone(bt.controller_index("not-present", root))
            node = root / "hci9/device/of_node"
            node.mkdir(parents=True)
            (node / "compatible").write_bytes(b"qcom,wcn6855-bt\0")
            with self.assertRaises(bt.IdentityError):
                bt.controller_index("qcom,wcn6855-bt", root)

    def test_mgmt_response_layout_status_lengths_and_deadline(self):
        class Socket:
            def __init__(self, frames):
                self.frames, self.sent = iter(frames), []
            def settimeout(self, timeout):
                assert timeout > 0
            def sendall(self, frame):
                self.sent.append(frame)
            def recv(self, size):
                return next(self.frames)
        def event(kind=1, status=0, data=b"ok", index=7):
            payload = struct.pack("<HB", bt.READ_INFO, status) + data
            return struct.pack("<HHH", kind, index, len(payload)) + payload
        sock = Socket([event(index=8), event(kind=2, data=b""), event()])
        client = bt.Management(sock, 1, clock=lambda: 0)
        self.assertEqual(client.request(bt.READ_INFO, 7), b"ok")
        self.assertEqual(sock.sent, [struct.pack("<HHH", bt.READ_INFO, 7, 0)])
        for frame in (b"", event(status=1), event()[:-1],
                      struct.pack("<HHH", 1, 7, 1) + b"x"):
            with self.assertRaises(bt.IdentityError):
                bt.Management(Socket([frame]), 1, clock=lambda: 0).request(bt.READ_INFO, 7)
        sock = Socket([])
        with self.assertRaises(bt.IdentityError):
            bt.Management(sock, 1, clock=lambda: 1).request(bt.READ_INFO, 7)
        self.assertEqual(sock.sent, [])


if __name__ == "__main__":
    unittest.main()
