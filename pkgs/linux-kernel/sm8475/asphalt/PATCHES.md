# Y700 2023 kernel patches

[中文](PATCHES.zh.md) · [Y700 2023 guide](../../../../docs/asphalt/README.md)

The `asphalt` kernel uses Linux 7.3-rc5 from the locked Nixpkgs input. The
ordered queue is defined in [`series.nix`](series.nix), and the kernel
configuration is [`kernel.config`](kernel.config).

| Patch | Area |
| --- | --- |
| 0001 | SM8475 core support |
| 0002 | Display, panel, and backlight |
| 0003 | Touchscreen |
| 0004 | PCIe and Wi-Fi |
| 0005 | UFS clocks |
| 0006 | Y700 2023 device tree |
| 0007 | Video codec |
| 0008 | USB and audio wiring |
| 0009 | CS35L45 DSP firmware name |
| 0010 | QMP hardware port selection |
| 0011 | Audio service setup |
| 0012 | SM8450 CAMSS |
| 0013 | Camera shared RCG clocks |
| 0014 | WL2864C regulators |
| 0015 | HI1339, S5K4H7 and SC202CS sensors |
| 0016 | TB320FC camera wiring and macro PHY lane mask |
| 0017 | Camera GDSC register retention |
| 0018 | DisplayPort graph, primary FSA4480 AUX mux and QMP DP orientation |
| 0019 | DP debugfs connector initialization |
| 0020 | Preserve an enabled Lucid OLE PLL during bootloader display handoff |

Build the kernel on an x86_64 or AArch64 Linux host with `nix build .#devices.asphalt.kernel`.
For an x86_64 build, the derivation runs on x86_64 and produces an AArch64
kernel. Kbuild uses `ARCH=arm64`, the AArch64 target prefix, and Clang/LLD from
`buildPackages`; no AArch64-hosted LLVM tools are needed.
Linux kernel patches follow the upstream GPL-2.0 terms and the SPDX notices
of the files they modify.

## Camera sources

- 0012/0013 import Aaron Bockelie's SM8450 CAMSS and shared-RCG patches from
  [`d08afbea`](https://github.com/aaronsb/sm-x800-linux/commit/d08afbea7ba594092a104089aa5e124a91b06c7c)
  and [`04f99a72`](https://github.com/aaronsb/sm-x800-linux/commit/04f99a725bc63343683b54dea1aa8f698c4c3b13).
  Original author, date, commit message and source are retained; only the
  relevant kernel patches are extracted from those packaging commits.
- 0014 implements WL2864C regulators from the
  [manufacturer's register specification](https://www.ovt.com/wp-content/uploads/2022/09/OV-WL2864C-v2.pdf).
- 0015 adds full-resolution RAW10 modes for HI1339, S5K4H7 and SC202CS.
  Tables use TB320FC's 24 MHz sensor configuration, with source hashes in the
  header. Register semantics and GPL references are listed in the patch.
- 0016 wires the actual board supplies, GPIOs and CSI ports, and preserves the
  one-lane macro camera's PHY mask. It is a local follow-up to 0012.
- 0017 imports the same author's camera GDSC register-retention patch from
  `04f99a72`, matching all nine `qcom,retain-regs` nodes in the TB320FC vendor DT.

S5K4H7 control semantics were also checked against the [MediaTek GPL driver (2019)](https://github.com/Samsung-MT6769-Devs/android_kernel_samsung_mt6768/blob/4e0fdc5e6f4c605813c569392f1c255ac4ef66ea/drivers/misc/mediatek/imgsensor/src/common/v1_1/s5k4h7_mipi_raw/s5k4h7mipiraw_Sensor.c).

## Bootloader display handoff

0020 imports [Esteban Urrutia's Lucid OLE PLL fix](https://lore.kernel.org/all/20260713-sm8450-qol-dispcc-v3-3-56fd05822270@proton.me/)
without code changes. Keeping an inherited PLL enabled lets the MDP RCG park
safely before Linux takes over. Pair this kernel with the U-Boot
`/reserved-memory/splash_region` reservation; renaming that node alone breaks
display and touch with older kernels. See the [firmware requirements](../../../u-boot/sm8475/README.md).
