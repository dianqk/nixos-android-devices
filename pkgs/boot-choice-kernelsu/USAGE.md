# Dodge same-slot boot choice (KernelSU module)

This module installs a static AArch64 `boot-choice` owner and matching template.
It does not install KernelSU, provide an Android boot image or replace RAM
recovery. Read the public [boot-choice guide](../../docs/boot-choice.md) for the
supported baseline, safety limits and complete workflow.

1. Keep working Android, independent RAM recovery and rollback assets.
2. Install or patch KernelSU into the supported current Android kernel first.
3. Install `dodge-boot-choice-kernelsu.zip` in KernelSU Manager.
4. Open the module WebUI to read status. Use the explicit switch buttons only
   when you intend to change the next boot target.

With an Android system overlay:

```sh
su -c 'boot-choice status'
su -c 'boot-choice reboot nixos'
```

The module action is read-only status. Entry, refresh and startup never request a
reboot. Host validation is not hardware or power-loss acceptance.
