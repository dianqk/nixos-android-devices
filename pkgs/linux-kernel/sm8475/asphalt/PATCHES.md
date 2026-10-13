# Y700 2023 kernel patches

[中文](PATCHES.zh.md) · [Y700 2023 guide](../../../../docs/asphalt/README.md)

The queue is adapted to the current Linux 7.3-rc6 lock. Independent patch replay,
resolved configuration checks, the board DTB and the 43 C files touched by the
queue pass validation. A full kernel build and device tests remain separate.
See the [shared kernel status](../../README.md) for the other devices.

The `asphalt` patch queue targets Linux 7.3-rc6. The
ordered queue is defined in [`series.nix`](series.nix), and the kernel
configuration is [`kernel.config`](kernel.config).

| Patch | Area |
| --- | --- |
| 0001 | SM8475 core support |
| 0002 | Display, panel, and backlight |
| 0003 | Touchscreen |
| [Shared PCIe fix](../../patches/pcie-qcom-iommu-cells.patch) | Parse IOMMU cells for PCIe BDF-to-SID mapping |
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
| `iris-hfi-gen2-{decode-order,capture-pool}.patch` | HFI gen2 decode-order controls and larger decoder capture pools |
| [Shared GMU series](../../patches/gmu-sync-state/README.md) | Bind a driver to the GMU so GCC/GPUCC `sync_state()` completes |
| 0026 | Disable the unused QCE node (driver is BROKEN upstream) so interconnect `sync_state()` completes |
| 0027 | Power down UFS controller/device/PHY in system suspend (no PHY retention across CX collapse) |

Build the kernel on an x86_64 or AArch64 Linux host with `nix build .#devices.asphalt.kernel`.
For an x86_64 build, the derivation runs on x86_64 and produces an AArch64
kernel. Kbuild uses `ARCH=arm64`, the AArch64 target prefix, and Clang/LLD from
`buildPackages`; no AArch64-hosted LLVM tools are needed.
Linux kernel patches follow the upstream GPL-2.0 terms and the SPDX notices
of the files they modify.

## Shared PCIe fix

Asphalt and Sheng's 7.3 series share the upstream PCIe parser patch above.
It replaces Asphalt's former local 0004 with the full original message and
trailers; the only code difference is restoring the upstream warning text.
SDM845 uses different PCIe operations and does not call this SID parser, so
Polaris does not select this patch.

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

## Battery notification serialization

0026 makes the notification-enable worker use the existing battery-manager
request mutex, like property reads. Both paths share a completion, so overlapping
requests during ADSP startup can wake the wrong waiter. This local fix changes
no charging limits or policy and leaves PDR callbacks nonblocking. Late replies
after a request timeout remain a separate protocol limitation.

## Iris VA-API prerequisites

`iris-hfi-gen2-{decode-order,capture-pool}.patch` import Xilin Wu's [decode-order controls](https://github.com/radxa-pkg/libva-v4l2/blob/0e4ce1e05da1d0a92b342efc2090b9e4987035e1/patches/0001-media-iris-support-decode-order-output-on-HFI-gen2.patch)
and [capture-pool limit](https://github.com/radxa-pkg/libva-v4l2/blob/0e4ce1e05da1d0a92b342efc2090b9e4987035e1/patches/0002-media-iris-allow-larger-capture-buffer-pools-on-HFI-.patch)
from libva-v4l2 v1.0.0 without modifications; the original patch headers,
messages and sign-offs are retained. These are libva-v4l2's companion patches,
not a claim that the changes have merged into upstream Linux.

Synchronous VA-API clients need decoded pictures before submitting later
input. The display-delay controls enable HFI gen2 decode-order output on
request; clients that do not set them retain the firmware default. The second
patch allows HFI gen2 decoders to request up to 64 capture buffers without
changing the minimum allocation or encoder queues. These prerequisites do not
by themselves establish working decoding on every profile.
