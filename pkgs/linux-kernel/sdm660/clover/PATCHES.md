# Clover kernel

[中文](PATCHES.zh.md) · [Clover guide](../../../../docs/clover/README.md)

The queue targets Linux 7.3. See the [shared kernel status](../../README.md).

`devices.clover.kernel` has a Linux 7.3 patch queue with the ordered
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
| 0030 | Shared ath10k driver | Keep the TxBF setting on disassociation; resetting it crashes WCN3990 firmware on every disconnect |
| 0031–0032 | SDM630/660 common | CPU idle: drop the cluster idle states, which PSCI rejects on every request, and correct the CPU retention parameter so idle CPUs sleep instead of retrying |
| 0033 | SDM630/660 common | Keep the generic cpufreq-dt driver off these SoCs |
| 0034–0045 | SDM630/660 common | CPR3/CPRh voltage driver with SDM660 support: vendor open-loop corner voltages, closed loop off, speed bin 1 with CPR fusing revision 2 only, and four local corrections |
| 0046–0047 | Shared OPP core | Tolerate a second debugfs link for a CPU OPP table, and drop the reference of the existing link |
| 0048–0052 | SDM630/660 common | Program the OSM from the CPRh corner voltages; SDM660 follows the vendor sequence, with local corrections for the domain count, an OSM already running and the error paths |
| 0053–0054 | SDM630/660 common | L2 SAW: vendor AVS value for the silver cluster, and keep the boot firmware SAW control registers |
| 0055–0057 | SDM660 common and Clover | CPRh, OSM, L2 SAW, fuse and CPU cooling nodes; Clover corner plan, first with a frequency limit, then the full table |
| 0058–0060 | SDM630/660 common | CPRh closed loop: vendor target quotients, read-only CPRh state in debugfs, and the closed-loop switch |

0016 uses the Polaris 7.3 WCN3990 fix. 0017, 0024 and 0025 are separate local
corrections. 0028 protects 0027 against an empty-list dereference while
preserving 7.3 recovery behavior. Patches to existing 7.3 files use hunks;
new files carry their source attribution. Clover's charger limit remains at
the baseline value because a higher limit lacks thermal validation. Qualcomm
Sensor Manager remains unavailable: the firmware package does not provide
`qcom/sensors/sns.reg`, and the userspace path is unverified.

CPU frequency scaling (0033–0060) programs the CPRh and OSM the way the
vendor kernel does. Silver scales from 300 MHz to 1843.2 MHz and gold from
300 MHz to 2208 MHz; above the 872 mV APM threshold (silver 1747.2 MHz, gold
1958.4 MHz and up) the memory arrays switch from VDD_MX to the APC supply.
In open loop (0033–0057) each frequency runs at its fused open-loop voltage;
the clocks, rail voltages and APM switch were checked on the device for every
frequency. With closed loop (0058–0060) the CPRh lowers each corner from its
open-loop voltage towards its floor, following the vendor target quotients;
closed-loop operation is not validated on the device yet. Revert 0060 alone
to return to open loop. Parts other than speed
bin 1 with CPR fusing revision 2 keep the bootloader CPU clocks, and the CPR
driver logs why. The CPU thermal zones throttle their cluster at the 70 °C
passive trip.

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
