# Sheng U-Boot

Sheng uses official U-Boot v2026.10-rc5, pinned at
`a06e89ab05eaa2b8344d521319399333cd760ae5`. Its SM8550 support needs
the sourced PM8550B repeater and UFS UniPro clock patches described below.

## Sources and patch preservation

| Patch | Source and local adaptation |
| --- | --- |
| `patches/0001-pm8550b-repeater.patch` | Linux [56d77c9a10d9](https://github.com/torvalds/linux/commit/56d77c9a10d97d15b8da900f861bc28b06b84b1c), Abel Vesa, 2023-02-08. Original commit ID, author/date, complete message and sign-off/link trailers are retained. The diff is a **U-Boot API port**, described below `---`: DM PMIC/PHY instead of Linux regmap/platform/regulators; only PM8550B USB device mode, no unused PMIC variants or tuning override API. |
| `patches/0002-snps-repeater-lifecycle.patch` | Local follow-up connecting the repeater to the baseline SNPS eUSB2 driver. Propagates errors, unwinds clocks/resets, and disables the repeater on partial initialization failure. Shared ABL supply votes remain intact. |
| `patches/0003-sm8550-unipro-clock.patch` | Local adaptation of the frequency table and `0x77098` RCGR from [Linux gcc-sm8550.c at ad75da348a02](https://github.com/ianchb/sm8550-mainline/blob/ad75da348a020f0b7cb541ca2f06ab38cf77004d/drivers/clk/qcom/gcc-sm8550.c). Programs 75/150/300 MHz using the existing GPLL0 parents. |
| `sheng/patches/0001-sheng-boot-dts.patch` | Linux [4edcd3031b04](https://github.com/ianchb/sm8550-mainline/commit/4edcd3031b04f4c7e398c8b8409c0d4a45d5ce79), map220v, 2024-08-24. Original commit ID, author/date and message are retained (original has no sign-off trailers). Diff is a boot-only U-Boot port: board identity, keys, UFS reset GPIO210 and PM8550B USB wiring, upstream DT path, USB2 peripheral mode. Current memory corrections come from the pinned Linux board below. |

The U-Boot ports also draw on the [Sheng Linux board at
`ad75da348a02`](https://github.com/ianchb/sm8550-mainline/tree/ad75da348a020f0b7cb541ca2f06ab38cf77004d).
Their patch headers describe changes to the Linux diffs; local lifecycle and
clock changes are separate patches.

## Boot and storage contract

- Sheng Android v0 envelope: gzip ARM64 payload with appended DTB,
  4096-byte pages, kernel offset `0x8000`, ramdisk `0x01000000`, tags `0x01e00000`,
  maximum 192 MiB. The envelope has passed ABL RAM boot with the firmware.
- `TEXT_BASE=0x80000000` keeps the ARM64 header's `text_offset` at zero.
  The generic PIE default of zero wraps that field because Snapdragon subtracts
  its `0x80000000` base. The ARM64 payload executes through ABL.
- USB ACM starts before UFS scanning. The firmware searches UFS LUNs 0–7 by GPT
  label `linux-boot`, then loads `EFI/BOOT/BOOTAA64.EFI`. No Android LP parser or
  nested partition table is used.
- `examples/sheng/system.nix` uses a separate **1 GiB FAT32 standard GPT ESP**
  `/boot`, ext4 `linux` root and **10 generations**. The installer verifies the
  mounted device, ESP type, size and room for a new payload. It does not relax
  ESP type checks. `/nix/store` belongs on ext4.
- The firmware belongs only in **boot_b**. Preserve A and super. There are no
  automatic slot writes, EFI capsules or firmware fastboot flashing; these are
  disabled. Normal generations update FAT files rather than Android boot.
- The example uses U-Boot/EFI. Independent RAM recovery retains its
  Android-format Linux image. Partition preparation and initial EFI installation
  are required before installing U-Boot in boot_b. Installed EFI systems support recovery rebuild/deploy.

## Console and power limitations

Sheng routes U-Boot/EFI output to **vidconsole and USB ACM**.
Local patch `0003-sheng-abl-framebuffer.patch` describes the board's
`0xb8000000` / `0x2b00000` splash allocation as a 3048×2032 ARGB8888
framebuffer while retaining Sheng's original `splash_region@b8000000` node.
RAM boot has verified the visible menu and volume/power-key selection.
`NO_FB_CLEAR=y` avoids clearing the framebuffer during initial video setup.
Linux display startup can leave the panel black; see the
[known limitations](../../../docs/sheng/hardware.md#known-limitations).

ABL must supply the UFS/PHY rails and repeater vdd18/vdd3 (PM8550 L15B/L5B).
The repeater is a SPMI PM8550B device, not Asphalt's NXP I²C device. Its three
default tuning writes, enable and device-mode sequence are taken from Linux.
The port preserves ABL regulator votes and propagates bus and timeout errors.
Only firmware USB2 gadget operation is implemented here; the full Linux USB-C,
DP, host and peripheral paths are unchanged.
The boot DT sets `qcom,select-utmi-as-pipe-clk`: the pinned U-Boot DWC3 glue
requires it to select UTMI in place of the absent SuperSpeed PIPE clock.
This local correction is in `sheng/patches/0002-usb2-pipe-clock.patch`.

## Build and device status

```sh
nix build .#devices.sheng.u-boot --out-link result-u-boot
python tests/sheng-uboot.py "$(nix eval --raw .#devices.sheng.u-boot.firmware.outPath)" result-u-boot
nix eval --impure --json --expr 'import ./tests/sheng-uefi.nix { flake = builtins.getFlake (toString ./.); }'
python tests/sheng-repeater.py /path/to/patched/u-boot
```

The firmware cross-builds on x86_64 for AArch64. Installed slot-B U-Boot/EFI
boot and USB NCM/SSH have been verified with serial-only firmware. The display
firmware has been tested through RAM boot; persistent installation and startup
without a USB host remain unverified. Keep independent RAM recovery.
