#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import signal
import sys
from contextlib import ExitStack
from types import SimpleNamespace
import unittest
from unittest.mock import patch, Mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sharing", ROOT / "modules/mobile/usb-tethering.py")
sharing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sharing)


class SharingTests(unittest.TestCase):
    def test_default_route_metric_and_usb_exclusion(self):
        self.assertEqual(sharing.uplink([
            {"dst": "default", "dev": "usb0", "metric": 0},
            {"dst": "default", "dev": "wlan0", "metric": 600},
            {"dst": "default", "dev": "wwan0", "metric": 100},
        ]), "wwan0")
        self.assertIsNone(sharing.uplink([]))
        self.assertIsNone(sharing.uplink([{"dst": "default", "dev": "lo"}]))
        self.assertIsNone(sharing.uplink([{"dst": "default", "type": "blackhole"}]))

    def test_route_does_not_interpolate_nft_commands(self):
        with self.assertRaises(ValueError):
            sharing.uplink([{"dst": "default", "dev": 'wlan0";accept;'}])

    def test_upstream_replaced_in_one_transaction(self):
        with patch.object(sharing, "run") as command:
            sharing.set_uplink("wlan0")
            self.assertEqual(command.call_count, 1)
            self.assertIn('flush set inet mobile_usb uplink\nadd element inet mobile_usb uplink { "wlan0" }', command.call_args.kwargs["input"])
            sharing.set_uplink(None)
            self.assertNotIn("add element", command.call_args.kwargs["input"])

    def test_scoped_forwarding_restores_preexisting_policy_and_survives_crash(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for interface, value in [("usb0", "0"), ("wlan0", "1"), ("other", "0")]:
                (root / interface).mkdir()
                (root / interface / "forwarding").write_text(value)
            receipt = root / "saved.json"
            forwarding = sharing.Forwarding(root, receipt)
            forwarding.enable("usb0")
            forwarding.enable("wlan0")
            self.assertEqual((root / "other/forwarding").read_text(), "0")
            # Reconstruct after SIGKILL, then restore only the owned interfaces.
            sharing.Forwarding(root, receipt).close()
            self.assertEqual((root / "usb0/forwarding").read_text().strip(), "0")
            self.assertEqual((root / "wlan0/forwarding").read_text().strip(), "1")
            self.assertEqual((root / "other/forwarding").read_text(), "0")

    def test_damaged_receipt_still_closes_gate_and_removes_dhcp_policy(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ready, saved, dropin = [root / name for name in ("ready", "saved", "dropin")]
            for path in (ready, saved, dropin):
                path.write_text("invalid")
            with patch.object(sharing, "PREPARED", root / "prepared"), patch.object(sharing, "READY", ready), patch.object(sharing, "SAVED", saved), patch.object(sharing, "DROPIN", dropin), patch.object(sharing, "set_uplink") as gate, patch.object(sharing, "network_reload") as reload:
                with self.assertRaises(ValueError):
                    sharing.cleanup()
                gate.assert_called_once_with(None)
                reload.assert_called_once()
            self.assertFalse(ready.exists())
            self.assertFalse(dropin.exists())

    def test_prepares_dhcp_before_binding_and_waits_for_own_netdev(self):
        with tempfile.TemporaryDirectory() as tmp, ExitStack() as stack:
            root = Path(tmp)
            for name, filename in [("READY", "ready"), ("PREPARED", "prepared"), ("DROPIN", "dropin"), ("SAVED", "saved"), ("NET", "net")]:
                stack.enter_context(patch.object(sharing, name, root / filename))
            handlers = {}
            stack.enter_context(patch.object(sharing.signal, "signal", side_effect=lambda sig, fn: handlers.update({sig: fn})))
            runner = stack.enter_context(patch.object(sharing, "run", return_value=SimpleNamespace(stdout="[]")))
            forwarding = Mock()
            stack.enter_context(patch.object(sharing, "Forwarding", return_value=forwarding))
            mac = "02:11:22:33:44:55"
            address = root / "net/usb0/address"

            def sleep(_seconds):
                if not address.exists():
                    # Simulate the kernel registering NCM at UDC bind time.
                    self.assertTrue(sharing.PREPARED.exists())
                    self.assertIn("EmitRouter=yes", sharing.DROPIN.read_text())
                    self.assertFalse(any(call.args[:2] == ("networkctl", "reconfigure") for call in runner.call_args_list))
                    address.parent.mkdir(parents=True)
                    address.write_text(mac)
                else:
                    self.assertEqual(sharing.READY.read_text().strip(), "offline")
                    handlers[signal.SIGTERM](signal.SIGTERM, None)

            def enable(interface):
                self.assertEqual(interface, "usb0")
                self.assertEqual(address.read_text(), mac)
                self.assertTrue(sharing.PREPARED.exists())

            forwarding.enable.side_effect = enable
            stack.enter_context(patch.object(sharing.time, "sleep", side_effect=sleep))
            stack.enter_context(patch.object(sys, "argv", ["sharing", "172.16.47.1/24", "--mac", mac]))
            sharing.main()
            forwarding.enable.assert_called_once_with("usb0")
            self.assertFalse(sharing.READY.exists())
            self.assertFalse(sharing.PREPARED.exists())
            self.assertFalse(sharing.DROPIN.exists())

    def test_never_enables_a_foreign_usb_interface(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "usb0").mkdir()
            (root / "usb0/address").write_text("06:00:00:00:00:00")
            with patch.object(sharing, "NET", root):
                with self.assertRaisesRegex(RuntimeError, "another device"):
                    sharing.wait_for_gadget("02:11:22:33:44:55", lambda: False)

    def test_disappearing_upstream_and_external_disable_are_safe(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "wlan0").mkdir()
            path = root / "wlan0/forwarding"
            path.write_text("0")
            forwarding = sharing.Forwarding(root)
            forwarding.enable("wlan0")
            path.write_text("0")
            forwarding.restore("wlan0")
            self.assertEqual(path.read_text(), "0")
            forwarding.enable("wlan0")
            path.unlink()
            forwarding.close()


if __name__ == "__main__":
    unittest.main()
