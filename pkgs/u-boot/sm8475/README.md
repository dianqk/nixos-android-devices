# SM8475 / Lenovo TB320FC U-Boot

`devices.asphalt.u-boot` uses the shared U-Boot v2026.10-rc5 builder. Its Android
v2 envelope contains an uncompressed ARM64 payload and separate DTB, within the
96 MiB `boot_b` limit. The payload is padded to at least 41,289,792 bytes for
reliable ABL handoff; the minimum safe extent is not established. Firmware
finds outer-GPT `linux-boot` across UFS LUNs and loads
`/EFI/BOOT/BOOTAA64.EFI`. The ESP is 1 GiB and systemd-boot keeps 10 generations.
Firmware operations target B only; A and `super` remain untouched. EFI capsule
updates are disabled.

When ABL supplies the exact `androidboot.mode=charger` boot argument, firmware
loads the dedicated charger image `/EFI/android-devices/charger.efi` from the
ESP; see [off-mode charging](../../../docs/asphalt/charging.md). Other startup
modes, including ordinary startup with a USB cable connected, boot EFI
automatically. The argument is read from U-Boot's control device tree before
EFI replaces the operating system's boot arguments. Both paths keep the B-slot
success confirmation.

The firmware requires an installed kernel with the ABL splash reservation and
Lucid OLE PLL preservation patch. That pair keeps the inherited display clocks
running through the Linux handoff. The internal display and touch have been
validated with this pair; deliberate menu-button selection remains unverified.
Keep independent RAM recovery available.

## Source patches

The first two imports match their published patches byte-for-byte. Local fixes
are separate commits.

| Patch | Source and adaptation |
| --- | --- |
| `0001-sm8450-gcc.patch` | [Jens Reidel, 157e7b423ec2](https://github.com/sm8450-mainline/u-boot/commit/157e7b423ec25991f41a76f64a3cb624d7dd44a5), original patch unchanged. SHA256 `4ecefd20a38183936f521dda167e43bd26a298a6ae65e9e989c347b4b3775321`. |
| `0002-sm8450-pinctrl.patch` | [Jens Reidel, 2bfaa78dd760](https://github.com/sm8450-mainline/u-boot/commit/2bfaa78dd760915a18cb867de766d76032d994bc), original patch unchanged. SHA256 `ef9cb2dc5f9695eb1c099d0362d0d2aae87fa76941d04d7349fed8661847bd0d`. |
| `0003-sm8475-ufs-phy.patch` | [Danila Tikhonov, Linux ef2bd6c96983](https://github.com/torvalds/linux/commit/ef2bd6c969830c7e42c23bcaf9d533db77420512). Author/date/message/trailers preserved verbatim. U-Boot type, match table and clock/regulator list adaptations are explained below the patch's commit-message separator. Register values unchanged. |
| `0004-sm8475-boot-dependencies.patch` | Local follow-up: SM8475 compatibles, QUP5, current pinmux callback type, literal snprintf format, PMIC GPIO and firmware-mediated SMMU matches. USB/UniPro offsets and rates follow [Linux v7.3-rc4 GCC](https://github.com/torvalds/linux/blob/v7.3-rc4/drivers/clk/qcom/gcc-sm8450.c). |
| `0005-asphalt-eusb2-repeater.patch` | Local U-Boot adaptation of the [Lenovo Linux NXP repeater](https://github.com/lenovo-basements/linux/blob/d792042c0c9561c0f32a8f6eb9f0aca325fc0350/drivers/phy/qualcomm/phy-qcom-i2c-eusb2-repeater.c), using the board's tested register overrides. |
| `0006-sm8475-ufs-overlay.patch` | Local U-Boot follow-up, separate from the SM8475 import. Shared SM8550 Gear 4 TX/RX tables copied unchanged from [Linux v7.3-rc4](https://github.com/torvalds/linux/blob/v7.3-rc4/drivers/phy/qualcomm/phy-qcom-qmp-ufs.c); only SM8475 enables the new lane/PCS overlay execution. |
| `0007-sm8450-unipro-divider.patch` | Local correction to `0004`: use the frequency table's already encoded HID divider and replace the previous divider bits. Hardware CFG readback changes from `0x107` (150 MHz) to `0x103` (300 MHz).  |
| `0008-sm8475-ufs-hs-series.patch` | Local ordering fix: apply HS-B after the SM8475 Gear 4 overlay, matching Linux. The old order overwrote `VCO_TUNE_MAP=0x44` with `0x04`; readback now gives `0x44`, all eight LUNs enumerate, and GPT and ext4 reads pass. |
| `../patches/0001-acm-stop-cancelled-rx.patch` | Local correction against the pinned [ACM implementation](https://source.denx.de/u-boot/u-boot/-/blob/a06e89ab05eaa2b8344d521319399333cd760ae5/drivers/usb/gadget/f_acm.c): do not requeue failed RX requests during endpoint teardown. Fixes the observed hang when switching from ACM to Fastboot on Asphalt. |
| `asphalt/patches/0001-asphalt-boot-dts.patch` | Boot-only board description derived from the repository's Linux `0006-asphalt-board-dts.patch` and [initial board source](https://github.com/lenovo-basements/linux/commit/d792042c0c9561c0f32a8f6eb9f0aca325fc0350). Uses the board's own framebuffer, UFS and USB wiring. |
| `asphalt/patches/0002-volume-up-pinctrl.patch` | Local follow-up: port GPIO6 input, pull-up and power-source=1 from the working Linux DTS. Requires the shared button/SPMI/PMIC GPIO fixes described in [the common README](../README.md#shared-usb-console-and-input). |

The original patches apply with context offsets/fuzz against the fixed baseline;
compilation and resulting files must be checked when updating that baseline.

## Build and device status

```sh
nix build .#devices.asphalt.u-boot --out-link result-u-boot
python3 tests/asphalt-uboot.py FIRMWARE_DIRECTORY result-u-boot
```

The package cross-builds on x86_64 for AArch64. Hardware has booted through UFS,
FAT and systemd-boot to an installed system with USB and Wi-Fi SSH. The UFS PHY
uses the SM8550 Gear 4 tables and HS-B ordering; all eight LUNs enumerate.
Unattended EFI startup with an unconfigured USB host has been verified. Physical
cable-absent cold boot and intentional button selection remain open checks.
The current U-Boot Fastboot flash backend is MMC, so its flash/BCB commands must
not be used on internal UFS. Prepare storage and install EFI files before
installing firmware in `boot_b`; see the [installation guide](../../../docs/asphalt/first-install.md).
