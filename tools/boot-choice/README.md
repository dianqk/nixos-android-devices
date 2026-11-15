# Native boot-choice tooling

[中文](README.zh.md)

This directory contains the Rust host/native implementation shared by
`boot-choice-native`, `boot-choice-efi` and the KernelSU module. It performs
bounded offline regular-file operations and guarded read-only status; live
install/reboot operation is exposed only through the matching boot-choice
product and firmware context.

Use the public [boot-choice guide](../../docs/boot-choice.md) for supported
baselines, build commands and safety limits. Do not bridge offline file packing
to block devices with shell writes.
