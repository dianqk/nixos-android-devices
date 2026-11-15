# Marble kernel patches

[中文](PATCHES.zh.md) · [Marble guide](../../../../docs/marble/README.md)

The `marble` queue targets Linux 7.3.1. It follows the shared Qualcomm patches
of [`../../default.nix`](../../default.nix) and is defined in
[`series.nix`](series.nix). The kernel configuration starts from the SM8475
baseline of [Asphalt](../../sm8475/asphalt/kernel.config) with the SoC layer in
[`../config.nix`](../config.nix) and the board overrides in
[`default.nix`](default.nix). A RAM recovery with this kernel boots on
hardware (console, UFS, USB, touch, keys and the display of a 36 0d 0b
phone).

## Source

The board support draws on [iLtanaka/linux-marble](https://github.com/iLtanaka/linux-marble)
`main` (`v7.2.8..ed120558cd2c`). Individual community patches in
[`patches/linux-marble`](patches/linux-marble) retain their original author,
date, message and trailers. Combined patches record their sources and porting
adjustments in their commit messages.

| Patches | Area |
| --- | --- |
| 0001–0010 | SM8475 pinctrl, cpufreq, `sm8475.dtsi`, SM8450 DT fixes, pd-mapper (Danila Tikhonov, Jens Reidel) |
| 0011 | UBWC configuration for SM8475 (resolved: 7.3's shared `ubwc_4_0_hbb16` descriptor) |
| 0012–0015 | PCIe IOMMU cells, OSM L3 binding, CPU capacities, USB/UFS PHY GDSCs |
| 0016–0018 | M16T DSC video panel, DSI 10 bpc clocking, DPU video-mode DSC (0017 resolved: see below) |
| 0019 | SM8475 battery manager |
| 0020, 0036 | AW88261/AW88263S speaker amplifier (0020, 0036 resolved: 7.3 `guard(mutex)` conversion) |
| 0021–0026 | SMMU secure context banks, Iris VPU2 (0022 resolved: Milos firmware data kept), IPA v5.1, PM8350B haptics, PM8008, SM8450 DT nodes |
| 0027, 0039 | Marble device tree (`qcom/sm8475-xiaomi-marble.dtb`) |
| 0028–0033, 0037, 0038, 0043–0045 | AudioReach/q6apm voice and APR changes (0038 resolved: include context only) |
| [0046](patches/local/0046-media-qcom-iris-adapt-the-SM8450-SM8475-VPU2-support.patch) | Local: Iris VPU2 build fixes for 7.3 |
| [0047](patches/local/0047-marble-m16t-36-0d-0b-panel.patch) | M16T "36 0d 0b" panel driver with cached backlight updates and bootloader power handoff |
| [Asphalt 0020](../../sm8475/asphalt/patches/upstream/0020-lucid-ole-preserve-enabled-pll.patch) | Upstream submission: keep a display PLL that the bootloader left running |
| [`iris-hfi-gen2-{decode-order,capture-pool}.patch`](../../patches/iris-hfi-gen2-decode-order.patch) | Shared Iris VA-API prerequisites (HFI gen2 decode-order controls, larger decoder capture pools), as on Asphalt; see [Asphalt's notes](../../sm8475/asphalt/PATCHES.md#iris-va-api-prerequisites) |
| [0051](patches/local/0051-media-qcom-iris-apply-msm_vidc-rate-control-conditio.patch) | Local: the VPU2 encoder sends Android's VBR-only properties (content-adaptive coding, bitrate boost, minimum quality, adaptive blur) only with VBR, time-delta rate control only with CBR/VBR, and the base-layer priority ID only for H.264, as msm_vidc does; with them in CBR, HEVC P frames came back empty (not yet verified on hardware) |
| [0052](patches/local/0052-audioreach-legacy-tdm-topology.patch) | Legacy AudioReach TDM modules and tertiary TDM bit clocks, with framing and lane setup from Audio IF topology tokens |
| [0054](patches/local/0054-marble-speaker-tdm-card.patch) | `xiaomi,marble-sndcard` binding, driver and wiring. The 96 kHz S32_LE TDM backend holds the LPASS core vote and selects the speaker at probe |
| [0064](patches/local/0064-marble-tdm-clock-and-dcodec-vote.patch) | Hold the TDM bit clock and LPASS DCODEC vote for the speaker backend lifetime |
| [0075](patches/local/0075-marble-three-channel-tdm.patch) | Map FL/FR/FC to TDM slots 0–2 so the top amplifier receives its ultrasound input |
| [`ssc-fastrpc-pdr.patch`](../../patches/ssc-fastrpc-pdr.patch), [0078](patches/local/0078-arm64-dts-qcom-sm8475-xiaomi-marble-subscribe-to-the.patch) | Shared FastRPC protection-domain subscription, as on Asphalt; the Marble DT subscribes the SLPI FastRPC node to `tms/servreg` / `msm/slpi/sensor_pd` (see [SLPI sensors](#slpi-sensors)) |
| [0079](patches/local/0079-arm64-dts-qcom-sm8475-xiaomi-marble-enable-the-PMK83.patch) | Local: enable the PMK8350 RTC with its alarm, as stock does (time setting stays off), for RTC wake from suspend |
| [`gmu-sync-state/0001–0005`](../../patches/gmu-sync-state/README.md) | Shared GMU driver-core series (Akhil P Oommen, RFT v1), as on Asphalt: binds a driver to the GMU so the GCC and GPUCC `sync_state()` complete |
| [0080](patches/local/0080-arm64-dts-qcom-sm8475-xiaomi-marble-disable-unsuppor.patch) | Local: disable the QCE node (driver BROKEN in 7.3), as on Asphalt, so the interconnect providers' `sync_state()` completes and their boot bandwidth floors drop |
| [0081](patches/local/0081-scsi-ufs-qcom-Power-down-the-controller-device-durin.patch) | Local, the same change as Asphalt's 0027 (cherry-picked): SM8450 UFS `no_phy_retention` (default `spm_lvl` 5); the UFS PHY loses its state across a CX collapse |
| [0082](patches/upstream/0082-dt-bindings-clock-qcom-gcc-sm8450-Add-CX-power-domai.patch)-[0084](patches/upstream/0084-arm64-dts-qcom-sm8450-Add-GCC-CX-power-domain.patch) | Upstream (linux-next, Abel Vesa), cherry-picked from Asphalt's 0028-0030: the SM8450 GCC and its GDSCs are parented to RPMh CX, so GDSC consumers' performance votes reach CX (see [UFS clocks and PHY](#ufs-clocks-and-phy)) |
| [0085](patches/local/0085-phy-qcom-qmp-ufs-program-the-full-SM8475-init-sequen.patch)-[0089](patches/local/0089-arm64-dts-qcom-sm8475-describe-UFS-operating-points-.patch) | Local, cherry-picked from Asphalt's 0032, 0005, 0033, 0034 and 0035: full SM8475 UFS PHY tables for every gear, 850 MHz UFS clocks from GPLL3, the `qcom,sm8475-ufshc` compatible, its turbo mode above 300 MHz and the UFS OPP table (75 MHz/LOW_SVS, 850 MHz/TURBO_L1); 0089 resolved: Marble's own `sm8475.dtsi` `freq-table-hz` |
| [0091](patches/local/0091-sm8450-ufs-phy-gdsc-retention.patch) | Retain the UFS PHY GDSC across CX collapse with `CFG_GDSCR` polling and flip-flop retention |
| [`sm-x800-linux/0012`, `0013`, `0017`](../../sm8475/asphalt/PATCHES.md#camera-sources) | Asphalt's SM8450 CAMSS support and camera clock fixes (Aaron Bockelie, sm-x800-linux), referenced from the Asphalt queue; see [Cameras](#cameras) |
| [0095](patches/local/0095-media-qcom-camss-keep-the-SM8450-CSIPHY-lane-mask.patch) | Local: keep the computed CSIPHY lane mask on SM8450 (the driver part of Asphalt's 0016), for the one-lane macro camera |
| [`camss-stream-unwind.patch`](../../patches/camss-stream-unwind.patch), [`camss-cphy/0001–0009`](../../patches/camss-cphy/README.md), [`camss-csiphy-cphy-clock.patch`](../../patches/camss-csiphy-cphy-clock.patch) | Shared CAMSS start/stop unwind, the CAMSS C-PHY series (David Heidelberg, v9) and the C-PHY CSIPHY clock rate, as on Aurora |
| [0096](patches/local/0096-media-qcom-camss-drop-SM8450-from-the-CSIPHY-init-la.patch), [0097](patches/local/0097-media-qcom-camss-select-the-SM8450-CSIPHY-lane-table.patch) | Local: move SM8450 out of `csiphy_init()` so the C-PHY series applies unchanged (0096), then select the SM8450 D-PHY lane table per PHY type (0097) |
| [0098](patches/local/0098-media-qcom-camss-select-C-PHY-on-CSID-680.patch) | Local: set the C-PHY type bit on CSID 680 (SM8450, SM8475, SM7475) |
| [0099](patches/local/0099-media-qcom-camss-csiphy-3ph-add-SM8450-C-PHY-lane-se.patch) | Local: SM8450-class C-PHY lane settings (Qualcomm CSIPHY v2.1.3, 1.7 and 2.5 Gsps per trio) |
| [0100](patches/local/0100-media-i2c-add-a-GalaxyCore-GC02M1-driver.patch)–[0102](patches/local/0102-media-i2c-add-an-OmniVision-OV64B40-driver.patch) | Local: GalaxyCore GC02M1 (macro), Samsung S5K3P9 (front) and OmniVision OV64B40 (wide) drivers, each with one fixed mode |
| [0103](patches/local/0103-arm64-dts-qcom-sm8475-xiaomi-marble-wire-the-cameras.patch) | Local: the four cameras in the board DT |
| [0104](patches/local/0104-power-supply-qcom_battmgr-report-the-SM8475-USB-port.patch) | Local: report the USB port type (SDP, CDP, DCP) from the SM8475 battery manager's `USB_ADAP_TYPE` |

0017 keeps the 24-bit-per-pixel-clock video timing for 10 bpc and the
panel-provided DSC RC parameters. Its slice-per-packet part is upstream in 7.3
([`ce73a5db44e3`](https://git.kernel.org/torvalds/c/ce73a5db44e3)); the M16T panel
uses that interface (`MIPI_DSI_MODE_DSC_ALL_SLICES_IN_PKT`) instead of the
fork's `dsc_slice_per_pkt` field.

### Cameras

| Camera | Sensor | Bus | Link | Mode | Bayer |
| --- | --- | --- | --- | --- | --- |
| Wide | OmniVision OV64B40 (`ovti,ov64b40`) | CCI0 bus 1, 0x10 | CSIPHY2, C-PHY 3 trios, 1.684 Gsps | 4624x3472 RAW10, 30 fps | BGGR |
| Ultra-wide | Sony IMX355 (mainline `imx355`) | CCI0 bus 0, 0x1a | CSIPHY0, D-PHY 4 lanes, 720 Mbps | 3280x2464 RAW10, 30 fps | RGGB |
| Front | Samsung S5K3P9 (`samsung,s5k3p9`) | CCI0 bus 0, 0x10 | CSIPHY3, D-PHY 4 lanes, 544 Mbps | 2304x1728 RAW10, 30 fps | GBRG |
| Macro | GalaxyCore GC02M1 (`galaxycore,gc02m1`) | CCI1 bus 0, 0x37 | CSIPHY1, D-PHY 1 lane, 672 Mbps | 1600x1200 RAW10, 30 fps | BGGR (expected) |

The Bayer orders of the wide, ultra-wide and front cameras were read from the
sensors' colour-bar test patterns; the GC02M1 test images are monochrome, so
its order follows from the mirrored and flipped readout. The sensor tables are
the vendor sequences of the production modules; the wide camera's per-module
calibration blocks are not written. The C-PHY lane settings are the generic
Qualcomm CSIPHY v2.1.3 values; the board's own CSIPHY2/CSIPHY3 tuning in the
vendor kernel was not needed. The sensor drivers keep a sensor off for at
least 1.2 s after power-down, since the CCI controller hangs when it stays
clocked across a sensor power cycle.

### UFS clocks and PHY

Marble runs the UFS core and UniPro clocks at 850 MHz for HS-G4, like the
SM8475 Lenovo TB320FC. 0082–0089 bring over the same series as
[Asphalt's UFS clocks and PHY](../../sm8475/asphalt/PATCHES.md#ufs-clocks-and-phy):
the GCC and its GDSCs are parented to RPMh CX (0082-0084), so the UFS OPP
table's CX levels (0089: 75 MHz at LOW_SVS for HS-G1, 850 MHz at TURBO_L1
for HS-G4, node-level NOM) are actually voted; `qcom,sm8475-ufshc` (0087)
selects the controller's turbo configuration above 300 MHz (0088); 0085
programs the full PHY tables for every gear; 0086 sources 850 MHz from
GPLL3. The shared
`ufs-qcom-lane-clocks-only.patch` (upstream `f07317a8d57f`) applies to
Marble as to every Qualcomm board. Marble keeps 0081 (no PHY retention, the same change as Asphalt's 0027)
and the USB GDSC polling of 0015; 0091 drops 0015's `ALWAYS_ON` on the UFS
PHY GDSC, which Asphalt never had: with the GDSC under CX it kept the UFS
TURBO_L1 vote in suspend. On hardware (0082–0089) the link ran HS-G4 without
errors under 2 x 2 GiB writes, and `s2idle` resumed at `spm_lvl` 3 and 5.

### Bootloader display handoff

Marble uses [Esteban Urrutia's Lucid OLE PLL fix](https://lore.kernel.org/all/20260713-sm8450-qol-dispcc-v3-3-56fd05822270@proton.me/)
from Asphalt patch 0020. ABL leaves a display PLL running as
the source of the MDP clock; reconfiguring it at probe stopped it under that
clock, so the clock could not be parked (`disp_cc_mdss_mdp_clk_src: rcg
didn't update its configuration` at boot). With Asphalt 0020 the display clock
controller keeps a PLL that is already running and the warning is gone, but
on its own the 36 0d 0b panel still stays black at boot: it does not answer
DCS reads until a display off/on cycle.

0047 powers that panel down at probe: ABL leaves it powered, so the driver
takes the supplies, turns them off in the stock order with reset held and
waits 500 ms, before attaching to the DSI host, so the link is first brought
up with a freshly powered panel. With both fixes, the 36 0d 0b panel lit
from boot on two hardware trials without diagnostic tracing.

### Panel variants

Marble phones carry either the M16T "36 02 0a" panel (0016,
`xiaomi,marble-m16t-36-02-0a`) or the "36 0d 0b" panel (0047,
`xiaomi,marble-m16t-36-0d-0b`); ABL reports which one in
`msm_drm.dsi_display0`. 0047 was generated with
[linux-mdss-dsi-panel-driver-generator](https://github.com/msm8916-mainline/linux-mdss-dsi-panel-driver-generator)
from the stock device tree and adapted: stock supply order and delays, the
36 02 0a reset pulse (high 11 ms, low 1 ms, high 11 ms; the panel does not
respond after its own stock sequence, low 1 ms then high 20 ms), both
DSC slices in one packet, and a DSC configuration equal to the PPS that the
stock on sequence writes with manufacturer command `0x70` (DSC 1.1, 10 bpc,
8 bpp, 540×12 slices). The DTB describes 36 02 0a; U-Boot changes the panel
compatible and the vddd voltage (1.256 V for 36 0d 0b) when it hands the DTB
to Linux, see the the U-Boot package.
See the [display guide](../../../../docs/marble/display.md) for the panel
variants and their selection.

### Not in this queue

| linux-marble commit | Reason |
| --- | --- |
| `b1e762036636` phy: qcom: qmp-pcie: add SM8475 Gen3x1 PCIe PHY support | Upstream in 7.3 as [`9e953732c3ed`](https://git.kernel.org/torvalds/c/9e953732c3ed). |
| `47e7100474a4` remoteproc: qcom: q6v5: disable handover IRQ once handled | Superseded by upstream [`bb7c5d6f5b41`](https://git.kernel.org/torvalds/c/bb7c5d6f5b41) ("Make handover IRQ one-shot") in 7.3. |
| `f5bc71d7372e` ASoC: qcom: sc8280xp: support TDM backends and 32-bit slots | Replaced by 0054 and 0064: 7.3 has TDM `hw_params` with standard DAI TDM slot properties; the board rate, format, core vote and card-held bit clock moved into a board card entry instead of `qcom,tdm-*` card properties. |
| `e21870ba92a9` ASoC: qcom: sc8280xp: connect Marble handset voice routes | Deferred (voice calls, a later step): builds on `f5bc71d7372e`. Its probe-time request of the speaker/earpiece GPIO (output, speaker) is in 0054. |
| `2c0bbc6ec3cc` ASoC: qcom: sc8280xp: preserve DT DAPM routes when adding voice routes | Deferred: fixes `e21870ba92a9`. |

### Speaker TDM

The speakers are two AW88263S amplifiers on the tertiary TDM interface, run
as on stock Android: 96 kHz, 32-bit samples in four 32-bit slots, short frame
sync with a one-bit delay. As the stock group device (`channels 3`,
`slot_mask 7`), the backend carries three channels in slots 0-2 (0075); the amplifiers' ACF selects slot 0 for the amplifier at 0x34
(top speaker) and slot 1 for the one at 0x35 (bottom speaker), and the top
amplifier takes TDM ultrasound input from a further slot (SYSCTRL
`ULS_MODE`). Stock fills slot 2 from its ultrasound backend; here the
device MFC outputs FL/FR/FC, so the slot is driven instead of idle. Linux 7.3 handles TDM through the
topology-driven Audio IF modules (`MODULE_ID_AUDIO_IF_*`, 0x0700117C), but
the SM7475 ADSP (ADSP.HT.5.7-01183) registers only the older TDM, I2S and
codec DMA endpoints (its image contains 0x0700100E/F, not 0x0700117C/D).
0052 adds the older TDM modules and configures them from the Audio IF
topology tokens. The board topology (`pkgs/marble/audio`) uses them. 0054
adds the board card, which sets 96 kHz S32_LE, votes for the LPASS core
while the backend runs, and selects the speaker at probe. The TDM path
sets the slots from the DT. 0064 holds the TDM bit clock and LPASS DCODEC
vote from backend startup to shutdown. Both speakers play at the stock
amplifier level.

### SLPI sensors

The stock SLPI firmware (SLPI.HY.5.0, `slpius.jsn`) registers the
`msm/slpi/sensor_pd` protection domain with the `tms/servreg` service, as
the SM8475 Lenovo TB320FC does. The shared FastRPC patch subscribes to that
domain when the FastRPC node names it in `qcom,protection-domain`, so its
service registry notifications are acknowledged; 0078 sets that property on
the SLPI FastRPC node. The pd-mapper already describes the domain (0010:
`qcom,sm8475` uses the SM8350 domain list). This is an acknowledgement
subscription, not static-PD restart handling. The userspace side is
described in [Marble sensors](../../../../docs/marble/README.md#sensors).

## Configuration

Built in for the module-free RAM recovery: SM8475 pinctrl, SM8450 GCC, display
and GPU clocks and interconnects, UFS, the eUSB2 PHY with the PTN3222 repeater,
DWC3, the ACM/NCM gadget functions, simpledrm, DRM MSM with both M16T panel drivers,
the Goodix Berlin SPI touchscreen, GPIO and PMIC keys, `PSTORE_RAM`, ext4 and
VFAT. The haptics, AW88261 and IPA drivers are modules, as are the
microphone path (Qualcomm SoundWire, WCD938x, LPASS RX/TX/VA macros).
`PM_DEBUG` and `PM_SLEEP_DEBUG` provide `/sys/power/pm_test`,
`pm_wakeup_irq` and `pm_print_times` for the suspend bring-up; the PMK8350
RTC driver (`RTC_DRV_PM8XXX`) is a module.

The device module passes `fw_devlink=permissive pcie_aspm=off`, as the
community port does; RAM recovery also passes `clk_ignore_unused
pd_ignore_unused regulator_ignore_unused`
(`hardware.marble.ignoreUnusedClocksAndDomains`,
`hardware.marble.ignoreUnusedRegulators`).

## Build

```sh
nix build .#devices.marble.kernel
```

Maintain the queue with [`tools/kernel-queue.py`](../../../../tools/kernel-queue.py)
(`--device marble --version 7.3.1 --base v7.3.1`), as described in the
[development guide](../../../../docs/development.md).
