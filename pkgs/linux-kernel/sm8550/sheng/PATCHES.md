# Sheng kernel

[中文](PATCHES.zh.md) · [Sheng guide](../../../../docs/sheng/README.md)

`devices.sheng.kernel` and its `kernel-mainline` alias use the pinned
[`ianchb/sm8550-mainline` Linux 7.2.6 source](https://github.com/ianchb/sm8550-mainline/commit/42f3b40c702abbc37c3a04c95af008cd283aeaf3)
and its two local patches. This version boots through installed U-Boot/EFI and
connects to Wi-Fi on Sheng. The source revision and hash are in
[mainline.nix](mainline.nix). `devices.sheng.kernel-testing` retains the Nixpkgs
7.3-rc5 [patch series](series.nix). Each patch names its source commits and
local 7.3 adaptations; [ORIGINS.md](patches/ORIGINS.md) retains original
authors, dates, messages and trailers. The 7.3 generation boots but currently
fails WCN7850 firmware loading. Both packages use `config.aarch64` and build
`sm8550-xiaomi-sheng.dtb`.

On an x86_64 host, this output uses an x86_64 build platform and an AArch64
host platform. Build the kernel with:

```sh
nix build .#devices.sheng.kernel --builders '' \
  --out-link tmp/systemd-artifacts/devices.sheng.kernel
nix build .#devices.sheng.kernel-mainline --builders '' \
  --out-link tmp/systemd-artifacts/devices.sheng.kernel-mainline
nix build .#devices.sheng.kernel-testing --builders '' \
  --out-link tmp/systemd-artifacts/devices.sheng.kernel-testing
```

The 7.3 series includes the board, display, input, battery, audio, camera, Type-C,
DP, WCN7850 and FPC1553 fingerprint changes needed for the current
configuration. Fingerprint userspace requires the FPC1553 driver and DT node.
The 7.3 kernel boots, but its Wi-Fi regression and remaining peripherals need
device validation before replacing the 7.2.6 default.

The FPC1553 driver has two known limitations: a
prepare disable/enable cycle does not re-enable an already requested IRQ, and
remove unregisters sysfs after releasing its resources. Neither path has been
validated on Sheng.

Kernel patches follow the upstream Linux GPL-2.0 terms and any license
notices in the changed files.
