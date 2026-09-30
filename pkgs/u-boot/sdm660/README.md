# Experimental Clover U-Boot

Clover uses the same official v2026.10-rc5 pin as Polaris/Asphalt; see
[the common package](../README.md). This is build-verified firmware, with no
Clover RAM or persistent boot verification yet. Installed defaults use U-Boot/EFI;
independent RAM recovery remains. Example: `examples/clover/system.nix`.

## Patch provenance

The following files are **byte-for-byte original GitHub `.patch` exports**,
including commit ID, author, date, message and trailers. All originate from
Alexey Minnekhanov's `sdm660-mainline/u-boot`, examined at
`c1fc9e3cc8f1adadd707dbe3d95d71b933fd799e`. They apply only to the Clover package.

| File | Original commit | SHA-256 of patch |
| --- | --- | --- |
| `patches/0000-gdsc-flags.patch` | [1c430cce98e3](https://github.com/sdm660-mainline/u-boot/commit/1c430cce98e34c6aa584f318971a93064e24531e) | `ea4af3f3d657b82993aff109b6161543c2ba539bdf7e0d38fbd6ec82e2eedeee` |
| `patches/0000-gdsc-poll.patch` | [fd48c536d29d](https://github.com/sdm660-mainline/u-boot/commit/fd48c536d29d00a30fd85aadb101dac24f74c459) | `9040f949f4abb9e483e0d13b74f1f09a500206d359cc1ba5f827dc7c01e34152` |
| `patches/0001-sdm660-gcc.patch` | [78519f78d857](https://github.com/sdm660-mainline/u-boot/commit/78519f78d857bb7d5c8368e9d2fec0f5f5d2fc4a) | `e45acdd79fd67ebc0a9b2716643e1e05261117997025da3b197424c41d2f93b7` |
| `clover/patches/0001-clover-dts.patch` | [a4faf7b435dc](https://github.com/sdm660-mainline/u-boot/commit/a4faf7b435dcc92bc8741a98c5fb04045c7ba1f4) | `e72888a8a153c9c271e4ffe5c375789df7d3e4846258f50e975abba802c0f9c0` |

Local follow-ups are separate: `0002` relocates the original board DTS into
`dts/upstream`, uses the current CDSP reservation label and removes a
nonexistent fuel-gauge node. `0003` removes unavailable RPM-SMD power-domain
handling from the two MMC controllers and limits firmware MMC to 52/50 MHz
without HS200/HS400 tuning. The original ramoops debug fragment is kept in the
source import but is never selected. The Linux kernel and its full eMMC/microSD
capabilities are unchanged. No nested partition-table support is introduced.

## Boot and storage

The Android v0 envelope contains gzip-compressed ARM64 U-Boot followed by its
DTB, 4096-byte pages and the existing Clover offsets; there is no second payload.
The fixed framebuffer is the original Clover DTS value, `0x9d400000`,
1200×1920, ARGB8888. ABL must have initialized the display and RPM-managed rails.
The upstream drivers cover SDM660 pinctrl, PMIC keys/GPIO, SDHCI and QUSB2.
The imported GDSC polling fix is required for SDM660 USB_30_GDSC.

USB ACM is enabled before eMMC access. The inherited aliases select internal
`mmc 1`; the environment finds its physical GPT `system` partition and loads
`/EFI/BOOT/BOOTAA64.EFI`. MicroSD remains `mmc 2`. `system` becomes FAT `/boot`
at its existing size; `userdata` remains ext4 `/`. Clover has no A/B slots.
Systemd-boot retains 10 generations and relaxes only the retained Android GPT
type check after verifying the mounted FAT partition identity. Firmware capsule
updates are disabled. Normal generations belong on FAT, not in Android `boot`.

## Build and validation

```sh
nix build .#devices.clover.u-boot --builders '' --out-link tmp/systemd-artifacts/devices.clover.u-boot
python tests/clover-uboot.py "$(nix eval --raw .#devices.clover.u-boot.firmware.outPath)" tmp/systemd-artifacts/devices.clover.u-boot
nix eval --impure --json --expr 'import ./tests/clover-uefi.nix { flake = builtins.getFlake (toString ./.); }'
```

The Python inspection needs `fdtget`. The firmware cross-builds on x86_64;
USB enumeration, display, eMMC FAT reads, EFI boot and updates/rollback remain
unverified on hardware.
Checked FAT preparation and initial EFI installation must precede persistent
firmware installation.
Existing EFI systems can be maintained through recovery rebuild/deploy.
