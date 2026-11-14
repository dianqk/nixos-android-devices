#!/usr/bin/env python3
"""Exercise independent hardware-key actions without input devices or a desktop."""
import importlib.util
from pathlib import Path
import signal
import sys
import unittest
from unittest.mock import Mock, patch


spec = importlib.util.spec_from_file_location(
    "hardware_keys", Path(__file__).resolve().parents[1] / "pkgs/unicorn/hardware-keys.py"
)
keys = importlib.util.module_from_spec(spec)
spec.loader.exec_module(keys)


class HardwareKeysTests(unittest.TestCase):
    def test_power_keys_without_audio(self):
        screen, shutdown = Mock(), Mock()
        policy = keys.KeyPolicy(None, screen, shutdown)
        policy.event(keys.KEY_VOLUMEUP, 1, 0)
        self.assertEqual(policy.volume_down, {})
        policy.event(keys.KEY_POWER, 1, 1)
        policy.event(keys.KEY_POWER, 0, 1.1)
        screen.assert_called_once_with()
        policy.event(keys.KEY_POWER, 1, 2)
        policy.tick(5)
        policy.tick(6)
        policy.event(keys.KEY_POWER, 0, 6)
        shutdown.assert_called_once_with()
        screen.assert_called_once_with()

    def test_screen_without_shutdown(self):
        screen = Mock()
        policy = keys.KeyPolicy(None, screen, None)
        policy.event(keys.KEY_POWER, 1, 0)
        policy.tick(4)
        policy.event(keys.KEY_POWER, 0, 4)
        screen.assert_not_called()
        policy.event(keys.KEY_POWER, 1, 5)
        policy.event(keys.KEY_POWER, 0, 5.1)
        screen.assert_called_once_with()

    def test_shutdown_without_screen(self):
        shutdown = Mock()
        policy = keys.KeyPolicy(None, None, shutdown)
        policy.event(keys.KEY_POWER, 1, 0)
        policy.event(keys.KEY_POWER, 0, 0.1)
        shutdown.assert_not_called()
        policy.event(keys.KEY_POWER, 1, 1)
        policy.event(keys.KEY_POWER, 0, 4)
        shutdown.assert_called_once_with()

    def test_volume_without_power_key_actions(self):
        volume = Mock()
        policy = keys.KeyPolicy(volume, None, None)
        policy.event(keys.KEY_POWER, 1, 0)
        policy.tick(4)
        self.assertIsNone(policy.power_down)
        policy.event(keys.KEY_VOLUMEUP, 1, 5)
        policy.tick(5.4)
        policy.event(keys.KEY_VOLUMEUP, 0, 5.5)
        policy.tick(6)
        self.assertEqual(volume.call_count, 2)
        volume.assert_called_with(True)

    def test_lost_release_never_shuts_down(self):
        shutdown = Mock()
        policy = keys.KeyPolicy(None, None, shutdown)
        policy.event(keys.KEY_POWER, 1, 0)
        policy.reset()
        policy.tick(10)
        shutdown.assert_not_called()

    def test_disabled_backends_start_without_vt_or_audio(self):
        handlers = {}

        def register(sig, handler):
            handlers[sig] = handler

        def stop_select(*_):
            handlers[signal.SIGTERM]()
            return []

        with patch.object(sys, "argv", ["hardware-keys", "--no-screen", "--no-poweroff"]), \
             patch.object(keys, "ConsoleScreen") as screen, \
             patch.object(keys.subprocess, "run") as run, \
             patch.object(keys.signal, "signal", side_effect=register), \
             patch.object(keys.Path, "glob", return_value=[]), \
             patch.object(keys.selectors, "DefaultSelector") as selector:
            selector.return_value.select.side_effect = stop_select
            keys.main()
            screen.assert_not_called()
            run.assert_not_called()
            selector.return_value.close.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
