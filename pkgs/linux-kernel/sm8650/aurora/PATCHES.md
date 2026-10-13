# Aurora kernel

[中文](PATCHES.zh.md) · [Aurora guide](../../../../docs/aurora/README.md)

`devices.aurora.kernel` applies an ordered patch queue to Linux 7.3-rc6. The
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
| Shared display | [DSC full ICH precision](../../patches/dpu-sm8650-dsc-full-ich-precision.patch), [DSC 1.2 RC model](../../patches/dsi-dsc-12-rc-model.patch), [first-line BPG offset](../../patches/dsi-dsc-12-first-line.patch) | DSC parameters required by the N1 panel |
| Shared USB and power | [NCM TX timer](../../patches/usb-ncm-retry-busy-timer.patch), [battmgr charge units](../../patches/qcom-battmgr-default-charge-unit.patch), [battmgr notification](../../patches/qcom-battmgr-serialize-notification-request.patch), [power-supply readiness](../../patches/power-supply-firmware-readiness.patch) | NCM throughput, ADSP battery reporting |
| Board | `board.patch`, `n1-board.patch`, `keys.patch`, `power.patch`, `unused-crypto.patch`, `ufs-mcq.patch` | Board DT, DSI panel wiring, keys, ADSP battery and USB2 roles, disabled QCE, UFS MCQ |
| Touch | `touch.patch` | S3910P raw SPI transport and wiring |
| GPU | `gpu.patch`, [GMU sync_state series](../../patches/gmu-sync-state/README.md) | Adreno 750 with OEM ZAP firmware; GMU component binding |
| Battery | `battmgr-property-ids.patch` | Aurora OEM battmgr property IDs and current sign |
| Audio | [q6apm readiness](../../patches/q6apm-probe-readiness.patch), [CS35L43 codec](../../patches/cs35l43-codec.patch), [CS35L43 DAI clock](../../patches/cs35l43-dai-clock.patch), [legacy TDM endpoint](../../patches/audioreach-legacy-tdm.patch), `audio.patch`, `audio-codec-clock.patch` | WCD9395 and dual CS35L43 speakers; see [audio](../../../../docs/aurora/audio.md) |
| Video | `video.patch`, [HFI gen2 decode order](../../patches/iris-hfi-gen2-decode-order.patch), [HFI gen2 capture pool](../../patches/iris-hfi-gen2-capture-pool.patch) | Iris with OEM VPU33 firmware, VA-API requirements |
| Wi-Fi and Bluetooth | `radio.patch`, `wifi-qmi-mlo.patch`, [ath12k single-pdev regulatory](../../patches/ath12k-single-pdev-reg.patch), [PCIe IOMMU cells](../../patches/pcie-qcom-iommu-cells.patch) | WCN7850 wiring, OEM Kiwi-v2 QMI resources, 5 GHz range, PCIe SID parsing |
| Supplies | `optional-supplies.patch` | Optional legacy supplies acquired explicitly (DRM, PCIe) |
| USB3 and DP | `usb-dp.patch` | SuperSpeed, combo PHY, WCD9395 mux and DP |
| N1 panel and scanout | `n1-panel.patch`, `n1-transfer.patch`, `n1-120hz.patch`, `n1-30hz.patch`, `cmd-disabled-flush.patch`, `cmd-multirect.patch`, `cmd-tearcheck.patch`, `sm8650-mdss-identity.patch`, `lucid-ole-preserve-enabled-pll.patch` | N1 DSC command-mode panel at 30/60/120 Hz, SM8650 command scanout, display takeover |
| Clocks | `gcc-cx-binding.patch`, `gcc-cx-runtime-pm.patch`, `gcc-cx-domain.patch` | GCC GDSCs tied to the RPMh CX domain (linux-next) |
| Modem | `modem.patch`, [IPA v5.5 configuration](../../patches/ipa-v5.5-config.patch), [QRTR HELLO and announcement fixes](../../patches/qrtr-hello), [PAS exclusive-region reassignment](../../patches/pas-reassign-exclusive-regions.patch) | MPSS, IPA and rmtfs memory; modem downlink; service announcement; MPSS restart without a phone reset. See [modem services](../../../../docs/modem.md) |

Build the kernel on an x86_64 or AArch64 Linux host with:

```sh
nix build .#devices.aurora.kernel --out-link result-kernel
```

An x86_64 build produces an AArch64 kernel with Clang/LLD from `buildPackages`.
Linux kernel patches follow the upstream GPL-2.0 terms and the SPDX notices of
the files they modify.
