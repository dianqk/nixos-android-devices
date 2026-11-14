#!/usr/bin/env python3
"""Unicorn auth integration: run the pinned upstream VDM implementation on a fake device."""
import argparse
import errno
import hashlib
import hmac
import importlib.util
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch, Mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("unicorn_auth", ROOT / "pkgs/unicorn/mipps-auth.py")
auth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auth)
UPSTREAM = None


class FakeDevice:
    root = Path("/fake/xiaomi")

    def __init__(self, upstream):
        self.upstream = upstream
        self.token = ("adapter", 1)
        self.values = {"adapter_svid": "00002717", "pdo2": "12345678", "adapter_id": "11223344",
                       "authentic": "1", "pd_verifed": "1", "request_vdm_cmd": "9,Null"}
        self.writes = []
        self.bad_gauge = False
        self.bad_adapter = False
        self.detach_on = None
        self.blank = 0
        self.timeout = False

    def session(self):
        return self.token

    def blank_state(self):
        return self.blank

    def read(self, name):
        if self.detach_on == name:
            self.token = ("new-adapter", 2)
        return self.values[name]

    def write(self, name, value):
        self.writes.append((name, str(value)))
        self.values[name] = str(value)
        if name == "verify_digest":
            digest = hmac.new(bytes.fromhex(self.upstream.FG_KEYS[0]), bytes.fromhex(value), hashlib.sha256).hexdigest()
            self.values[name] = "0" * 64 if self.bad_gauge else digest
        elif name == "request_vdm_cmd":
            cmd, payload = value.split(",")
            if self.timeout:
                raise TimeoutError("GLINK timeout")
            if cmd == "4":
                self.seed_index = self.upstream.SEEDS.index(payload)
            if cmd == "5":
                digest = hmac.new(bytes.fromhex(self.upstream.KEYS[self.seed_index]),
                                  bytes.fromhex(payload + self.values["adapter_id"]), hashlib.sha256).hexdigest()
                self.values[name] = "5," + ("0" * 32 if self.bad_adapter else digest[:32])
            else:
                self.values[name] = f"{cmd},Null"


class AuthenticationTests(unittest.TestCase):
    def setUp(self):
        self.upstream = auth.load_upstream(UPSTREAM)
        # Exercise the upstream real send_vdm/wait_state functions without hardware delays.
        self.clock = patch.object(self.upstream.send_vdm.__globals__["time"], "sleep")
        self.clock.start()
        self.addCleanup(self.clock.stop)
        self.device = FakeDevice(self.upstream)

    def run_auth(self):
        auth.authenticate(self.device, self.upstream, self.device.session(), sleep=lambda _: None)

    def test_single_gauge_and_valid_adapter(self):
        self.run_auth()
        self.assertEqual(self.device.values["authentic"], "1")
        self.assertEqual(self.device.values["pd_verifed"], "1")
        self.assertEqual(self.device.values["verify_process"], "0")
        self.assertEqual(self.device.values["sport_mode"], "0")
        names = [n for n, _ in self.device.writes]
        self.assertNotIn("slave_authentic", names)
        self.assertNotIn("verify_slave_flag", names)
        self.assertNotIn("data_role", names)
        digest = next(v for n, v in self.device.writes if n == "verify_digest")
        self.assertEqual(len(digest), 64)
        self.assertLess(names.index("verify_digest"), self.device.writes.index(("authentic", "1")))

    def test_unknown_svid_discovery_requires_explicit_opt_in(self):
        self.device.values["adapter_svid"] = "00000000"
        def discover(token):
            self.device.values["adapter_svid"] = "00002717"
            return token
        self.device.discover_xiaomi = discover
        with self.assertRaises(auth.UnsupportedAdapter):
            self.run_auth()
        auth.authenticate(self.device, self.upstream, self.device.session(),
                          sleep=lambda _: None, allow_data_role_swap=True)
        self.assertEqual(self.device.values["pd_verifed"], "1")

    def test_success_receipt_avoids_reauthentication_after_service_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            receipt = Path(directory) / "verified.json"
            first = auth.Controller(receipt=receipt)
            first.step(self.device, self.upstream, 0)
            self.assertTrue(auth.has_verified_session(receipt, self.device.session()))
            count = sum(n == "verify_digest" for n, _ in self.device.writes)
            restarted = auth.Controller(receipt=receipt)
            restarted.step(self.device, self.upstream, 2)
            self.assertTrue(restarted.authenticated)
            self.assertEqual(sum(n == "verify_digest" for n, _ in self.device.writes), count)
            self.device.token = ("different-partner", 2)
            restarted.step(self.device, self.upstream, 4)
            self.assertEqual(sum(n == "verify_digest" for n, _ in self.device.writes), count + 1)

    def test_receipt_cannot_override_cleared_firmware_flags(self):
        with tempfile.TemporaryDirectory() as directory:
            receipt = Path(directory) / "verified.json"
            auth.save_verified_session(receipt, self.device.session())
            self.device.values["pd_verifed"] = "0"
            restarted = auth.Controller(receipt=receipt)
            restarted.step(self.device, self.upstream, 0)
            self.assertTrue(any(n == "verify_digest" for n, _ in self.device.writes))

    def test_gauge_mismatch_never_submits_positive(self):
        self.device.bad_gauge = True
        with self.assertRaisesRegex(RuntimeError, "gauge digest"):
            self.run_auth()
        self.assertNotIn(("authentic", "1"), self.device.writes)
        self.assertNotIn(("pd_verifed", "1"), self.device.writes)
        self.assertFalse(any(n == "request_vdm_cmd" for n, _ in self.device.writes))
        self.assertEqual(self.device.values["pd_verifed"], "0")

    def test_display_change_is_forwarded_before_digest_commit(self):
        original = self.device.read
        def read(name):
            if name == "verify_digest":
                self.device.blank = 1
            return original(name)
        self.device.read = read
        self.run_auth()
        writes = self.device.writes
        self.assertLess(writes.index(("fb_blank_state", "1")), writes.index(("authentic", "1")))

    def test_adapter_mismatch_never_sends_verified(self):
        self.device.bad_adapter = True
        with self.assertRaisesRegex(RuntimeError, "adapter digest"):
            self.run_auth()
        self.assertNotIn(("pd_verifed", "1"), self.device.writes)
        self.assertFalse(any(n == "request_vdm_cmd" and v.startswith(("6,", "7,", "8,"))
                             for n, v in self.device.writes))
        self.assertEqual(self.device.values["authentic"], "0")

    def test_malformed_gauge_digest_is_rejected(self):
        original = self.device.read
        self.device.read = lambda n: original(n) + "suffix" if n == "verify_digest" else original(n)
        with self.assertRaisesRegex(RuntimeError, "gauge digest"):
            self.run_auth()
        self.assertNotIn(("authentic", "1"), self.device.writes)

    def test_detach_mid_digest_cannot_authenticate_new_partner(self):
        self.device.detach_on = "verify_digest"
        with self.assertRaises(auth.SessionChanged):
            self.run_auth()
        self.assertNotIn(("authentic", "1"), self.device.writes)
        self.assertNotIn(("pd_verifed", "1"), self.device.writes)

    def test_generic_pd_and_computer_usb_do_not_write(self):
        for svid, pdo in (("00000000", "12345678"), ("00002717", "00000000")):
            self.device.values.update(adapter_svid=svid, pdo2=pdo)
            with self.assertRaises(auth.UnsupportedAdapter):
                self.run_auth()
            self.assertEqual(self.device.writes, [])

    def test_boot_attached_dedup_unplug_and_adsp_restart(self):
        c = auth.Controller()
        c.step(self.device, self.upstream, 0)
        self.assertTrue(c.authenticated)
        count = len(self.device.writes)
        c.step(self.device, self.upstream, 2)
        self.assertEqual(len(self.device.writes), count)
        self.device.blank = 1
        c.step(self.device, self.upstream, 4)
        self.assertEqual(self.device.values["fb_blank_state"], "1")
        self.device.token = None
        c.step(self.device, self.upstream, 6)
        self.assertFalse(c.authenticated)
        self.device.token = ("second-partner", 1)
        c.step(self.device, self.upstream, 8)
        self.assertTrue(c.authenticated)
        self.device.token = ("second-partner", 2)
        c.step(self.device, self.upstream, 10)
        self.assertTrue(c.authenticated)
        self.assertEqual(sum(n == "verify_digest" for n, _ in self.device.writes), 3)

    def test_failure_retries_and_eventual_success(self):
        c = auth.Controller()
        self.device.timeout = True
        c.step(self.device, self.upstream, 0)
        self.assertFalse(c.authenticated)
        self.assertEqual(c.attempts, 1)
        count = len(self.device.writes)
        c.step(self.device, self.upstream, 2)
        self.assertEqual(len(self.device.writes), count)
        self.device.timeout = False
        c.step(self.device, self.upstream, 61)
        self.assertTrue(c.authenticated)

    def test_firmware_cleared_flags_are_reauthenticated(self):
        c = auth.Controller()
        c.step(self.device, self.upstream, 0)
        self.device.values["pd_verifed"] = "0"
        c.step(self.device, self.upstream, 2)
        self.assertTrue(c.authenticated)
        self.assertEqual(sum(n == "verify_digest" for n, _ in self.device.writes), 2)

    def test_missing_svid_logs_pending_once(self):
        self.device.values["adapter_svid"] = "00000000"
        c = auth.Controller()
        with self.assertLogs(auth.LOG, level="INFO") as logs:
            c.step(self.device, self.upstream, 0)
            c.step(self.device, self.upstream, 11)
        self.assertEqual(len(logs.output), 1)
        self.assertIn("authentication pending", logs.output[0])
        self.assertIn("adapter_svid=00000000", logs.output[0])
        self.assertNotIn(("authentic", "1"), self.device.writes)


class SysfsTests(unittest.TestCase):
    def test_discovery_rolls_back_non_xiaomi_and_keeps_power_role(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            d = auth.Device(root / "xiaomi", root)
            partner = root / "class/typec/port0-partner"
            partner.mkdir(parents=True)
            port = partner.with_name("port0")
            port.mkdir()
            (port / "power_role").write_text("source [sink]")
            (port / "data_role").write_text("host [device]")
            d.usb.mkdir(parents=True)
            (d.usb / "usb_type").write_text("[PD]")
            token = ("root", "generation", "partner", 1, 2)
            with patch.object(d, "session", return_value=token), patch.object(d, "read", return_value="00000000"):
                with self.assertRaises(auth.UnsupportedAdapter):
                    manager = Mock()
                    manager.status.side_effect = [
                        {"busy": "false", "desired_mode": "developer_mode"},
                        {"busy": "false", "desired_mode": "host_mode"},
                    ]
                    d.discover_xiaomi(token, timeout=0, manager=manager)
            self.assertEqual([call.args[0] for call in manager.request.call_args_list], ["host_mode", "developer_mode"])
            self.assertEqual((port / "data_role").read_text(), "host [device]")
            self.assertEqual((port / "power_role").read_text(), "source [sink]")

    def test_unicorn_battery_name_and_legacy_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            d = auth.Device(root / "xiaomi", root)
            legacy = root / "class/power_supply/battery"
            legacy.mkdir(parents=True)
            self.assertEqual(d.battery_supply(), legacy)
            battery = root / "class/power_supply/qcom-battmgr-bat"
            battery.mkdir()
            (battery / "capacity").write_text("100")
            (battery / "temp").write_text("309")
            self.assertEqual(d.battery_supply(), battery)
            snapshot = auth.diagnostics(d)
            self.assertEqual(snapshot["capacity"], "100")
            self.assertEqual(snapshot["temp"], "309")

    def test_routine_snapshot_skips_unverified_properties(self):
        with tempfile.TemporaryDirectory() as directory:
            d = auth.Device(directory, directory)
            with patch.object(d, "read", return_value="0") as read:
                snapshot = auth.diagnostics(d)
            self.assertEqual(snapshot["bq2597x_battery_voltage"], "not-probed")
            read.assert_any_call("bq2597x_bus_voltage")
            self.assertFalse(any(call.args[0] in auth.EXTENDED_DIAGNOSTICS
                                 for call in read.call_args_list))

    def test_extended_probe_stops_at_timeout(self):
        with tempfile.TemporaryDirectory() as directory:
            d = auth.Device(directory, directory)
            def read(name):
                if name == "bq2597x_battery_voltage":
                    raise TimeoutError(errno.ETIMEDOUT, "firmware timeout")
                return "0"
            with patch.object(d, "read", side_effect=read) as mocked:
                snapshot = auth.diagnostics(d, extended=True)
            self.assertEqual(snapshot["bq2597x_battery_voltage"], "error:110")
            self.assertEqual(snapshot["master_smb1396_online"], "skipped:previous-timeout")
            self.assertFalse(any(call.args[0] == "master_smb1396_online"
                                 for call in mocked.call_args_list))

    def test_blocking_error_has_a_useful_code(self):
        self.assertEqual(auth.read_error(BlockingIOError()), "error:11")

    def test_actual_drm_dpms_and_unknown_are_conservative(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            d = auth.Device(root, root)
            self.assertEqual(d.blank_state(), 0)
            dpms = root / "class/drm/card0-DSI-1/dpms"
            dpms.parent.mkdir(parents=True)
            for state, expected in (("On", 0), ("Off", 1), ("Unknown", 0), ("Standby", 0)):
                dpms.write_text(state)
                self.assertEqual(d.blank_state(), expected)

    def test_power_uses_usb_input_and_preserves_errors(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            d = auth.Device(root / "xiaomi", root)
            d.usb.mkdir(parents=True)
            (d.usb / "voltage_now").write_text("20000000")
            (d.usb / "current_now").write_text("6000000")
            self.assertEqual(auth.diagnostics(d)["usb_input_watts"], 120)
            (d.usb / "current_now").unlink()
            result = auth.diagnostics(d)
            self.assertEqual(result["usb_input_watts"], "unavailable")
            self.assertEqual(result["current_now"], "error:2")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", required=True, type=Path)
    args, rest = parser.parse_known_args()
    UPSTREAM = args.upstream
    unittest.main(argv=[__file__] + rest)
