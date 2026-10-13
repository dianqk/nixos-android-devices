# Sheng kernel

[中文](PATCHES.zh.md) · [Sheng guide](../../../../docs/sheng/README.md)

The queue targets Linux 7.3-rc6; the hardware results below were obtained
with earlier 7.3 kernels. See the [shared kernel status](../../README.md).

`devices.sheng.kernel` applies the ordered [patch series](series.nix).
Installed systems and RAM recovery use the same kernel package. The package uses `config.aarch64` and builds
`sm8550-xiaomi-sheng.dtb`.

Each patch names its source commits and local 7.3 adaptations;
[ORIGINS.md](patches/ORIGINS.md) retains original authors, dates, messages and
trailers. Display and WCN7850 Wi-Fi work on the installed system; other peripheral
limitations are listed in the
[hardware reference](../../../../docs/sheng/hardware.md).

The [Lucid OLE patch](patches/upstream/0001-lucid-ole-preserve-enabled-pll.patch)
preserves a PLL already enabled by the bootloader before display-clock RCGs
are parked. SM8550 uses this same PLL configuration path; disabling the
inherited clock can cause an MDP RCG update timeout during display takeover.
The patch is carried unchanged with its original author and upstream link.
It does not change the panel, DSI PLL rate calculation, DTB or kernel config.
Without it the display starts black with an MDP RCG update timeout. See [hardware status](../../../../docs/sheng/hardware.md).

The 7.3-rc6 series also carries the Lucid OLE guard and the upstream
[Qualcomm PCIe IOMMU-cell parser fix](../../patches/pcie-qcom-iommu-cells.patch).
The latter makes the BDF-to-SID table consume the provider's actual cell count;
SM8550's valid five-cell maps otherwise get parsed with a four-cell stride.
It retains the original patch, author, date and trailers, with only a source
Link added. The malformed-map revert from the device fork is omitted. With it,
WCN7850 firmware loads without a BHI timeout.

Upstream commit `58aeb412495a`'s larger MAC buffer ring causes WMI timeouts
with Sheng's firmware. The local
[Sheng firmware compatibility patch](patches/7.3/0025-ath12k-sheng-mac-buffer-ring.patch)
retains 2048 entries for Sheng's WCN7850 with HMT.1.1.c2-00259 firmware;
other boards keep the upstream 4096-entry default. The larger RX release ring
is unchanged. Retain a working rollback generation while other peripherals
remain unverified.

On an x86_64 host, this output uses an x86_64 build platform and an AArch64
host platform. Build the kernel with:

```sh
nix build .#devices.sheng.kernel --out-link result-kernel
```

The 7.3 series includes the board, display, input, battery, audio, camera, Type-C,
DP, WCN7850 and FPC1553 fingerprint changes needed for the current
configuration. Fingerprint userspace requires the FPC1553 driver and DT node.
The remaining peripherals still need device validation.

The FPC1553 driver has two known limitations: a
prepare disable/enable cycle does not re-enable an already requested IRQ, and
remove unregisters sysfs after releasing its resources. Neither path has been
validated on Sheng.

Kernel patches follow the upstream Linux GPL-2.0 terms and any license
notices in the changed files.

The shared [Iris decode-order](../../patches/iris-hfi-gen2-decode-order.patch)
and [capture-pool](../../patches/iris-hfi-gen2-capture-pool.patch) patches are
also used by Asphalt. They expose the HFI gen2 zero display-delay controls and
allow up to 64 decoder capture buffers for synchronous VA-API clients. Their
contents, authors and trailers are unchanged from Xilin Wu's patches in
[libva-v4l2 v1.0.0](https://github.com/radxa-pkg/libva-v4l2/tree/0e4ce1e05da1d0a92b342efc2090b9e4987035e1/patches).
These patches do not add 10-bit encoder input formats.

The single-pdev regulatory range fix is shared with Aurora in
[ath12k-single-pdev-reg.patch](../../patches/ath12k-single-pdev-reg.patch).
Its existing Sheng hunks are unchanged; only their location and provenance
header changed. It corrects band indices and preserves 5 GHz when a combined
radio also supports 6 GHz. Multi-pdev shared-state races remain outside its scope.

## Sync state

The [shared GMU series](../../patches/gmu-sync-state/README.md) binds a driver to the GMU, and the `unused-crypto` patch disables the unused QCE node (Linux 7.3 marks its driver BROKEN), so supplier `sync_state()` no longer waits for the whole boot.
