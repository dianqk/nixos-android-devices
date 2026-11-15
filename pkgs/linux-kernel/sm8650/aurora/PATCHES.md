# Aurora kernel

[中文](PATCHES.zh.md) · [Aurora guide](../../../../docs/aurora/README.md)

`devices.aurora.kernel` applies an ordered patch queue to Linux 7.3. The
authoritative list and order are in [`default.nix`](default.nix); shared
patches live in [`../../patches`](../../patches), board patches in this
directory. The base configuration is Sheng's `config.aarch64` with the common
reductions, SM8650 requirements and the Aurora overrides in `default.nix`.
Each patch keeps its original author, message and upstream link where one
exists; local adaptations are described in the patch. See the
[shared kernel status](../../README.md) and
[hardware support](../../../../docs/aurora/hardware.md).

| Area | Patches | Purpose |
| --- | --- | --- |
| Shared display | [DSC full ICH precision](../../patches/dpu-sm8650-dsc-full-ich-precision.patch), [DSC 1.2 RC model](../../patches/dsi-dsc-12-rc-model.patch), [first-line BPG offset](../../patches/dsi-dsc-12-first-line.patch), [DSI PHY interface clock runtime PM](../../patches/dsi-phy-iface-clk-runtime-pm.patch) | DSC parameters required by the N1 panel; display clock controller released with the display off |
| Shared USB and power | [NCM TX timer](../../patches/usb-ncm-retry-busy-timer.patch), [battmgr charge units](../../patches/qcom-battmgr-default-charge-unit.patch), [battmgr notification](../../patches/qcom-battmgr-serialize-notification-request.patch), [power-supply readiness](../../patches/power-supply-firmware-readiness.patch) | NCM throughput, ADSP battery reporting |
| Board | `board.patch`, `n1-board.patch`, `keys.patch`, `power.patch`, `unused-crypto.patch`, `ufs-mcq.patch`, `ramoops.patch` | Board DT, DSI panel wiring, keys, ADSP battery and USB2 roles, disabled QCE, UFS MCQ, ramoops with oops records |
| Touch | `touch.patch`, `touch-panel-follower.patch` | S3910P raw SPI transport and wiring; controller powered off with the panel |
| GPU | `gpu.patch`, [GMU sync_state series](../../patches/gmu-sync-state/README.md) | Adreno 750 with OEM ZAP firmware; GMU component binding |
| Battery | `battmgr-property-ids.patch`, `battmgr-reporting.patch`, `battmgr-charge-control.patch`, `battmgr-adsp-log.patch`, `battmgr-usb-icl.patch`, `usb-psy-name.patch` | Aurora OEM battmgr property IDs and current sign; USB charger type, no ID resistor as internal resistance; charge thresholds with the firmware enable and a writable charge current cap; ADSP charger log through dynamic debug; USB input current limit from the gadget current |
| Audio | [q6apm readiness](../../patches/q6apm-probe-readiness.patch), [CS35L43 codec](../../patches/cs35l43-codec.patch), [CS35L43 DAI clock](../../patches/cs35l43-dai-clock.patch), [legacy TDM endpoint](../../patches/audioreach-legacy-tdm.patch), `audio.patch`, `audio-codec-clock.patch` | WCD9395 and dual CS35L43 speakers; see [audio](../../../../docs/aurora/audio.md) |
| Video | `video.patch`, [HFI gen2 decode order](../../patches/iris-hfi-gen2-decode-order.patch), [HFI gen2 capture pool](../../patches/iris-hfi-gen2-capture-pool.patch) | Iris with OEM VPU33 firmware, VA-API requirements |
| Wi-Fi and Bluetooth | `radio.patch`, `wifi-qmi-mlo.patch`, [ath12k single-pdev regulatory](../../patches/ath12k-single-pdev-reg.patch), [PCIe IOMMU cells](../../patches/pcie-qcom-iommu-cells.patch), `pcie-suspend-opp-floor.patch`, `pcie-suspend-opp.patch`, `pcie-suspend-floor-modes.patch`, `pci-host-common-endpoint-d3cold.patch` | WCN7850 wiring, OEM Kiwi-v2 QMI resources, 5 GHz range, PCIe SID parsing; only endpoints veto D3cold, so the link is torn down in s2idle (armada; `pci_host_common.endpoint_d3cold`); an optional suspend-only PCIe OPP floor as a fallback (armada; `pcie_qcom.suspend_opp_floor` = off (default), full, cx, or bw with `suspend_floor_kbps`) |
| Supplies | `optional-supplies.patch` | Optional legacy supplies acquired explicitly (DRM, PCIe) |
| USB3 and DP | `usb-dp.patch` | SuperSpeed, combo PHY, WCD9395 mux and DP |
| N1 panel and scanout | `n1-panel.patch`, `n1-transfer.patch`, `n1-120hz.patch`, `n1-30hz.patch`, `n1-boot-power-cycle.patch`, `cmd-disabled-flush.patch`, `cmd-multirect.patch`, `cmd-tearcheck.patch`, `sm8650-mdss-identity.patch`, `lucid-ole-preserve-enabled-pll.patch` | N1 DSC command-mode panel at 30/60/120 Hz with a cold power-up after the bootloader, SM8650 command scanout, display takeover |
| Clocks | `gcc-cx-binding.patch`, `gcc-cx-runtime-pm.patch`, `gcc-cx-domain.patch`, `pcie-gdsc-off.patch` | GCC GDSCs tied to the RPMh CX domain (linux-next); PCIe controller and PHY GDSCs powered off in suspend (armada) |
| Modem | `modem.patch`, [IPA v5.5 configuration](../../patches/ipa-v5.5-config.patch), [QRTR HELLO and announcement fixes](../../patches/qrtr-hello), [PAS exclusive-region reassignment](../../patches/pas-reassign-exclusive-regions.patch) | MPSS, IPA and rmtfs memory; modem downlink; service announcement; MPSS restart without a phone reset. See [modem services](../../../../docs/modem.md) |
| Camera | `imx858.patch`, `camera-ultra.patch`, `ov32b40.patch`, `camera-tele-front.patch`, `lyt900.patch`, `camera-wide-tele5x.patch`, [CAMSS stream unwind](../../patches/camss-stream-unwind.patch), [CAMSS C-PHY series](../../patches/camss-cphy/README.md), [SM8650 C-PHY lane settings](../../patches/camss-sm8650-cphy.patch), [gen3 CSID C-PHY select](../../patches/camss-csid-gen3-cphy.patch), [C-PHY CSIPHY clock](../../patches/camss-csiphy-cphy-clock.patch) | Sony IMX858 (ultra-wide, tele 3.2x, tele 5x) and LYT-900 (wide) drivers with fixed 4096x3072 RAW10 modes, an OmniVision OV32B40 driver (front, not yet enabled); CCI, CSIPHY and supply wiring; C-PHY receive on SM8650; the MIPI path select of the wide and tele 3.2x |

Build the kernel on an x86_64 or AArch64 Linux host with:

```sh
nix build .#devices.aurora.kernel --out-link result-kernel
```

An x86_64 build produces an AArch64 kernel with Clang/LLD from `buildPackages`.
Linux kernel patches follow the upstream GPL-2.0 terms and the SPDX notices of
the files they modify.
