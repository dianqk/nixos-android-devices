"""Host-only checks: no fastboot, SSH, or partition writes."""

import argparse
from pathlib import Path
import subprocess
import tempfile
import hashlib
import json
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
        # Every supported recovery runs the Rust daemon protocol.
        if args == ("cat", "/etc/mobile-recovery-protocol"):
            return subprocess.CompletedProcess(args, 0, b"1\n", b"")
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

    def identity_fixture(self, directory, **changes):
        record = dict(version=1, serial="abc", product="taro",
                      compatible=["lenovo,asphalt", "qcom,sm8475"],
                      source="nixos-ram-recovery", collected_at="2026-10-02T08:00:00+00:00",
                      boot_id="12345678-1234-1234-1234-123456789abc")
        record.update(changes)
        path = Path(directory) / "identity.json"
        path.write_text(json.dumps(record))
        return path

    def test_soc_product_identity_is_explicit_and_rechecked(self):
        with tempfile.TemporaryDirectory() as directory:
            args, transport = self.fastboot_fixture(directory, "asphalt", product="taro", serialno="abc")
            args.device_identity = self.identity_fixture(directory)
            args.serial_explicit = True
            with patch.object(cli, "run", side_effect=transport) as run:
                cli.fastboot(args)
                self.assertFalse(any(c.args[0][3:4] == ["flash"] for c in run.call_args_list))
                run.reset_mock()
                args.execute = True
                cli.fastboot(args)
                queries = [c.args[0][-1] for c in run.call_args_list if c.args[0][3:4] == ["getvar"]]
                self.assertEqual(queries, ["product", "serialno", "modelname", "current-slot", "partition-size:recovery_b"])
                self.assertEqual(run.call_args.args[0][3:5], ["flash", "recovery_b"])

    def test_soc_product_identity_refusals_never_flash(self):
        cases = [
            ({}, {}, "missing"), ({}, {}, "implicit"),
            ({"serial": "other"}, {}, "record"), ({}, {"serialno": "other"}, "record"),
            ({}, {"serialno": ""}, "record"),
            ({"compatible": ["qcom,sm8475"]}, {}, "record"),
            ({"compatible": ["lenovo,asphalt", "xiaomi,sheng"]}, {}, "record"),
            ({"product": "other"}, {}, "record"), ({}, {"product": "asphalt"}, "record"),
            ({"version": True}, {}, "record"), ({"source": "unknown"}, {}, "record"),
            ({"collected_at": "bad"}, {}, "record"), ({"collected_at": "2026-10-02"}, {}, "record"),
            ({"boot_id": "bad"}, {}, "record"), ({"compatible": "lenovo,asphalt"}, {}, "record"),
            ({}, {}, "malformed"), ({}, {}, "extra"), ({}, {}, "oversize"),
            ({}, {}, "duplicate"), ({}, {}, "missing_field"),
            ({}, {"current-slot": "a"}, "record"), ({}, {}, "wrong_partition"),
            ({}, {"partition-size:recovery_b": "0x1"}, "record"),
        ]
        for changes, variables, mode in cases:
            with self.subTest(changes=changes, variables=variables, mode=mode), tempfile.TemporaryDirectory() as directory:
                args, transport = self.fastboot_fixture(directory, "asphalt", **({"product": "taro", "serialno": "abc"} | variables))
                args.execute = True
                args.serial_explicit = mode != "implicit"
                if mode != "missing":
                    args.device_identity = self.identity_fixture(directory, **changes)
                    if mode == "malformed": args.device_identity.write_text("{")
                    if mode == "extra": args.device_identity.write_text(args.device_identity.read_text()[:-1] + ', "extra": 1}')
                    if mode == "oversize": args.device_identity.write_text(" " * 16385)
                    if mode == "duplicate": args.device_identity.write_text(args.device_identity.read_text()[:-1] + ', "serial": "abc"}')
                    if mode == "missing_field":
                        record = json.loads(args.device_identity.read_text())
                        del record["source"]
                        args.device_identity.write_text(json.dumps(record))
                if mode == "wrong_partition": args.partition = "recovery_a"
                with patch.object(cli, "run", side_effect=transport) as run:
                    with self.assertRaises(cli.ToolError): cli.fastboot(args)
                    self.assertFalse(any(c.args[0][3:4] == ["flash"] for c in run.call_args_list))

    def test_oem_model_check_and_execute_revalidate_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            args, transport = self.fastboot_fixture(directory, "asphalt", product="taro",
                                                    serialno="abc", modelname="TB320FC")
            args.serial_explicit = True
            with patch.object(cli, "run", side_effect=transport) as run:
                cli.fastboot(args)
                self.assertFalse(any(c.args[0][3:4] == ["flash"] for c in run.call_args_list))
                args.execute = True
                cli.fastboot(args)
                self.assertEqual(run.call_args.args[0][3:5], ["flash", "recovery_b"])
            for changes in ({"modelname": "TB320FC-other"}, {"modelname": "tb320fc"},
                            {"modelname": ""}, {"serialno": "other"}, {"current-slot": "a"}):
                _, changed = self.fastboot_fixture(directory, "asphalt", **(
                    {"product": "taro", "serialno": "abc", "modelname": "TB320FC"} | changes))
                with patch.object(cli, "run", side_effect=changed) as run:
                    with self.assertRaises(cli.ToolError): cli.fastboot(args)
                    self.assertFalse(any(c.args[0][3:4] == ["flash"] for c in run.call_args_list))

    def test_oem_model_does_not_override_invalid_record_or_wrong_model(self):
        for model, record, explicit in [("TB320FC", "bad", True), ("OTHER", "valid", True),
                                         ("TB320FC", None, False)]:
            with self.subTest(model=model, record=record), tempfile.TemporaryDirectory() as directory:
                args, transport = self.fastboot_fixture(directory, "asphalt", product="taro",
                                                        serialno="abc", modelname=model)
                args.serial_explicit = explicit
                args.execute = True
                if record:
                    args.device_identity = self.identity_fixture(directory)
                    if record == "bad": args.device_identity.write_text("{")
                with patch.object(cli, "run", side_effect=transport) as run:
                    with self.assertRaises(cli.ToolError): cli.fastboot(args)
                    self.assertFalse(any(c.args[0][3:4] == ["flash"] for c in run.call_args_list))

    def test_optional_model_only_accepts_explicit_absence(self):
        for code, text, absent in [
            (0, b"modelname: \n", True),
            (1, b"FAILED (remote: 'GetVar Variable Not found')\n", True),
            (0, b"modelname: TB320FC\nmodelname: OTHER\n", False),
            (0, b"modelname TB320FC\n", False), (0, b"", False),
            (1, b"modelname OTHER\nFAILED (remote: 'Variable not found')\n", False),
            (1, b"FAILED (remote: 'device disconnected')\n", False),
            (1, b"modelname: OTHER\nFAILED (remote: 'Variable not found')\n", False),
        ]:
            with self.subTest(code=code, text=text), patch.object(cli, "run", return_value=
                    subprocess.CompletedProcess([], code, b"", text)):
                if absent:
                    self.assertIsNone(cli.fastboot_modelname("abc"))
                else:
                    with self.assertRaises(cli.ToolError): cli.fastboot_modelname("abc")

    def test_asphalt_dtbo_erase_checks_and_refusals(self):
        cases = [None, "image", "device", "partition", "slot", "model", "missing_model_record",
                 "serial", "implicit", "capacity", "larger_capacity", "invalid_capacity",
                 "other_product", "invalid_record", "malformed_record"]
        for case in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                variables = {"product": "taro", "serialno": "abc", "modelname": "TB320FC",
                             "partition-size:dtbo_b": "0x1800000"}
                if case == "slot": variables["current-slot"] = "a"
                if case == "model": variables["modelname"] = "OTHER"
                if case == "missing_model_record": variables["modelname"] = ""
                if case == "serial": variables["serialno"] = "other"
                if case == "capacity": variables["partition-size:dtbo_b"] = "0x1000000"
                if case == "larger_capacity": variables["partition-size:dtbo_b"] = "0x6000000"
                if case == "invalid_capacity": variables["partition-size:dtbo_b"] = "unknown"
                if case == "other_product": variables["product"] = "sheng"
                args, transport = self.fastboot_fixture(directory, "asphalt", **variables)
                args.image = args.image if case == "image" else None
                args.device = None if case == "device" else "asphalt"
                args.partition = "dtbo_a" if case == "partition" else "dtbo_b"
                args.operation = "erase"
                args.serial_explicit = case != "implicit"
                if case == "missing_model_record": args.device_identity = self.identity_fixture(directory)
                if case == "invalid_record": args.device_identity = self.identity_fixture(directory, serial="other")
                if case == "malformed_record":
                    args.device_identity = self.identity_fixture(directory)
                    args.device_identity.write_text("{")
                with patch.object(cli, "run", side_effect=transport) as run:
                    if case is None:
                        cli.fastboot(args)
                        self.assertFalse(any(c.args[0][3:4] == ["erase"] for c in run.call_args_list))
                        args.execute = True
                        cli.fastboot(args)
                        self.assertEqual(run.call_args.args[0], ["fastboot", "-s", "abc", "erase", "dtbo_b"])
                    else:
                        args.execute = True
                        with self.assertRaises(cli.ToolError): cli.fastboot(args)
                        self.assertFalse(any(c.args[0][3:4] == ["erase"] for c in run.call_args_list))
                        if case in ("image", "device", "partition", "implicit"):
                            run.assert_not_called()

    def test_dtbo_erase_execution_rechecks_changed_identity(self):
        for field, changed in [("serialno", "other"), ("modelname", "OTHER"),
                               ("current-slot", "a"), ("product", "aurora"),
                               ("partition-size:dtbo_b", "0x6000000")]:
            with self.subTest(field=field), tempfile.TemporaryDirectory() as directory:
                variables = {"product": "taro", "serialno": "abc", "modelname": "TB320FC",
                             "partition-size:dtbo_b": "0x1800000"}
                args, transport = self.fastboot_fixture(directory, "asphalt", **variables)
                args.operation, args.image, args.device, args.partition = "erase", None, "asphalt", "dtbo_b"
                args.serial_explicit = True
                with patch.object(cli, "run", side_effect=transport): cli.fastboot(args)
                variables[field] = changed
                _, transport = self.fastboot_fixture(directory, "asphalt", **variables)
                args.execute = True
                with patch.object(cli, "run", side_effect=transport) as run:
                    with self.assertRaises(cli.ToolError): cli.fastboot(args)
                    self.assertFalse(any(c.args[0][3:4] == ["erase"] for c in run.call_args_list))

    def test_erase_parser_has_no_image_and_defaults_to_check(self):
        with patch.object(cli, "fastboot") as fastboot:
            cli.main(["--serial", "abc", "fastboot", "erase", "--device", "asphalt", "--partition", "dtbo_b"])
            args = fastboot.call_args.args[0]
            self.assertIsNone(args.image)
            self.assertFalse(args.execute)
            self.assertTrue(args.serial_explicit)

    def test_fastboot_argument_errors_never_access_device(self):
        invalid = [
            ["boot"], ["flash", "--partition", "boot_b"],
            ["erase"], ["erase", "--device", "asphalt", "--partition", "dtbo_a"],
            ["erase", "image", "--device", "asphalt", "--partition", "dtbo_b"],
            ["erase", "--device", "asphalt", "--partition", "recovery_b"],
            ["flash", "zero.img", "--device", "asphalt", "--partition", "dtbo_b"],
            ["boot", "image", "--device", "asphalt"],
        ]
        for arguments in invalid:
            with self.subTest(arguments=arguments), patch.object(cli, "run") as run:
                with self.assertRaises(SystemExit): cli.main(["--serial", "abc", "fastboot", *arguments])
                run.assert_not_called()
        with patch.object(cli, "run") as run:
            with self.assertRaises(SystemExit):
                cli.main(["fastboot", "erase", "--device", "asphalt", "--partition", "dtbo_b"])
            run.assert_not_called()

    def test_soc_product_record_cannot_authorize_another_board(self):
        with tempfile.TemporaryDirectory() as directory:
            args, transport = self.fastboot_fixture(directory, "sheng", product="taro", serialno="abc")
            args.device_identity = self.identity_fixture(directory)
            args.serial_explicit = True
            args.execute = True
            with patch.object(cli, "run", side_effect=transport) as run, self.assertRaises(cli.ToolError):
                cli.fastboot(args)
            self.assertFalse(any(c.args[0][3:4] == ["flash"] for c in run.call_args_list))

    def test_deploy_query_accepts_only_manifest_paths(self):
        transport = FakeSsh(query="/nix/store/other")
        args = argparse.Namespace(system="ignored", execute=False,
                                  result_file="/run/deploy.result")
        with patch.object(cli, "local_system", return_value=Path("/nix/store/system")), \
             patch.object(cli, "closure_manifest", return_value=(["/nix/store/system"], b"sha256:test /nix/store/system\n")):
            with self.assertRaisesRegex(cli.ToolError, "outside the selected closure"):
                cli.recovery_deploy(args, transport)
        self.assertFalse(any("deploy-offline" in call for call in transport.calls))



    def test_removed_legacy_commands_are_rejected(self):
        for arguments in (["format-userdata"], ["copy", "/nix/store/system"],
                          ["install-initial", "/nix/store/system", "--bootstrap-info", "b",
                           "--result-file", "/run/x"],
                          ["install-image", "image", "--installer", "x.sh"],
                          ["enter", "--script", "request.sh"]):
            with self.subTest(arguments=arguments), patch.object(cli, "Ssh") as ssh:
                with self.assertRaises(SystemExit):
                    cli.main(["recovery", "--target", "test", *arguments])
                ssh.assert_not_called()
        with self.assertRaises(SystemExit):
            cli.main(["system", "--target", "t", "update", "/nix/store/system"])

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
                                  bootstrap_info="ignored", execute=False)
        with patch.object(cli, "local_system", return_value=Path("/nix/store/system")), \
             patch.object(cli, "closure_manifest", return_value=(["/nix/store/system"], b"sha256:test /nix/store/system\n")), \
             patch.object(cli, "bootstrap_info", return_value=(Path("/tmp/registration"), 4096)), \
             patch.object(Path, "is_file", return_value=True), \
             patch.object(Path, "read_text", return_value="polaris"), \
             patch.object(cli, "stream_closure_tar") as stream:
            cli.recovery_install_initial(args, transport)
        stream.assert_not_called()
        self.assertTrue(any(call[-1] == "--check" for call in transport.calls if call[0] == "shell"))
        self.assertFalse(any("--confirm" in call or "format-root" in call for call in transport.calls))

    def test_initial_install_parser_has_no_result_file(self):
        with patch.object(cli, "Ssh"), patch.object(cli, "recovery_install_initial") as install:
            self.assertEqual(cli.main(["recovery", "--target", "test", "install-initial",
                                       "/nix/store/system", "--bootstrap-info", "bootstrap"]), 0)
        self.assertFalse(hasattr(install.call_args.args[0], "result_file"))

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
        args = argparse.Namespace(system="ignored", bootstrap_info="ignored", execute=True)
        with patch.object(cli, "local_system", return_value=Path("/nix/store/system")), \
             patch.object(Path, "is_file", return_value=True), \
             patch.object(Path, "read_text", return_value="polaris"), \
             patch.object(cli, "closure_manifest", return_value=(["/nix/store/system"], b"manifest")), \
             patch.object(cli, "bootstrap_info", return_value=(Path("/tmp/registration"), 4096)), \
             patch.object(cli, "daemon_submit", return_value=(7, "recovery input 7 token")), \
             patch.object(cli, "stream_closure_tar", side_effect=cli.ToolError("interrupted")):
            with self.assertRaisesRegex(cli.ToolError, "interrupted"):
                cli.recovery_install_initial(args, transport)
        self.assertNotIn(("shell", "rm", "-rf", "/tmp/mobile-device.TEST"), transport.calls)

    def test_initial_resume_uses_daemon_without_resending_closure(self):
        for execute in (False, True):
            transport = FakeSsh(query="aurora")
            args = argparse.Namespace(system="ignored", bootstrap_info="ignored", execute=execute,
                                      resume=True)
            with patch.object(cli, "local_system", return_value=Path("/nix/store/system")), \
                 patch.object(Path, "is_file", return_value=True), \
                 patch.object(Path, "read_text", return_value="aurora"), \
                 patch.object(cli, "closure_manifest", return_value=(["/nix/store/system"], b"manifest")), \
                 patch.object(cli, "bootstrap_info", return_value=(Path("/tmp/registration"), 4096)), \
                 patch.object(cli, "recovery_daemon", return_value=True), \
                 patch.object(cli, "stream_closure_tar") as stream:
                cli.recovery_install_initial(args, transport)
            stream.assert_not_called()
            self.assertTrue(any("--resume-check" in call for call in transport.calls))
            self.assertEqual(any("--resume-confirm" in call for call in transport.calls), execute)
            self.assertIn(("shell", "rm", "-rf", "/tmp/mobile-device.TEST"), transport.calls)

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

class RecoveryDaemonTests(unittest.TestCase):
    def test_protocol_selection_rejects_unknown_version(self):
        transport = FakeSsh()
        with patch.object(transport, "shell", return_value=subprocess.CompletedProcess([], 1, b"", b"")):
            with self.assertRaisesRegex(cli.ToolError, "Rust recovery daemon"):
                cli.recovery_daemon(transport)
        with patch.object(transport, "shell", return_value=subprocess.CompletedProcess([], 0, b"1\n", b"")):
            self.assertTrue(cli.recovery_daemon(transport))
        with patch.object(transport, "shell", return_value=subprocess.CompletedProcess([], 0, b"2\n", b"")):
            with self.assertRaises(cli.ToolError):
                cli.recovery_daemon(transport)

    def test_task_submission_and_reconnect_use_exact_task_identity(self):
        transport = FakeSsh(json.dumps({"version": 1, "snapshot": {"task": {"id": 987}}, "token": "input-token"}))
        task_id, command = cli.daemon_submit(transport, ["deploy-offline", "m", "s", "1", "--confirm"])
        self.assertEqual(task_id, 987)
        self.assertEqual(shlex.split(command), ["recovery", "input", "987", "input-token"])
        transport.query = json.dumps({"task": {"id": 987, "active": False, "result": "verified", "error": None}})
        cli.daemon_wait(transport, 987)
        transport.query = json.dumps({"task": {"id": 988, "active": False, "result": "other task"}})
        with self.assertRaises(cli.ToolError):
            cli.daemon_wait(transport, 987)
        transport.query = json.dumps({"task": {"id": 987, "active": False, "error": "input interrupted"}})
        with self.assertRaises(cli.ToolError):
            cli.daemon_wait(transport, 987)
        self.assertFalse(any(".result" in str(call) for call in transport.calls))
