# Polaris Linux kernel

[中文](PATCHES.zh.md) · [Polaris index](../../../../docs/polaris/README.md)

The queue targets Linux 7.3-rc6; hardware results for this device were obtained
with earlier 7.x kernels. See the [shared kernel status](../../README.md).

The package selects `linuxPackages_testing.kernel` from Nixpkgs.
It targets Linux 7.3-rc6. [`series.nix`](series.nix) lists active patches in
application order. The package builds `qcom/sdm845-xiaomi-polaris.dtb` and
Android-compatible `Image.gz` with LLVM 23.

The MDSS boot power-domain patch is Dmitry Baryshkov's
[upstream submission](https://lore.kernel.org/r/20260217-sdm845-hdk-v1-1-866f1965fef7@oss.qualcomm.com).
It preserves the original author, date, explanation and sign-off/review trailers;
the code is unchanged. Only a source `Link` trailer was added. It allows the
bootloader-enabled display domain to power down before Linux initializes it.

PCM v2 uses S16_LE or MSB-aligned 24-bit samples in S32_LE containers.
The q6asm alignment patch declares that format and 24 significant bits.

Camera support uses the SDM845 community IMX363 driver from
[`dbc31cca7`](https://gitlab.com/sdm845-mainline/linux/-/commit/dbc31cca7cadbb97c2bee0ff7c8a3f86a7b25273)
and the upstream OV5675 driver. The IMX363 import refreshes only Kconfig and
Makefile context for Linux 7.3; its added code is unchanged. Local patches
hold IMX363 reset during probe,
control the Polaris module-enable GPIO, propagate clock failures, and connect
the front and main rear sensors to CAMSS.
Supply and GPIO assignments follow Xiaomi's
[production-board overlay](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/blob/polaris-o-oss/arch/arm64/boot/dts/qcom/polaris-p1-camera-sensor-mtp.dtsi)
and [base camera description](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/blob/polaris-o-oss/arch/arm64/boot/dts/qcom/polaris-camera-sensor-mtp.dtsi).

The local clock orphan patch avoids forcing idle parent clocks on while merely
linking the registered clock tree. It preserves prepared/critical reference
migration and normal runtime reparenting. Its rationale follows
[Stephen Boyd's registration fix](https://www.mail-archive.com/linux-kernel@vger.kernel.org/msg1630217.html)
and [Jerome Brunet's reference-migration follow-up](https://lkml.rescloud.iu.edu/1802.0/03657.html);
the current change is a local implementation, not either original patch.

The QRTR nameserver change retains the `ns.c` portion of
[Takashi Iwai's HELLO proposal](https://lore.kernel.org/all/878q55sfxo.wl-tiwai@suse.de/),
including original authorship and message, with the partial import documented.
A separate local patch coalesces HELLO sends under the endpoint lock, retaining
proactive registration while sending HELLO before service announcements. Both now live in the shared
`pkgs/linux-kernel/patches/qrtr-hello/` directory, which Aurora also uses.
These changes target Polaris initial SMD startup; MHI suspend/resume and arbitrary
transport failure recovery are outside the verified scope.

## Imported community patches

These patches retain their original mail headers and commit messages.

| Patch | Original author | Source commit |
| --- | --- | --- |
| `0001-nt35596s-panel.patch` | Arnaud Ferraris | [`3b0c2c8d57`](https://gitlab.com/sdm845-mainline/linux/-/commit/3b0c2c8d5707d5fb41fbfe1cb17ec09c87fe35a5) |
| `0002-pmi8998-fuel-gauge.patch` | Joel Selvaraj | [`dad5ba4bf9`](https://gitlab.com/sdm845-mainline/linux/-/commit/dad5ba4bf9651fbab6b4e69b51f0fd85808d4dcd) |
| `0003-tas2559-codec.patch` | Joel Selvaraj | [`15a2625230`](https://gitlab.com/sdm845-mainline/linux/-/commit/15a2625230216f9911fa29837620d87a8ede7532) |
| `0004-pmi8998-fg-binding.patch` | Yassine Oudjana | [`b2ac93767d`](https://gitlab.com/sdm845-mainline/linux/-/commit/b2ac93767db99546c1a82a2da1876c69e0e3b351) |
| `0005-pmi8998-fg-node.patch` | dianqk | [`8189a12c5e`](https://gitlab.com/sdm845-mainline/linux/-/commit/8189a12c5e03972ff5b5f194d332d42c31affc06) |
| `0006-ath10k-split-amsdu.patch` | Richard Acayan | [`2fc5766fb5`](https://gitlab.com/sdm845-mainline/linux/-/commit/2fc5766fb5a281b61d03ae5786b23c7795af87b0) |
| `0016-imx363-sensor.patch` | Joel Selvaraj | [`dbc31cca7c`](https://gitlab.com/sdm845-mainline/linux/-/commit/dbc31cca7cadbb97c2bee0ff7c8a3f86a7b25273) |

- `0023-polaris-ramoops.patch` adapts the attributed Xiaomi SDM845 downstream
  ramoops reservation (4 MiB at `0xb0000000`) to Polaris. It retains the record
  layout and includes normal shutdown dumps. Hardware checks recovered a pmsg
  marker and the preceding console after an isolated modem-stop reset. This
  enables diagnosis; it does not fix the shutdown failure.

- `0024-polaris-rmtfs-guards.patch` adapts Caleb Connolly's
  [SDM845 RMTFS guard fix](https://github.com/torvalds/linux/commit/e60fd5ac1f6851be5b2c042b39584bfcf8a66f57)
  using the current `qcom,use-guard-pages` binding. The expanded reservation
  retains the effective `0xf6301000` / `0x200000` payload. Polaris downstream
  also requires these guards. This alone did not fix modem-stop resets.
- `0025-polaris-ipa.patch` restores the upstream IPA node, paired with the
  built-in driver and early IPA firmware. Without IPA initialization, an
  accepted modem shutdown request timed out waiting for its acknowledgement
  and the phone reset. With IPA initialized, the modem acknowledged shutdown
  and completed resource reclaim; repeated isolated stop/start tests passed.
  This does not establish which IPA hardware or handshake dependency caused
  the failure, nor does it validate complete phone poweroff.

- `0027-polaris-fastrpc-sessions.patch` enables two connections on the existing
  SLPI context bank: the native listener holds a coherent-memory allocator
  descriptor and a separate sensor RPC transport descriptor. The inherited
  single-session limit makes its second open fail with `EBUSY`, preventing
  registry initialization and eventually triggering the sensor watchdog.
  SSC clients communicate over QRTR and do not require additional sessions.

- `fastrpc-sdsp-dmabuf-pool.patch` allocates exported buffers for SDSP without
  an IOMMU from its already shared reserved pool, matching RPC metadata.
  Exporting ordinary CMA buffers otherwise stalls the listener's first data
  request on Polaris. The complete allocation must stay inside the shared
  region, including when the DMA allocator falls back after pool exhaustion.
  Buffers retain their allocation device and original DMA handle until release.
  VMIDs and subsystem-restart ownership policy are unchanged.

## Sync state

The [shared GMU series](../../patches/gmu-sync-state/README.md) binds a driver to the GMU, and the `unused-crypto` patch disables the unused QCE node (Linux 7.3 marks its driver BROKEN), so supplier `sync_state()` no longer waits for the whole boot.
