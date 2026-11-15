# Alldocube iPlay 80 mini Ultra (t880)

[中文](README.zh.md) · [All devices](../README.md) · [Support status](status.md) · [Install guide](install.md)

Status: **experimental; NixOS boots on slot A** (U-Boot → systemd-boot; niri on the panel with GPU rendering; no touch yet). The board is
also sold as 酷比魔方掌玩 Mini4 Ultra (Android device `T880`, board
`p5n1_kb_t880_8883_b0`); its SoC is the MediaTek MT8883 part of the
MT6897/Dimensity 8300 class. It ships with Android 16 and a 6.1 GKI kernel.

The U-Boot image uses values read from a T880 (its runtime device tree, boot
headers, LK log and GPT) and runs on the device: screen, UFS (read), keys,
watchdog and USB fastboot/ACM at High Speed over a USB 2.0 cable. Direct
Type-C connections and SuperSpeed are not verified yet. Linux 7.3 and the
RAM recovery boot through U-Boot raw FIT staging and `bootm`: screen console (simpledrm),
eight CPUs, UFS with all LUNs and partitions, USB NCM networking with SSH.
`mobile-device fastboot`
refuses T880 images until the stock fastboot identity is checked and flashing
is approved.

## Hardware support

| Function | State | Notes |
| --- | --- | --- |
| Boot (U-Boot on slot A, systemd-boot, generations, rollback) | Working | Android stays on slot B; `fastboot set_active b` returns to it |
| RAM recovery (screen menu, USB networking, partitioning, image install) | Working | Host-supplied FIT via U-Boot USB fastboot |
| Storage (UFS) | Working | UFS 4.0 HS-G5 x2, eight hardware queues (MCQ) |
| USB device mode (networking, SSH, U-Boot fastboot/ACM) | Working | SuperSpeed (5 Gbit/s) in Linux with the plug orientation from the Type-C controller (tested in one orientation); U-Boot runs High Speed |
| USB Type-C and PD | Working | MT6375 port controller, sink only: orientation and a 5 V PD contract (tested with a PD 3.0 charger and a Mac port) |
| Display | Working | 1600x2560 through mediatek-drm on both display pipes (dual DSI, C-PHY, DSC), 144/120/90/60 Hz, DPMS; simpledrm on the bootloader's framebuffer as the boot console until mediatek-drm takes over; physical scanout as the shipped default, with GCE/CMDQ updates and both MM IOMMUs held runtime-active; IOMMU translation for the display is open but deferred, because the display address mode is owned by the device firmware (display address translation is owned by device firmware); intermittent half-black boots, one DSI1 initialization timeout and GCE activity during DPMS off remain open; niri example session |
| GPU (Mali-G615, panthor) | Working | 265 MHz-1.4 GHz; needs a Mesa with v11 support (OpenGL ES 3.1; Vulkan through PanVK, not conformant) |
| Volume keys | Working | The power key (MT6363 PMIC) registers as an input device; its interrupt path is not verified yet |
| Direct USB-C and USB-C-to-A cables | Not tested | |
| Touchscreen | Working | Novatek NT36523N, 10 touches |
| CPU frequency scaling | Working | `mtk-cpufreq-hw`: 0.48-2.2 GHz (4x A510), 0.4-3.2 GHz (3x A715), 0.4-3.35 GHz (A715), schedutil |
| Thermal sensors and CPU throttling | Working | 28 LVTS zones (CPU, DSU, SoC, modem) read from the bootloader's configuration; the MCUPM firmware holds the CPUs at about 95 °C; kernel CPU trips at 103/108 °C as a backstop, shutdown at 115 °C. There is no skin/case temperature control yet: avoid long full-load runs, especially while charging |
| GPU frequency scaling | Working | 65 GPUEB operating points, 265 MHz-1.4 GHz (panthor devfreq); throttled at 95 °C on the SoC sensors |
| Backlight | Working | `pwm-backlight` on the display PWM, 1024 levels, default 256; `bl_power` blanks the panel |
| RTC | Working | MT6685 over SPMI; keeps time across reboots |
| Battery and charging | Experimental | MT6375 battery/input reporting and bounded fixed 5 V charging; a 120 s test maintained positive charging with the example desktop screen on. Normal automatic charging and termination settings passed boot and a 120 s observation; full charge/recharge is unverified |
| Wi-Fi | Working | MediaTek connsys drivers (out of tree), NetworkManager/iwd; needs the stock files, see [Wi-Fi](wifi.md) |
| Bluetooth | Experimental | `hardware.t880.connectivity.bluetooth.enable`: BlueZ, scans and connections; controller idle/wake and hardware power cycling, see [Wi-Fi](wifi.md#bluetooth-experimental) |
| Audio | Not yet | |
| USB host/OTG, PD above 5 V | Not yet | |
| DisplayPort over USB-C | Not yet | The Type-C switches, the DP TX and a second display pipe are in place (a `DP-1` connector that stays disconnected); not tested with a monitor, no picture yet |
| CPU idle | Working | Core-off states of every cluster through PSCI, after the MCUPM boot contact (`mtk-mcupm`); cluster and MCUSYS off states not yet |
| Suspend | Not yet | |
| Hardware video decode | Partial | 8-bit V4L2/VA-API H.264/HEVC, VP9 profile 0 and AV1 Main; exact crop/seek and exported-surface checks pass; CPU conversion/replay can be costly |
| Hardware video encode | Experimental | V4L2 and stock FFmpeg VA-API: H.264 Main CAVLC and HEVC Main, explicit AVBR/GOP30, one reference, no B frames and forced IDR. HEVC is limited to 1080p area; its closing firmware FREE error remains |
| Sensors, microSD, vibrator, cameras, cellular | Not yet | |

## What exists

| Output | Content |
| --- | --- |
| `devices.t880.u-boot` (= `boot`) | Header v4 boot image for slot A: U-Boot v2026.10 as an LZ4 kernel, no ramdisk (like the stock boot image). |
| `devices.t880.recovery` | The same U-Boot image with the recovery FIT (kernel, initrd, DTB) as its ramdisk; the FIT itself is its `payload` attribute, at most 128 MiB. Start its raw FIT with the staging commands in the install guide; see the limits below. |
| `devices.t880.kernel` | Linux 7.3 with the [T880 queue](../../pkgs/linux-kernel/mt6897/t880/PATCHES.md). |
| `devices.t880.system`, `boot-files`, `bootstrap-info` | The example: a niri session on the panel (mediatek-drm) with USB networking. The GPU (Mali-G615, panthor) needs a Mesa with v11 support (Mesa main or a backport); the Mesa 26.2 in nixpkgs renders with llvmpipe. |

```sh
nix build .#devices.t880.u-boot --out-link result-u-boot
nix build .#devices.t880.recovery --out-link result-recovery
nix build .#devices.t880.kernel --out-link result-kernel
```

### Modem metadata upgrade order

Kernels with queue patch 0182 require U-Boot patch 0036 to forward the actual
LK modem descriptor. Upgrade slot-A U-Boot **before** installing that kernel,
using the recovery firmware-update commands.
With an older U-Boot, Linux still boots but cellular metadata is unavailable
and the modem stays disabled. NixOS generation updates do not replace `boot_a`.
Runtime descriptor forwarding, normal modem startup and RAM recovery through
the updated U-Boot are verified. Retain a working bootloader image and the
[USB RAM recovery path](install.md#2-start-the-recovery-from-ram).

### Modem stop failures

The modem owner waits for completed FSM stop and the raw GATED state before
reporting completion. Pending stops return EINPROGRESS; a platform/pre-stop
failure returns its latched error and the owner exits nonzero. Reboot before
another modem start after a latched failure. Module unload and manual unbind
remain unsupported; GATED alone does not prove physical domain-off or complete
DMA/transport teardown.

NixOS uses slot A; Android (GSI on the stock vendor, Virtual A/B) stays on
slot B, and `fastboot set_active b` returns to it. The stock LK on slot A
loads `boot_a`; vendor_boot, init_boot, dtbo and vbmeta stay stock. U-Boot
takes memory, reserved regions, the initrd window and the framebuffer from the
FDT that LK passes, services the watchdog and draws on the LK framebuffer at a
lowered backlight, idling with WFE. Its default flow boots a recovery FIT
found in the boot image's ramdisk, else systemd-boot from the FAT `linux-boot`
partition, else waits in USB fastboot (serial number from
LK, 128 MiB download buffer): `fastboot stage` downloads the raw FIT, then U-Boot `bootm` starts it; `fastboot
oem console` shows the console, `fastboot continue` switches to a USB ACM
console (`run fastboot` returns), and `fastboot reboot-bootloader` enters the
stock LK fastboot. The boot menu (hold Volume Down) times out after 10 seconds
and offers the same choices. If no USB host connects within `autoreset_s` (90)
seconds, U-Boot lets the watchdog reset the device; LK counts that as a
failed boot and falls back to Android on slot B after a few attempts. The
only storage U-Boot writes is the successful bit of slot A in misc, after it
loaded `/EFI/BOOT/BOOTAA64.EFI` from `linux-boot` (see the boot design). See the [boot design
reference.

LK cannot deliver the RAM recovery inside `boot_a`: a 47 MB FIT as the boot
image ramdisk made LK assert while loading `boot_a`, and its 64 MiB ramdisk
window is shared with the stock vendor ramdisk (about 27 MB). Boot the
recovery FIT from the host using the [raw FIT staging commands](install.md#2-start-the-recovery-from-ram).

The recovery is the full one: screen UI on the panel, the Rust storage daemon
and NCM/SSH. Its storage model keeps Android on slot B and checks the board
(compatible, the bootloader serial number, the AOSP boot control in misc
selecting slot A with B bootable). `recovery prepare-install --android-userdata
SIZE --check` prints the planned split of the userdata span for the chosen
Android size ([offered sizes](../recovery.md#ab-devices-preparing-linux-storage));
nothing else is changed:

| Entry | Use | Size |
| --- | --- | --- |
| 80 `userdata` | Android on B, left unformatted (first 8 MiB zeroed) | chosen size |
| 83 `linux-boot` | FAT ESP | 1 GiB |
| 84 `linux` | ext4 root | the rest |

The GPT grows from 82 to 84 entries within the arrays' existing sectors. After
the split, Android needs a factory reset from its own recovery: LK fastboot →
`fastboot set_active b` → `fastboot reboot recovery` → "Wipe data/factory
reset" (formats the new userdata and resets the metadata encryption) → boot
Android; `adb reboot bootloader` → `fastboot set_active a` returns to NixOS.
Recovery is supplied by the host: rebooting with the `recovery` argument
enters U-Boot USB fastboot, then use the [raw FIT staging commands](install.md#2-start-the-recovery-from-ram).
The volume keys use the SoC keypad; Power uses the PMIC key input.
A working slot-A U-Boot is required. If it is damaged, restore U-Boot through
stock LK fastboot before starting RAM recovery.

Every image written to `boot_a` must fill the 64 MiB partition and carry an
AVB hash footer: unlocked LK still loads `boot_a` through AVB, and without a
parseable footer and vbmeta it asserts before loading the boot image header.
The U-Boot image is built that way.

First installation: [install guide](install.md) (partitioning, recovery and the NixOS system; verified on one T880).

## Reboot paths in U-Boot

| Request | Result | State |
| --- | --- | --- |
| `fastboot reboot`, `reset` (ACM) | PSCI reset; LK boots slot A again and counts the attempt | Verified |
| `fastboot reboot-bootloader`, `rebootmode bootloader`, menu "Stock bootloader fastboot (LK)" | LK fastboot (product `p5n1_kb_t880_8883_b0`) | Verified from fastboot and ACM; menu keys not tested |
| `fastboot reboot recovery` | LK recovery mode loads slot-A U-Boot, which waits in USB fastboot for a host-supplied FIT | RAM recovery |
| LK recovery mode or misc `boot-recovery`; missing ESP or returned systemd-boot | Waits in U-Boot USB fastboot; misc is read only | RAM recovery |
| `fastboot reboot fastboot` | Refused ("Cannot set fastboot flag"); there is no userspace fastbootd on the NixOS side | Not implemented |
| `fastboot stage <FIT>` then `oem 'run:bootm ${fastboot_addr_r}'` | Downloads the raw FIT and boots its selected configuration from RAM | Verified |
| No USB host for `autoreset_s` | Watchdog reset; after the retries LK boots Android on B | Verified |
| Power off | No `poweroff` command; PSCI SYSTEM_OFF exists but is untested (needs a power-key press; with a cable LK may start charging mode) | Not implemented |


## Device values

| Item | Value | State |
| --- | --- | --- |
| Boot image | Header v4, page 4096, LZ4-legacy kernel, no ramdisk; LK loads the kernel to `0x40000000`, the ramdisk to `0x66f00000` (64 MiB cap) and the DTB to `0x47c80000` from vendor_boot | Measured; U-Boot packed to match |
| Slots and boot partition | NixOS on A, Android on B; `boot_a` 64 MiB; no recovery partition | Measured / decided |
| Memory | `0x40000000` + 12 GiB; 57 LK reserved regions | Measured; read at runtime |
| CPUs, PSCI, GIC, timer | GICD `0x0c400000`, GICR `0x0c440000`, PSCI smc, 13 MHz | Measured |
| UART | `0x11001000` mt6577, 921600 | Measured; not used by U-Boot |
| UFS | HCI `0x112b0000` (SPI 168, MCQ 177–184), PHY `0x112a0000`, ti,syscon resets at `0x112bb000` | Verified read (gear 5, 2 lanes, GPT); U-Boot reads only |
| USB device | mtu3 `0x11201000` (ippc `0x11203e00`), xsphy u2 `0x11e40000`, forced VBUS | Verified: High Speed fastboot and ACM; U-Boot releases the PHY state the stock bootloader forces |
| Watchdog | RGU `0x1c00a000`, enabled by the preloader | Measured; U-Boot restarts and feeds it (15 s) |
| Keys | Keypad `0x1c00e000`: Volume Down index 0, Volume Up index 1; Power on MT6363 | Measured; U-Boot reads the keypad only |
| Framebuffer | `0xfd11f000`, VRAM `0x2ee0000`, 1600×2560 ARGB8888, pitch 6400 | Measured (pitch inferred) |
| Compatible | `alldocube,t880`, `mediatek,mt6897` | Chosen here |
| Storage for Linux | FAT `linux-boot` 1 GiB and ext4 `linux`, split from userdata | Android keeps the selected size; Linux gets the rest |
| Stock fastboot | LK product `p5n1_kb_t880_8883_b0`; entered from Android (`adb reboot bootloader`) or U-Boot (`fastboot reboot-bootloader`) through the reboot-mode register | Verified |
| Kernel and recovery DT | Measured values: simplefb, reboot modes, xsphy and mtu3 forced VBUS; ramoops in its own DRAM region (LK restores its pstore area from expdb) | Verified raw FIT boot through U-Boot |


The MT6375 charger requests fixed 5 V at up to 3 A, programs at most 2.1 A input
and battery current, and stops above the 2.2 A board ceiling (input also clips
to the negotiated contract). Programmed CV is 4.40 V; samples above that
regulation target alone are not treated as overvoltage. MT6375 hardware fault
status, including BATOV, stops charging; its numerical BATOV threshold has not
been established. Charging stops below
10 °C or at/above 45 °C, and sensor/electrical faults latch off. Recovery
disables automatic arming. A bounded screen-on desktop test measured about 9.4 W input and 7.0 W
net battery charging; higher voltage/PPS and full-charge behavior are unverified.
The corrected policy passed a bounded charging trial; full-charge/taper remains unverified.

The kernel includes USB Wi-Fi, Bluetooth, card-reader, audio and common serial
adapter modules. USB host operation remains unverified; firmware-dependent
adapters may require matching firmware supplied by the consuming configuration.
