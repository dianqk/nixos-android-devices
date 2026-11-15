# Marble display panels

[中文](display.zh.md) · [Device guide](README.md) · [Kernel patches](../../pkgs/linux-kernel/sm7475/marble/PATCHES.md)

Marble phones are fitted with one of two M16T AMOLED panels (1080×2400,
DSC video mode). They use different controllers, so Linux has a driver for
each, and U-Boot selects the right one for every boot.

## Supported panels

| | 36 02 0a | 36 0d 0b |
| --- | --- | --- |
| ABL name (`msm_drm.dsi_display0`) | `qcom,mdss_dsi_m16t_36_02_0a_dsc_vid` | `qcom,mdss_dsi_m16t_36_0d_0b_dsc_vid` |
| Stock `mi,panel-id` | `0x4d313654 0x360200` | `0x4d313654 0x360201` |
| Linux compatible | `xiaomi,marble-m16t-36-02-0a` | `xiaomi,marble-m16t-36-0d-0b` |
| Linux driver | `panel-xiaomi-m16t-36-02-0a` (patch 0016, from iLtanaka's port) | `panel-xiaomi-m16t-36-0d-0b` (patch 0047) |
| vddd (PM8350B L1) | 1.2 V | 1.256 V (stock 1.25 V is not a regulator step) |
| Kernel DTB | default | selected by U-Boot |
| Status | not tested on hardware by this project | works on hardware (see the handover below) |

Both drivers are built into the same kernel image.

### 36 0d 0b

The driver was generated with
[linux-mdss-dsi-panel-driver-generator](https://github.com/msm8916-mainline/linux-mdss-dsi-panel-driver-generator)
from the stock device tree and adapted:

- Supplies in the stock order and delays: vddio 1.8 V, vci 3.0 V, vddd.
- Display clock handover (Asphalt patch 0020): ABL leaves a display
  PLL running under the MDP clock. Reconfiguring that PLL at probe stops the
  clock (`disp_cc_mdss_mdp_clk_src: rcg didn't update its configuration` at
  boot). The display clock controller keeps a PLL that is already running.
  A kernel for this panel needs it, but it is not enough on its own.
- Panel power handover (0047): ABL leaves the panel powered. Without a
  power-down the panel stays black at boot, with every DCS read failing,
  even though the DSI link and backlight report success; a display off/on
  cycle brings it up. The driver powers the panel down at probe (reset held,
  supplies off in the stock order, 500 ms) before attaching to the DSI host,
  so the link is first brought up with a freshly powered panel. With both fixes,
  the panel lit from boot on two hardware trials without diagnostic tracing.
- Reset: a full high-low-high pulse (high 11 ms, low 1 ms, high 11 ms), as on
  the 36 02 0a panel. After the stock 36 0d 0b sequence (low 1 ms, then high
  20 ms) the panel does not answer DSI commands.
- DSC: the stock on sequence programs the decoder with the manufacturer
  command `0x70`, whose PPS says DSC 1.1, 10 bpc, 8 bpp and 540×12 slices
  (the stock device tree's slice height of 20 is not what the decoder is
  told). The driver encodes with exactly these parameters, also sends them
  as a standard PPS, and puts both slices in one packet.
- Backlight: DCS brightness, 12 bits, high byte first. Levels written while
  the panel is off are kept and sent at the next power-on (0047).

## Panel selection

ABL names the fitted panel in the command line it passes on, for example
`msm_drm.dsi_display0=qcom,mdss_dsi_m16t_36_0d_0b_dsc_vid:`. The kernel DTB
describes 36 02 0a. When U-Boot starts it copies the name from ABL's
`/chosen/bootargs` into the environment variable `abl_panel`. Whenever it
hands a device tree to Linux it sets the panel node's compatible and the
vddd regulator voltage of the named variant:

- RAM recovery: `bootm` of the recovery FIT.
- Installed system: `bootefi` and the EFI device-tree fixup protocol, which
  systemd-boot calls for the DTB of a boot entry.

The U-Boot console then shows, for example:

```text
Panel: qcom,mdss_dsi_m16t_36_0d_0b_dsc_vid -> xiaomi,marble-m16t-36-0d-0b
Panel: vddd-supply at 1256000 uV
```

If ABL reports no panel, or a name that is not in the table, U-Boot prints a
warning (`Panel: unknown panel <name>; device tree unchanged`) and boots with
the unchanged DTB, so Linux probes the 36 02 0a driver. On another panel the
screen then most likely stays dark; USB access to the RAM recovery and the
installed system is not affected. The selection needs a U-Boot that contains
it: the RAM recovery carries its own copy, and for the installed system
`boot_b` must hold `devices.marble.u-boot`.

## Which panel does a phone have?

- Android (root): `tr ' ' '\n' < /proc/cmdline | grep dsi_display0`
- U-Boot ACM console: the `Panel:` lines above, or `printenv abl_panel`
- Linux:

  ```sh
  cat /sys/firmware/devicetree/base/soc@0/display-subsystem@ae00000/dsi@ae94000/panel@0/compatible; echo
  ls /sys/bus/mipi-dsi/drivers/
  ```
