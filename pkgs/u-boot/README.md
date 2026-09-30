# Qualcomm device U-Boot

The baseline is official U-Boot **v2026.10-rc5**, commit
[`a06e89ab05eaa2b8344d521319399333cd760ae5`](https://git.u-boot-project.org/u-boot/u-boot/-/commit/a06e89ab05eaa2b8344d521319399333cd760ae5).
`default.nix` pins its archive and hash; `devices.nix` selects the board package.
For configuration and installation, see the [installation guide](../../docs/u-boot-install.md).

| Device | Package reference |
| --- | --- |
| Polaris / SDM845 | [Display and keys](../../docs/polaris/boot-menu-reference.md) |
| Asphalt / SM8475 | [Firmware and patch sources](sm8475/README.md) |
| Clover / SDM660 | [Firmware and patch sources](sdm660/README.md) |
| Sheng / SM8550 | [Firmware and patch sources](sm8550/README.md) |

## Polaris

Polaris uses upstream `qcom_defconfig` and `board/qualcomm/qcom-phone.config`,
with local patches for the ABL framebuffer reservation and bitmap font scaling.
Patch headers record their sources. Its environment derives from the upstream
GPL-2.0+ `qcom-phone.env` and loads `/EFI/BOOT/BOOTAA64.EFI` from the physical
GPT `system` partition on UFS. Linux mounts that FAT partition at `/boot` and
uses ext4 `userdata` for `/`, including `/nix/store`.

The installer verifies the mounted FAT device before relaxing the retained
Android GPT type check. EFI variables are not persisted on that type. Inspect
boot status with:

```sh
SYSTEMD_RELAX_ESP_CHECKS=1 bootctl --esp-path=/boot status
```

The upstream GPL-2.0+ 8×16 font is scaled to 24×48 glyphs with
`VIDEO_FONT_SCALE=3`; other boards default to 1. `vidconsole` comes first in
stdout/stderr so EFI uses the panel's 45×45 character grid. Serial and USB ACM
remain available. See the [menu guide](../../docs/polaris/boot-menu.md) for usage
and hardware limits.

## Shared USB console and input

ACM patches allow startup without an attached USB host and later console
connections. They bound stalled transmissions and cancel requests on disconnect.
Button patches correct press/release events; SPMI and PMIC GPIO patches preserve
board bias and power-source settings. Board wiring stays in each device package.

Run these source-level checks against a patched U-Boot tree:

```sh
python3 tests/uboot-acm-lifecycle.py /path/to/patched/u-boot
python3 tests/uboot-font-scale.py /path/to/patched/u-boot
python3 tests/uboot-button-events.py /path/to/patched/u-boot
```

The font test uses AddressSanitizer/UndefinedBehaviorSanitizer and checks all
256 glyphs at scales 1–4, padding, rotation, allocation failure and reselection.
Target-device input, display and cold-boot checks are still required.
