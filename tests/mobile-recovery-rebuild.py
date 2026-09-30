#!/usr/bin/env python3
"""Run the real offline rebuild guard with fake Nix/boot tools and isolated files."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "pkgs/mobile-recovery-deploy/rebuild.sh"
SCRATCH = SOURCE.parents[2] / "tmp"
SCRATCH.mkdir(exist_ok=True)

class RebuildTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=SCRATCH)
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for d in ['bin', 'boot/EFI/BOOT', 'boot/loader/entries', 'var/lib', 'run/current-system/sw/bin', 'nix/var/nix/profiles', 'new-system']:
            (self.root/d).mkdir(parents=True, exist_ok=True)
        (self.root/'new-system/mobile-efi').touch()
        (self.root/'boot/EFI/BOOT/BOOTAA64.EFI').write_text('EFI')
        (self.root/'boot/loader/entries/new.conf').write_text(f'options init={self.root}/new-system/init\n')
        text=SOURCE.read_text()
        for prefix in ['/run/current-system', '/var/lib', '/nix/var', '/boot']:
            text=text.replace(prefix,str(self.root)+prefix)
        self.script=self.root/'rebuild'
        self.script.write_text(text)
        self.tool('findmnt', '#!/bin/sh\necho "${MOUNT_MODE:-rw},relatime"\n')
        self.tool('readlink', f'#!/bin/sh\necho {self.root}/new-system\n')
        self.tool('sync', '#!/bin/sh\nexit 0\n')
        real=self.root/'run/current-system/sw/bin/nixos-rebuild'
        real.write_text(f'#!/bin/sh\nprintf "%s\\n" "$@" > {self.root}/called\nexit "${{NIX_EXIT:-0}}"\n')
        real.chmod(0o755)
    def tool(self,name,text):
        p=self.root/'bin'/name;p.write_text(text);p.chmod(0o755)
    def run_guard(self,*args,**env):
        return subprocess.run(['sh',str(self.script),*args],env={**os.environ,'PATH':str(self.root/'bin')+':'+os.environ['PATH'],**env},capture_output=True,text=True)
    def test_rejects_live_activation_and_other_targets_before_writes(self):
        for args in [('switch',),('test',),('boot','--target-host=another'),('boot','--profile-name','other')]:
            with self.subTest(args=args):
                self.assertNotEqual(self.run_guard(*args).returncode,0)
                self.assertFalse((self.root/'called').exists())
                self.assertFalse((self.root/'var/lib/mobile-offline-rebuild').exists())
    def test_readonly_rejects_before_profile_update(self):
        self.assertNotEqual(self.run_guard('boot',MOUNT_MODE='ro').returncode,0)
        self.assertFalse((self.root/'called').exists())
    def test_failed_install_leaves_pending_and_successful_retry_clears_it(self):
        self.assertNotEqual(self.run_guard('boot','--rollback',NIX_EXIT='1').returncode,0)
        self.assertTrue((self.root/'var/lib/mobile-offline-rebuild/pending').exists())
        result=self.run_guard('boot','--rollback')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse((self.root/'var/lib/mobile-offline-rebuild/pending').exists())
        self.assertEqual((self.root/'called').read_text().splitlines(),['--no-reexec','boot','--rollback'])
    def test_missing_boot_entry_is_not_reported_as_success(self):
        (self.root/'boot/loader/entries/new.conf').write_text('options init=/wrong/init\n')
        self.assertNotEqual(self.run_guard('boot').returncode,0)
        self.assertTrue((self.root/'var/lib/mobile-offline-rebuild/pending').exists())
    def test_incomplete_initial_install_is_not_overridden(self):
        p=self.root/'var/lib/mobile-efi-preparation';p.mkdir();(p/'pending').touch()
        self.assertNotEqual(self.run_guard('boot').returncode,0)
        self.assertFalse((self.root/'called').exists())

if __name__=='__main__':unittest.main()
