# Device kernel configuration

Each device has exactly one kernel, `devices.<device>.kernel`: the release
provided by the locked Nixpkgs input (`linuxPackages_latest`, currently
7.3.4) plus the device's ordered patch queue. The installed system and RAM
recovery use the same kernel; there are no pinned or fallback kernel versions.
The build platform is selected through the package outputs: under
`x86_64-linux` everything cross-compiles for AArch64 (an x86_64-only machine
suffices), and under `aarch64-linux` it builds natively. Within one build
platform, a device's system, recovery and `kernel` outputs share one kernel
derivation; the platform evaluation check asserts this for both platforms.

Every queue targets the `expectedVersion` in [`default.nix`](default.nix).
When Nixpkgs moves to another release, evaluation fails with a message to port
the queues: port every device queue to the new release (see the
[development guide](../../docs/development.md#kernel-patch-queues)) and update
`expectedVersion`. The kernel's `patchQueueStatus` reports `expectedVersion`
and `evaluatedVersion` for tooling. Evaluation success is not a build or
deployment validation.

All eight queues target 7.3.4. Dodge no longer carries the generic PHY
module-reference race fix, included in 7.3.4 (stable `8a9f16b5237e`, upstream
`090055ee6295`). FastRPC PDR subscriptions preserve the upstream reserved-memory
helper; Clover/Polaris WLED IRQ-depth tracking uses upstream initial brightness;
Polaris retains its ramoops reservation alongside the extended XBL region.
Marble keeps both upstream restricted IOVA state and the secure encoder ARP pool,
and its audio ownership patches coexist with upstream position-buffer UNMAP fixes.
Retained patches keep their existing shared/board-owned paths and ordered lists.
The 7.3.4 source preparation uses the same exact checked Nixpkgs plus local
preparation contract as 7.3.1. Source replay and compilation do not establish
hardware behavior; test changed kernel and graphics paths on each device.

Configuration is applied in this order:

1. The board's checked-in `configfile`.
2. [Shared capabilities and reductions](config/common.nix).
3. The SoC's `config.nix`.
4. The board specification's `configOverrides`.

Use `lib.kernel.yes`, `module`, or `no` in overrides. Put shared policy in the
common layer, chip requirements in the SoC layer and board exceptions in the
board specification. `olddefconfig` resolves dependencies; `postConfigure`
checks all overrides and the resulting enabled `PINCTRL` symbols before compilation.

## nftables support

Every SoC and kernel variant includes the shared [nftables configuration](config/nftables.nix).
IPv4/IPv6, inet, ARP, bridge and netdev tables, connection tracking, NAT/redirect,
NFQUEUE, FIB lookups, socket matching, transparent proxying, logging, limits,
sets/maps (part of the nf_tables core) and flow offload support are built in.
This also covers the kernel facilities used by TUN auto-redirect. Enabling these
capabilities does not install firewall rules or enable a proxy service.

## Bluetooth profiles

Every kernel with Bluetooth includes the shared
[Bluetooth profile configuration](config/bluetooth.nix): RFCOMM (hands-free
headset audio and serial profiles), BNEP (network tethering over Bluetooth)
and HIDP (classic Bluetooth keyboards and mice). Kernels whose baseline does
not select them build them as modules; a baseline that already selects them
keeps its choice.

## Peripheral and pinctrl policy

The configuration keeps USB-C/DP, USB hubs, USB networking, external storage,
card readers, keyboards and mice, including their host, role-switch, USB
Storage/UAS, SCSI and HID dependencies. Asphalt and Clover also keep the MMC/
SDHCI path for their built-in microSD slots. FAT and exFAT remain available.

[Qualcomm clock and interconnect reductions](config/qcom-soc-drivers.nix) are
restored by each SoC layer where needed. Shared RPM/RPMh, GDSC/PLL/APCS and
interconnect helpers follow Kconfig dependencies. The SoC layers also restore
the required pin controllers:

| Device | SoC controller | Audio controller | PMIC support |
| --- | --- | --- | --- |
| Asphalt / Unicorn | `PINCTRL_SM8475` | `PINCTRL_SM8450_LPASS_LPI` | `PINCTRL_QCOM_SPMI_PMIC` |
| Polaris | `PINCTRL_SDM845` | WCD9340 GPIO in `drivers/gpio` | `PINCTRL_QCOM_SPMI_PMIC` |
| Sheng | `PINCTRL_SM8550` | `PINCTRL_SM8550_LPASS_LPI` | `PINCTRL_QCOM_SPMI_PMIC` |
| Clover | `PINCTRL_SDM660` | `PINCTRL_SDM660_LPASS_LPI` | `PINCTRL_QCOM_SPMI_PMIC` |
| Marble | `PINCTRL_SM8475` | `PINCTRL_SM8450_LPASS_LPI` | `PINCTRL_QCOM_SPMI_PMIC` |

Audio pinctrl also needs `PINCTRL_LPASS_LPI`; Asphalt and Unicorn use the SM8450
audio controller compatible. See the [Unicorn SM8475 queue](sm8475/README.md);
Asphalt retains its independent upstream queue.
Configuration checks do not establish hardware function.
Test display, touch, storage, audio and external peripherals on the target
before deploying a changed kernel.

[中文](README.zh.md)
