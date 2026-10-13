# Clover kernel

[中文](PATCHES.zh.md) · [Clover guide](../../../../docs/clover/README.md)

The queue targets Linux 7.3-rc6. See the [shared kernel status](../../README.md).

`devices.clover.kernel` has a Linux 7.3-rc6 patch queue with the ordered
[patch series](series.nix). It cross-builds from x86_64 to AArch64 and is
selected by the system and RAM recovery. It has not been boot-tested on the device.

Build the kernel from an x86_64 host with the repository's cross package
scope:

```console
nix build .#devices.clover.kernel --out-link result-kernel
```

Each patch keeps the source author, date, message and trailers. Its
`Source-Commit` and `Scope` headers identify provenance and reuse:

| Patches | Scope | Purpose |
| --- | --- | --- |
| 0001–0004 | SDM630/660 or PM660 common | PM660 fuel gauge node and audio codec/clock nodes |
| 0005–0006 | Clover LTE only | Board binding and device tree |
| 0007–0009 | PMI8998 PMIC common | Fuel gauge driver and bindings |
| 0010–0011 | Panel generic | NT51021 driver and binding used by Clover |
| 0012–0013 | SDM660/SDM630 common | MSS and MDP5 SMMU identity domains |
| 0014–0017 | Shared WLED/ath10k drivers | IRQ balance, key response, WCN3990 VHT mask and initial IRQ-state correction |
| 0018–0025 | SDM630/660 GPU common | GPU clock switching, OPP/speedbin support, SDM660 nominal-speed cap and two local corrections |
| 0026 | SDM630/660 audio common | APR audio protection domains required for q6afe clocks and AFE ports |
| 0027–0028 | Shared ath10k driver | Persistent WCN3990 split A-MSDU receive state and RFC v3 correction |

0016 uses the Polaris 7.3 WCN3990 fix. 0017, 0024 and 0025 are separate local
corrections. 0028 protects 0027 against an empty-list dereference while
preserving 7.3 recovery behavior. Patches to existing 7.3 files use hunks;
new files carry their source attribution. Clover's charger limit remains at
the baseline value because a higher limit lacks thermal validation. Qualcomm
Sensor Manager remains unavailable: the firmware package does not provide
`qcom/sensors/sns.reg`, and the userspace path is unverified.

The PMI8998 fuel gauge has source defects in its fallback
charge-status calculation, notifier error branch and removal cleanup.
The GPU clock code has an ineffective rate-range block;
fixed OPP operation compiled, but frequency behavior needs device
validation. The ath10k key-response change should be checked during
disconnect/reconnect. No device runtime validation has been performed.

The kernel builds `sdm660-xiaomi-clover.dtb`. Its configuration keeps
MSM DRM, NT51021, Qualcomm firmware helpers, USB host/role switching,
external USB devices and the built-in microSD path available to the
system and RAM recovery.

Kernel patches follow the upstream Linux GPL-2.0 terms and any license
notices in the changed files.
