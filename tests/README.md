# Host tests

[中文](README.zh.md)

These tests run on the build host, not on a phone. They use scripted peers and
fixtures to check the boot-image formats, U-Boot helpers, storage operations,
firmware archives and the Rust recovery tool. Hardware checks stay separate and
are listed in the device guides.

Run the flake checks for the full host suite:

```sh
nix flake check --no-build --system x86_64-linux
```

The `host-tools` and `recovery-daemon` checks build and run the Python and Rust
unit tests. Kernel-driver harnesses compile selected production source files
against mocks; pass `--source /path/to/linux` and optionally `--cc clang`.
These harnesses do not prove firmware behavior, interrupt timing, power
switching or driver-core lifetime on hardware.
