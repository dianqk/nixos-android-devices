# SM8650: Xiaomi 14 Ultra RAM firmware

Aurora uses the shared official U-Boot v2026.10-rc5 baseline,
`a06e89ab05eaa2b8344d521319399333cd760ae5`. This is experimental firmware. The installed EFI path has been hardware-validated. No ESP or userdata repartitioning is needed
for the USB console and read-only storage diagnostics.

```sh
nix build .#devices.aurora.u-boot --out-link result-u-boot
python tests/aurora-uboot.py \
  "$(nix eval --raw .#devices.aurora.u-boot.firmware.outPath)" \
  result-u-boot
```

Follow the [Aurora B-slot/AVB prerequisites](../../../docs/aurora/README.md)
before using `fastboot -s SERIAL boot IMAGE`. Validate a new build with RAM boot before replacing `boot_b`. Preserve the independently bootable recovery and Android A.

USB ACM and button-kbd are enabled before an immediate Linux ESP scan
(`bootdelay=0`). Hold Volume Down as U-Boot takes over to enter the maintenance
menu. Volume Up/Down navigate; a short power press selects. It offers NixOS,
USB serial, shell, reset and wired charging. The menu and selected shell do not
have an inactivity timeout. Normal systemd-boot retains its separate timeout.
There is no persistent environment, capsule update or fastboot flash backend.
If normal EFI loading returns, the firmware pauses and offers the maintenance menu.

Exact ABL `androidboot.mode=charger` selects `/EFI/android-devices/charger.efi`;
USB connection alone does not. Missing charger payload powers off, never falls
through to normal Linux. The charger EFI also qualifies for the shared slot-B
confirmation hook. The Aurora module installs the shared reboot/poweroff,
bootloader, recovery-B and Android-A actions; see [boot actions](../../../docs/boot-actions.md).
New physical-key actions and charging behavior require board-level acceptance.

A normal reset follows the stock bootloader's current slot and BCB state; a
pending `boot-recovery` request returns to recovery. Arrange that return path
before experimenting. The timeout cannot recover an arbitrary hardware hang.

Verified hardware behavior: ABL RAM load, correct device identity, USB2 ACM,
ABL memory-bank and hypervisor timer-overlay preservation, software reset to
recovery, six UFS LUNs at HS-G5/two lanes, GPT enumeration and a 16 MiB
recovery-partition read with matching CRC32, and installed systemd-boot-to-Linux
handoff. The simplefb registers as `vidconsole`; U-Boot text and systemd-boot
menus are physically visible with the matching factory `imagefv_b` present.
If fastboot and U-Boot stay black after a Linux-to-bootloader reboot, check
`imagefv_b` first; see the [factory display firmware prerequisite](../../../docs/aurora/README.md#keep-b-slot-boot-display-firmware-intact).
The panic path has not been deliberately fault-injected on hardware.

## Board and driver choices

- Boot DT identity, 42 fixed reserved-memory ranges and protected GPIO ranges
  match the working Aurora recovery. Keep `arch_timer` symbols for ABL's
  hypervisor overlay. Keep `splash_region` at `0xfc400000`; a reservation
  alone is not proof of a usable linear framebuffer. The display description now
  uses measured Android 14 ABL scanout: 1440×3200 ARGB8888, stride 5760 at
  `0xfc400000`. VIG0/VIG1 read two 720-pixel halves of that shared buffer.
  `vidconsole` precedes serial/USB ACM; `NO_FB_CLEAR` preserves initial contents.
  Physical refresh and EFI-to-Linux takeover must be checked on the target.
- Reuse the unchanged SM8550 PM8550B repeater/lifecycle patches. Original Linux
  author, date, message and trailers remain in those patches; see the
  [SM8550 source notes](../sm8550/README.md). ABL's regulator votes are retained.
- USB2 uses the U-Boot-specific `qcom,select-utmi-as-pipe-clk` override. The
  working Aurora Linux DT does not require that override.
- The baseline already supplies the SM8650 USB configuration NoC gate. Add
  its master-clock dependency, not a duplicate gate. UniPro uses SM8650's
  100/201.5/403 MHz table and GPLL4 mux 5, not SM8550's 300 MHz table.
  Replace encoded HID bits instead of passing them through a second encoding.
  PLL initialization remains owned by ABL. The register/table source is
  [Linux v7.3-rc5 gcc-sm8650.c](https://github.com/torvalds/linux/blob/v7.3-rc5/drivers/clk/qcom/gcc-sm8650.c).
- The UFS driver must read `operating-points-v2`, not `required-opps`, to find
  the clock table. The latter otherwise silently falls back to 150 MHz.
- With overlays enabled, the Snapdragon fallback FDT copy must target
  `fdt_addr_r`, not the most recent overlay allocation.
- Keep the baseline hypervisor-aware SMMU driver: identity translation is
  distinct from bypass, which firmware can convert to a fault. Do not reset
  firmware-owned mappings on handoff. Linux display takeover also needs the
  existing enabled Lucid OLE PLL guard (the Aurora kernel already carries it).

The shared ACM patch zero-initializes the complete stdio descriptor. Without
it, the optional `flush` callback contains stack garbage and panic can fault
again before reaching reset. `tests/uboot-acm-stdio.py` exercises the actual
initializer against poisoned stack storage with and without flush support.

The Android v0 envelope uses gzip plus appended DTB, 4096-byte pages and stock
14.0.0 / 2026-02-01 compatibility metadata. `TEXT_BASE=0x80000000` prevents
Snapdragon's ARM64 `text_offset` subtraction from wrapping. The Linux-specific
ABL alignment wrapper is not used for U-Boot; EFI experiments must use the
original Linux PE-capable `Image`, not that wrapped direct-boot payload.


The experimental installed path looks up `linux-boot` by GPT name after the
zero-delay console setup, loads `/EFI/BOOT/BOOTAA64.EFI`, and supplies the
relocated ABL DT at `fdt_addr_r` to EFI. An absent/returning loader falls back to
reset. No GPT/filesystem writes or slot changes are performed by this scan.
RAM and installed EFI/Linux handoff have passed; validate rebuilt firmware in RAM
before replacing an installed image.
