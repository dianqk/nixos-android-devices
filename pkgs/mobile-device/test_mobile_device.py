"""Host-only checks: no fastboot, SSH, or partition writes."""

import argparse
from pathlib import Path
import subprocess
import tempfile
import hashlib
import shlex
import unittest
from unittest.mock import patch

import mobile_device as cli
from test_boot_image import make_image


class FakeSsh:
    def __init__(self, query=""):
        self.calls = []
        self.query = query

    def recovery(self):
        self.calls.append(("recovery",))

    def temporary(self):
        return "/tmp/mobile-device.TEST"

    def push(self, source, target):
        self.calls.append(("push", target))

    def shell(self, *args, **kwargs):
        self.calls.append(("shell", *map(str, args)))
        return subprocess.CompletedProcess(args, 0, b"", b"")

    def text(self, *args):
        self.calls.append(("text", *map(str, args)))
        return self.query


class MobileDeviceTests(unittest.TestCase):
    def test_ssh_target_and_argument_quoting(self):
        for target in (None, "", "-oProxyCommand=bad", "root@host command"):
            with self.assertRaises(cli.ToolError):
                cli.Ssh(target)
        transport = cli.Ssh("root@phone", "/path with spaces/config")
        with patch.object(cli, "run") as run:
            transport.shell("cat", "/tmp/a; echo bad")
            command = run.call_args.args[0]
            self.assertIn("-T", command)
            self.assertIn("BatchMode=yes", command)
            self.assertEqual(command[-2], "root@phone")
            self.assertEqual(shlex.split(command[-1]), ["cat", "/tmp/a; echo bad"])

    def test_mount_default_is_readonly_and_rebuild_rejects_switch(self):
        transport = FakeSsh()
        with patch.object(cli, "Ssh", return_value=transport):
            self.assertEqual(cli.main(["recovery", "--target", "test", "mount"]), 0)
            self.assertEqual(cli.main(["recovery", "--target", "test", "rebuild", "switch"]), 1)
        self.assertIn(("shell", "recovery", "mount-target", "--ro"), transport.calls)
        self.assertFalse(any("switch" in call for call in transport.calls))

    def test_recovery_uses_fixed_command_without_selector(self):
        transport = FakeSsh()
        with patch.object(cli, "Ssh", return_value=transport):
            self.assertEqual(cli.main(["recovery", "--target", "test", "status"]), 0)
        self.assertIn(("recovery",), transport.calls)
        self.assertIn(("text", "recovery", "status"), transport.calls)

    def test_reboot_disconnect_requires_matching_acknowledgement(self):
        args = argparse.Namespace(command_action="reboot", destination="recovery", execute=True)
        for message, allowed in [(b"Rebooting.\n", True),
                                 (b"Rebooting with argument 'recovery'.\n", True),
                                 (b"Rebooting with argument 'bootloader'.\n", False),
                                 (b"ERROR: not Rebooting.\n", False), (b"", False)]:
            with self.subTest(message=message):
                transport = FakeSsh()
                with patch.object(transport, "shell", return_value=subprocess.CompletedProcess([], 1, b"", message)):
                    if allowed:
                        cli.recovery_command(args, transport)
                    else:
                        with self.assertRaises(cli.ToolError):
                            cli.recovery_command(args, transport)

    def test_serial_selection_never_guesses_between_devices(self):
        with patch.object(cli, "output", return_value="abc\tfastboot\nxyz\tfastboot"):
            with self.assertRaises(cli.ToolError):
                cli.choose_serial("fastboot", None, "fastboot")
            self.assertEqual(cli.choose_serial("fastboot", "xyz", "fastboot"), "xyz")
            with self.assertRaises(cli.ToolError):
                cli.choose_serial("fastboot", "wrong", "fastboot")

    def fastboot_fixture(self, directory, board="clover", **overrides):
        image = Path(directory) / "anything.img"
        image.write_bytes(make_image(board))
        args = argparse.Namespace(image=str(image), serial="abc", operation="flash",
                                  partition="recovery_b" if board in ("sheng", "asphalt") else "recovery",
                                  execute=False)
        variables = {"product": board, "current-slot": "b",
                     "partition-size:" + args.partition: "0x1000000"}
        variables.update(overrides)
        def run(command, **kwargs):
            if command == ["fastboot", "devices"]:
                return subprocess.CompletedProcess(command, 0, b"abc\tfastboot\n", b"")
            if command[3] == "getvar":
                name = command[4]
                return subprocess.CompletedProcess(command, 0, b"",
                    f"(bootloader) {name}: {variables.get(name, '')}\nFinished. Total time: 0.001s\n".encode())
            return subprocess.CompletedProcess(command, 0, b"", b"")
        return args, run

    def test_fastboot_check_and_execute_use_verified_partition(self):
        with tempfile.TemporaryDirectory() as directory:
            args, transport = self.fastboot_fixture(directory)
            with patch.object(cli, "run", side_effect=transport) as run:
                cli.fastboot(args)
                self.assertTrue(all(c.args[0][-1] in ("devices", "product", "partition-size:recovery")
                                    for c in run.call_args_list))
                args.execute = True
                cli.fastboot(args)
                self.assertEqual(run.call_args.args[0],
                                 ["fastboot", "-s", "abc", "flash", "recovery", str(Path(args.image).resolve())])

    def test_fastboot_refuses_mismatch_slot_capacity_and_partition(self):
        cases = [("clover", {"product": "polaris"}, None),
                 ("sheng", {"current-slot": "a"}, None),
                 ("sheng", {"current-slot": ""}, None),
                 ("sheng", {}, "recovery_a"),
                 ("clover", {}, "super"),
                 ("clover", {"partition-size:recovery": "0x1"}, None),
                 ("clover", {"partition-size:recovery": "unknown"}, None)]
        for board, variables, partition in cases:
            with self.subTest(board=board, variables=variables, partition=partition), tempfile.TemporaryDirectory() as directory:
                args, transport = self.fastboot_fixture(directory, board, **variables)
                args.execute = True
                if partition:
                    args.partition = partition
                with patch.object(cli, "run", side_effect=transport) as run:
                    with self.assertRaises(cli.ToolError):
                        cli.fastboot(args)
                    self.assertFalse(any(c.args[0][3:4] == ["flash"] for c in run.call_args_list))

    def test_invalid_image_is_rejected_before_device_access(self):
        with tempfile.TemporaryDirectory() as directory:
            args, _ = self.fastboot_fixture(directory)
            Path(args.image).write_text("not a boot image")
            args.execute = True
            with patch.object(cli, "run") as run, self.assertRaises(ValueError):
                cli.fastboot(args)
            run.assert_not_called()

    def test_deploy_query_accepts_only_manifest_paths(self):
        transport = FakeSsh(query="/nix/store/other")
        args = argparse.Namespace(system="ignored", execute=False,
                                  result_file="/run/deploy.result")
        with patch.object(cli, "local_system", return_value=Path("/nix/store/system")), \
             patch.object(cli, "closure_manifest", return_value=(["/nix/store/system"], b"sha256:test /nix/store/system\n")):
            with self.assertRaisesRegex(cli.ToolError, "outside the selected closure"):
                cli.recovery_deploy(args, transport)
        self.assertFalse(any("deploy-offline" in call for call in transport.calls))



    def test_format_requires_explicit_execute_after_check(self):
        transport = FakeSsh()
        args = argparse.Namespace(execute=False)
        cli.recovery_format_userdata(args, transport)
        self.assertIn(("shell", "recovery", "format-userdata", "--check"), transport.calls)
        self.assertFalse(any("--confirm" in call for call in transport.calls))
        transport.calls.clear()
        args.execute = True
        cli.recovery_format_userdata(args, transport)
        self.assertEqual([call[-1] for call in transport.calls if call[0] == "shell"],
                         ["--check", "--confirm"])

    def test_linux_root_format_requires_explicit_execute(self):
        transport = FakeSsh()
        args = argparse.Namespace(execute=False)
        cli.recovery_format_root(args, transport)
        self.assertEqual([call[-1] for call in transport.calls if call[0] == "shell"], ["--check"])
        transport.calls.clear()
        args.execute = True
        cli.recovery_format_root(args, transport)
        self.assertEqual([call[-1] for call in transport.calls if call[0] == "shell"],
                         ["--check", "--confirm"])

    def test_initial_install_check_never_streams_or_formats(self):
        transport = FakeSsh(query="polaris")
        args = argparse.Namespace(system="ignored",
                                  bootstrap_info="ignored", result_file="/run/first.result",
                                  execute=False)
        with patch.object(cli, "local_system", return_value=Path("/nix/store/system")), \
             patch.object(cli, "closure_manifest", return_value=(["/nix/store/system"], b"sha256:test /nix/store/system\n")), \
             patch.object(cli, "bootstrap_info", return_value=(Path("/tmp/registration"), 4096)), \
             patch.object(Path, "is_file", return_value=True), \
             patch.object(Path, "read_text", return_value="polaris"), \
             patch.object(cli, "stream_closure_tar") as stream:
            cli.recovery_install_initial(args, transport)
        stream.assert_not_called()
        self.assertTrue(any(call[-1] == "--check" for call in transport.calls if call[0] == "shell"))
        self.assertFalse(any("--confirm" in call or "format-userdata" in call for call in transport.calls))

    def test_initial_install_uses_shared_result_default(self):
        with patch.object(cli, "Ssh"), patch.object(cli, "recovery_install_initial") as install:
            self.assertEqual(cli.main(["recovery", "--target", "test", "install-initial",
                                       "/nix/store/system", "--bootstrap-info", "bootstrap"]), 0)
        self.assertEqual(install.call_args.args[0].result_file, "/run/mobile-initial-install.result")

    def test_initial_install_wrong_device_fails_before_transfer(self):
        transport = FakeSsh(query="sheng")
        args = argparse.Namespace(system="ignored", bootstrap_info="ignored", execute=True)
        with patch.object(cli, "local_system", return_value=Path("/nix/store/system")), \
             patch.object(Path, "is_file", return_value=True), \
             patch.object(Path, "read_text", return_value="polaris"), \
             patch.object(cli, "stream_closure_tar") as stream:
            with self.assertRaisesRegex(cli.ToolError, "does not match"):
                cli.recovery_install_initial(args, transport)
        stream.assert_not_called()
        self.assertFalse(any(call[0] == "push" for call in transport.calls))

    def test_initial_install_uncertain_transfer_keeps_remote_inputs(self):
        transport = FakeSsh(query="polaris")
        args = argparse.Namespace(system="ignored", bootstrap_info="ignored", execute=True,
                                  result_file="/run/mobile-initial-install.result")
        with patch.object(cli, "local_system", return_value=Path("/nix/store/system")), \
             patch.object(Path, "is_file", return_value=True), \
             patch.object(Path, "read_text", return_value="polaris"), \
             patch.object(cli, "closure_manifest", return_value=(["/nix/store/system"], b"manifest")), \
             patch.object(cli, "bootstrap_info", return_value=(Path("/tmp/registration"), 4096)), \
             patch.object(cli, "stream_closure_tar", side_effect=cli.ToolError("interrupted")):
            with self.assertRaisesRegex(cli.ToolError, "interrupted"):
                cli.recovery_install_initial(args, transport)
        self.assertNotIn(("shell", "rm", "-rf", "/tmp/mobile-device.TEST"), transport.calls)

    def test_bootstrap_metadata_must_match_closure(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            (base / "registration").write_text("registration\n")
            (base / "store-paths").write_text("/nix/store/other\n")
            (base / "total-nar-size").write_text("4096\n")
            with self.assertRaisesRegex(cli.ToolError, "does not describe"):
                cli.bootstrap_info(base, ["/nix/store/system"])

    def test_ssh_uses_one_quoted_remote_command(self):
        with patch.object(cli, "run", return_value=subprocess.CompletedProcess([], 0, b"", b"")) as run:
            cli.ssh_command("example", "echo", "a b", "$(touch /tmp/bad)")
        self.assertEqual(run.call_args.args[0],
                         ["ssh", "-o", "BatchMode=yes", "example",
                          "echo 'a b' '$(touch /tmp/bad)'"])

    def test_toml_defaults_are_passed_to_command(self):
        with tempfile.TemporaryDirectory() as directory:
            profile = Path(directory) / "device.toml"
            profile.write_text('serial = "example"\n')
            with patch.object(cli, "fastboot") as fastboot:
                self.assertEqual(cli.main(["--config", str(profile), "fastboot", "boot", "image"]), 0)
                self.assertEqual(fastboot.call_args.args[0].serial, "example")


if __name__ == "__main__":
    unittest.main()
