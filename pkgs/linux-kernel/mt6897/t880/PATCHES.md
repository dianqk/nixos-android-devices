# T880 kernel patches

[中文](PATCHES.zh.md) · [T880 guide](../../../../docs/t880/README.md)

This is the device patch queue for the locked Linux 7.3.1 release. The order is
in [`series.nix`](series.nix); configuration is in [`kernel.config`](kernel.config)
and [`trim.nix`](trim.nix). See the T880 guide above for builds, installation and
feature status. The shared `usb-ncm-retry-busy-timer.patch` comes first, followed
by 244 device patches here (245 total). No Qualcomm shared patch applies.

Imported preparatory series retain their order, mail authors, dates, messages,
trailers and source links. Local followups are consolidated by subsystem, with
bindings/interfaces before implementations, build activation after source files,
and device trees last. Vendor imports remain separate from MT6897 adaptations;
each patch records its source selection and attribution.

## Imported sources

| Patches | Source | Selection and authors |
| --- | --- | --- |
| [0001](patches/tb375fc-linux/0001-mt6897-source-dtsi.patch) | [tb375fc-linux aef99312](https://github.com/u0n0u/tb375fc-linux/commit/aef99312cbe5619b83857e71efe6f0afe7d2c39b) | Villode; selected SoC DTS |
| [0002](patches/local/0002-i2c-mediatek-support-the-mt6983-generation-controller-mt6895.patch) | [MT6895-Mainline abb5229e](https://github.com/MT6895-Mainline/linux/commit/abb5229ecbe3145a19fb1f8b905fc0e99e3f6b9a) | Hecheng Yu; selected I²C controller changes |
| [0003](patches/mt6895-mainline/0003-spmi-mtk-pmif-clear-observed-slave-eint-status-bits.patch)–[0004](patches/mt6895-mainline/0004-spmi-mtk-pmif-fix-slave-irq-bank-calculation.patch) | [MT6895-Mainline](https://github.com/MT6895-Mainline/linux) | Hecheng Yu; PMIF slave interrupt fixes |
| [0005](patches/lore/0005-spmi-print-error-status-with-pe-format.patch)–[0008](patches/lore/0008-spmi-implement-spmi-subdevice-alloc-and-add-and-devm-variant.patch) | [SPMI subdevices v7](https://lore.kernel.org/all/20251021083219.17382-1-angelogioacchino.delregno@collabora.com/) | AngeloGioacchino Del Regno; preparation and subdevice API |
| [0009](patches/lore/0009-clk-mediatek-split-out-registration-from-mtk-clk-register-gates.patch)–[0015](patches/lore/0015-clk-mediatek-add-support-for-mt6685-pm-clock-ic-clock-controller.patch) | [SPMI clocks v2](https://lore.kernel.org/all/20251027111343.21723-1-angelogioacchino.delregno@collabora.com/) | AngeloGioacchino Del Regno; clock helpers and MT6685 |
| [0016](patches/lore/0016-dt-bindings-rtc-add-mediatek-mt6685-pm-clock-ic-real-time-clock.patch)–[0017](patches/lore/0017-rtc-add-support-for-mt6685-clock-ic-s-rtc-over-spmi.patch) | [MT6685 RTC](https://lore.kernel.org/all/20251024083318.25890-1-angelogioacchino.delregno@collabora.com/) | AngeloGioacchino Del Regno; RTC |
| [0018](patches/lore/0018-dt-bindings-mfd-add-binding-for-mediatek-mt6363-series-spmi-pmic.patch)–[0019](patches/lore/0019-mfd-add-support-for-mediatek-spmi-pmics-and-mt6363-73.patch) | [SPMI PMIC MFD v12](https://lore.kernel.org/all/20260511101355.122478-1-angelogioacchino.delregno@collabora.com/) | AngeloGioacchino Del Regno; selected MFD/binding |
| [0020](patches/lore/0020-dt-bindings-display-mediatek-dsc-add-mt8196-compatible.patch)–[0078](patches/lore/0078-drm-mediatek-mtk-drm-drv-fail-init-only-if-all-paths-are-invalid.patch) | [DSC/DSI/WDMA v9](https://patchwork.kernel.org/project/linux-mediatek/list/?series=1166385), [display restructuring v2](https://patchwork.kernel.org/project/linux-mediatek/list/?series=1127365) | Original authors/trailers and release adaptations retained |
| [0079](patches/local/0079-soc-regulator-mfd-power-add-mt6895-pmic-and-power-domain-support.patch)–[0080](patches/local/0080-usb-typec-xaga-add-mt6375-tcpc-dual-role-type-c-support.patch) | [tb375fc-linux](https://github.com/u0n0u/tb375fc-linux) | Hecheng Yu; selected MT6375 MFD and TCPC |
| [0081](patches/lore/0081-memory-mtk-smi-fail-larb-runtime-resume-until-component-bind.patch) | [mtk-smi fix](https://lore.kernel.org/all/20260926192417.1448813-1-valentin.haudiquet@canonical.com/) | Valentin Haudiquet; defer runtime resume until component bind |
| [0082](patches/local/0082-misc-mediatek-import-the-vendor-ccci-util-for-mt6897.patch)–[0083](patches/local/0083-misc-mediatek-import-the-vendor-eccci-and-ccmni-for-mt6897.patch) | [MiCode 3c4ccd07](https://github.com/MiCode/MTK_kernel_device_modules/tree/3c4ccd07d5624879555ec710c11bb8818e5cb5c6/drivers/misc/mediatek) | Unmodified CCCI utility, ECCCI and CCMNI source; 何发云, 2024-01-12 |
| [0084](patches/local/0084-eccci-write-the-ccif-sram-info-tail-to-the-md-window-as-well.patch)–[0086](patches/local/0086-misc-mediatek-eccci-expose-the-at-port-as-a-standard-tty-ttyccci0.patch) | [MT6895-Mainline qqcandy](https://github.com/MT6895-Mainline/linux) | Furruka; CCIF SRAM tail and ttyCCCI0; separate local Makefile adapter at0085 |
| [0087](patches/local/0087-arm64-mediatek-xaga-add-the-mt6895-vcp-multimedia-platform.patch) | [VCP source 591943ef](https://github.com/MT6895-Mainline/linux/commit/591943ef425cd42eca7583f4a56be73fc3aef596), [snapshot f1c0c824](https://github.com/MT6895-Mainline/linux/tree/f1c0c8245d163fece46699612b8322d11e26348d) | Silvia and Hecheng Yu; decoder-only selection, full source-update ledger retained |

The VCP import selects the stateful decoder frontends/backends, bitstream
helpers and transport API declarations. It excludes xaga board data, encoder,
regulator, remoteproc implementation and DVFS policy. The MT6897 encoder and
platform integration are subsequent local changes.

## Local integration

| Patches | Content |
| --- | --- |
| [0088](patches/local/0088-dt-bindings-mediatek-describe-mt6897-clock-resources.patch)–[0107](patches/local/0107-dt-bindings-mediatek-describe-mt6897-usb-phy-resources.patch) | Bindings and hardware IDs |
| [0108](patches/local/0108-drm-mediatek-declare-mt6897-display-controller-interfaces.patch)–[0118](patches/local/0118-mailbox-mediatek-support-mt6897-gce-firmware-contexts.patch) | Display interfaces; SPMI, input, thermal and mailbox providers |
| [0119](patches/local/0119-workaround-clk-mediatek-retain-firmware-owned-mt6897-mux-state.patch)–[0138](patches/local/0138-power-supply-mt6375-implement-reporting-and-battery-care.patch) | Clock, power, firmware, memory and charger support |
| [0139](patches/local/0139-phy-mediatek-support-mt6897-usb-phy-initialization.patch)–[0144](patches/local/0144-phy-mediatek-support-mt6897-c-phy-lanes.patch) | USB, Type-C, orientation and C-PHY |
| [0145](patches/local/0145-soc-mediatek-describe-mt6897-mmsys-and-mutex-routing.patch)–[0156](patches/local/0156-bluetooth-tolerate-unsupported-sync-train-parameters.patch) | Display routing, OVL/DSI/DSC/DP, panel, DMA ownership and Bluetooth |
| [0157](patches/local/0157-misc-mediatek-update-shared-ccci-declarations.patch)–[0167](patches/local/0167-misc-mediatek-integrate-mt6897-modem-module-builds.patch) | Vendor modem adapters, SCP sensors and build integration |
| [0168](patches/local/0168-media-mediatek-adapt-the-vcp-decoder-backend-to-mt6897.patch)–[0171](patches/local/0171-media-mediatek-enable-mt6897-vcp-codec-builds.patch) | VCP decoder, asynchronous queues, stateful encoder and build integration |
| [0172](patches/local/0172-arm64-dts-mediatek-describe-mt6897-soc-resources.patch)–[0177](patches/local/0177-workaround-arm64-dts-apply-t880-dram-proxy-floors.patch) | SoC, display and board device trees with explicit policy workarounds |

The appended [0178](patches/local/0178-dt-bindings-display-boot-ownership.patch)–[0180](patches/local/0180-arm64-dts-t880-display-boot-owners.patch) series adds independent inherited display DMA ownership, physical SMI supplier links and explicit transfer of the initial IOMMU guards. Physical and translated display paths have verified idle suspension and DMA-time reacquisition of both M4Us, display power cycles and cursor capture; physical-path H264 hardware encode/decode and translated-path H264 hardware decode pass.

## Retained workarounds

These commit subjects begin with `workaround: `. These commits document restrictions
required by the current hardware and firmware integration. Actual board force-VBUS
wiring, PHY/role lifecycle fixes and the OVL shadow-latching repair are not
classified as workarounds.

| Patch | Retained limitation |
| --- | --- |
| [0119](patches/local/0119-workaround-clk-mediatek-retain-firmware-owned-mt6897-mux-state.patch) | Partly superseded by 0184–0187: AP votes for eight muxes are implemented; firmware parents, VCP control and inherited boot votes remain restricted. |
| [0120](patches/local/0120-workaround-clk-mediatek-preserve-unmanaged-mt6897-pll-rates.patch) | 0186 replaces boot rate snapshots with direct register queries; non-TVDPLL programming remains unmanaged. |
| [0132](patches/local/0132-workaround-soc-mediatek-proxy-mt6897-dram-bandwidth-votes.patch) | CPU/devfreq load proxies and static floors substitute for the missing multimedia bandwidth policy. |
| [0137](patches/local/0137-workaround-mfd-mt6375-preserve-firmware-protection-settings.patch) | Firmware protection writes are restricted, with bounded charger exceptions and no TCPC software reset. |
| [0166](patches/local/0166-workaround-misc-mediatek-keep-modem-modules-permanent.patch) | Modem modules cannot unload or manually unbind because teardown is incomplete. |
| [0173](patches/local/0173-workaround-arm64-dts-avoid-duplicate-mt6897-cpu-throttling.patch) | Linux CPU trips remain above the firmware thermal target to avoid duplicate throttling. |
| [0177](patches/local/0177-workaround-arm64-dts-apply-t880-dram-proxy-floors.patch) | The board selects DRAM proxy votes and retained multimedia/vcore floors. |

The historical [0135](patches/local/0135-workaround-iommu-mediatek-hold-mt6897-mm-banks-active.patch) permanent probe hold is superseded by 0178–0180. Initial guards now transfer to independent boot owners and ordinary DMA consumers; it is no longer an active permanent-power workaround.

The [0181](patches/local/0181-ccci-validate-runtime-LK-metadata.patch)–[0183](patches/local/0183-selftests-mediatek-LK-metadata-boundaries.patch) series bounds LK metadata parsing and removes the captured board descriptor. It requires the matching U-Boot runtime forwarding update; see [upgrade order](../../../../docs/t880/README.md#modem-metadata-upgrade-order). Runtime forwarding, normal modem startup and RAM recovery through the updated U-Boot are verified on T880. The historical [0176](patches/local/0176-workaround-arm64-dts-retain-the-t880-lk-modem-tag-fallback.patch) captured-descriptor workaround is superseded.

0184–0187 add bounded AP mux voting, direct live PLL rate reporting and portable fault-injection tests. They partially supersede 0119/0120; parent changes, VCP ownership, inherited boot-vote transfer and non-TVDPLL controls remain unavailable.

0188 makes the eight mux AP votes atomic CCF enable/disable operations and
preserves unknown direct boot enables even with no inherited AP bit. 0189
prepares both OVL domains' explicit root references before any domain
initialization, enables them before HWV-on and retains them on uncertain
failures. It does not retire boot votes or establish physical off; see
clock ownership.

0190–0192 add an optional always-on SPM status source and an explicit OVL boot
ownership handoff. Strict physical-off epochs permit accounting transfer while
ordinary roots remain enabled; later normal last disable releases the AP vote.
Absent/failed/incomplete observations retain BOOT. Other inherited roots, parent
coherence and VCP controls remain restricted; hardware behavior is unverified.
See clock ownership.

0193 extends ordinary root ownership to MM_INFRA, DIS0/1 and VEN0/1, with
checked phased VENC power requests, selected topology admission and shared
ancestor quarantine. MM_INFRA preserves bootstrap ownership until direct VEN
admission. OVL epoch retirement remains OVL-only; the existing VENC leaf-gate
sequence and other clock ownership limitations remain. See
clock ownership.

0194 scopes DirectLink configuration clocks to individual component lifetimes,
with ordered port/config release and local rollback. Shared and shadow
components retain independent references; inactive bound links no longer hold
their config providers active. Physical-off observation remains necessary for
OVL boot-vote retirement.

0195 enables MT6897-only MMSYS/mutex runtime-PM participation and balances
mutex consumer references and CRTC prepare failures. Optional MMSYS clock-child
cleanup is guarded. This removes an ordinary domain-off blocker; CMDQ shutdown
quiescence and physical-off behavior still need separate validation.

0196 gives MT6897 DP_INTF serialized full runtime-PM/clock ownership, separate
successful bridge/component references and active-only debug register access.
Debug files pin the bridge allocation and become unavailable at unbind; retained
power is not force-drained. Other DPI/DVO clock behavior is unchanged.

0197 verifies MT6897 CMDQ channel stop before abort-task retirement, propagates
PM/suspend/reset/readback failures and latches a channel fault with one retained
power lease. Faulted submissions are rejected and IRQs acknowledge status without
retiring retained tasks. This does not repair framebuffer lifetime after a fault.

0198 also requires an empty mailbox framework TX queue at the MT6897 checked-stop
boundary. A queued token after task-allocation failure cannot later dispatch after
power release; actual mailbox-core retry tests cover this boundary.

0199 checks MT6897 stop before CRTC packet reuse and target teardown, retaining
component/mutex/PM ownership on uncertainty. Faulted CRTC work and future commits
are blocked, with balanced owned/current/queued events. Independent bridge
callbacks and framebuffer/manual-unbind safety after faults remain outside this
power-retention guarantee.

0200–0201 add the MT6897 C-PHY configuration clock, per-link MMSYS routing
restore and balanced power ownership. The masked fields follow the
[vendor register sequence](https://github.com/MiCode/MTK_kernel_device_modules/blob/3c4ccd07d5624879555ec710c11bb8818e5cb5c6/drivers/gpu/drm/mediatek/mediatek_v2/mtk_mipi_tx.c).
Functional recovery after physical display-domain power loss still fails: DSI
commands time out and vblank does not advance.

0202–0204 give each MT6897 C-PHY link ownership of its DIS common 26M gate
across the link power session and add bounded read-only routing, gate and
merge-interrupt phase evidence. The vendor display controller claims both 26M
gates in its
[top-clock group](https://github.com/MiCode/MTK_kernel_device_modules/blob/3c4ccd07d5624879555ec710c11bb8818e5cb5c6/arch/arm64/boot/dts/mediatek/mt6897.dts);
the gate's exact DSI role remains a hypothesis. Functional resume after
physical display power loss remains unverified.

0205 clears the MT6897 DIS/OVL merge-interrupt routing on MMSYS runtime
resume. The vendor display driver writes INTMERGE +0x008 to zero on every
top-clock power-on; the 26M trial measured 1 after a physical domain power
loss and the pending DSI read IRQ never reached the handler. The existing
read-only phase diagnostics still read the same register.

0206 aligns MT6897 DSI command completion with the vendor: CMD_DONE is not
enabled and, after starting a command, the engine is polled until DSI_BUSY
clears. Reads keep the LPRX wait and video keeps VM_DONE; other SoCs retain the
IRQ wait. Bounded first-8 command/IRQ traces and an extended timeout dump are
read-only and reset per power-on.

0207 replaces the per-command success-path dev_info trace with a 16-entry
in-memory ring per DSI instance, so command pacing is unchanged. A poll or IRQ
timeout dumps the failing message, the ring oldest-to-newest and the engine/PHY
registers once per power-on; a post-route clock-rate line is also recorded once.
All reads are read-only.

0208 sets cmdq_long_packet_ctl for MT6897 so CMDQ_SIZE_SEL is written on every
command, matching the vendor. Boot-time firmware set the bit, but a physical
domain reset clears it. A confirming trial still saw the same post-long-packet
stall with the bit set, so this alignment alone does not recover resume.

0209 selects the MT6897 MM reset source before the power-on DSI engine reset.
The vendor C-PHY path sets DSI_DEBUG_SEL bit10 MM_RST_SEL; mainline wrote the
same bit only in the later TX-buffer setup, after mtk_dsi_reset_engine(). Boot
state is firmware-initialized, while after a domain reset the first command
reads empty CMDQ SRAM and the long-packet sequence stalls. The read-only
first-command, timeout and ring dumps now include DSI_DEBUG_SEL.

0210 clears the two MT6897 command-queue words at power-on after the engine
reset and replaces the per-byte read-modify-write path for the MT6897 v1
layout with software-built, zero-padded full-word writes. This addresses the
uninitialized CMDQ state after a domain reset and the partially written
padding word of a long packet; CMDQ_SIZE and SIZE_SEL programming and other
SoCs are unchanged. The timeout ring also records the CMDQ+4 word.

0211 adds read-only diagnostics to the MT6897 HWV root vote and off path. A
failed vote records the step (done wait, set/clr write, AP set/clear wait,
done-state wait), return code, the six HWV registers and the root/fault/
children state; HWV root power-off logs its pre-vote and post-vote state once.
Vote behavior, timeouts, writes and the quarantine policy are unchanged.

0212 is a diagnostic revert of 0210 for a resume hard hang. The display-off
path completed and logged the HWV vote state, but the following resume hung
with no kernel or userspace output. 0210 is the remaining new variable since
the candidates that produced explicit DSI command timeouts. The revert
restores the previous per-byte CMDQ programming and removes the power-on
queue clear and CMDQ+4 ring readback; all other clock, ownership,
polled-completion, ring, CMDQ_SIZE_SEL, MM_RST_SEL and HWV changes remain.
This is diagnostic pending the hang result.

With 0210 removed, the resume returns the explicit DSI poll timeout and the
system stays alive; 0210 therefore caused the hard hang.

0213 re-applies only zeroing the two MT6897 CMDQ words after the engine reset,
keeping the bytewise read-modify-write path and the ring without CMDQ+4.
This separates initialization from the remaining 0210 changes as a bundle;
composition, padding and header/payload ordering were not isolated causes
of the earlier hard hang.

0214 adds a read-only MT6897 CMDQ write trace. Each command-queue data,
config, size and SIZE_SEL write is recorded in a 64-entry in-memory ring with
its command sequence, message type and length, target offset, mask, value and
write kind; the command ring again records CMDQ word1. The existing
once-per-power-on timeout dump prints the write ring oldest-to-newest and the
command ring including word1. Writes, masks, ordering and timing are
unchanged. This distinguishes an issued-and-lost config write from one that
was never issued after a long packet.

0223 handles MT6897 Type-C sink IRQs when HPD remains high. It reads service
and trained-lane status, rejects unsupported automated tests explicitly, and
leaves other service bits pending. Healthy links remain untouched. A degraded
active link gets one retrain at its current rate/lane count; failure keeps the
stream muted and reports the unusable link to DRM. An inactive failed plug can
retry from its capabilities. Training, stream transitions, AUX power, sleep and
diagnostics are serialized; repeated recovery failures require a fresh
attachment or an explicit idle retrain. The exact OEM references are in the
patch's `Link:` trailers.

0224 gives MT6897 its own command-register map without the MT8186 shadow-control
access. Its polled reader owns read-ready acknowledgement; the IRQ acknowledges
only enabled non-read status and never waits on BUSY or RACKs a reply. Bounded
transaction errors stop the command trigger and block pair commands/video until
a fresh power-on, while retaining the original failure snapshot. Legacy paths
and payload/configuration/size RMW order are retained. Source references are in
the patch's `Link:` trailers.

0225 composes MT6897 command words from message bytes without using command
SRAM readbacks as inputs. Payload words precede the header, followed by the
existing size/SIZE_SEL/start sequence; partial payload words are zero-padded.
An explicit capability keeps other layouts on their existing RMW path. Invalid
buffers or lengths exceeding the six-bit queue count are rejected before
hardware changes. Direct-write trace records mark the old value unavailable;
size/control RMW records retain their observed old value. The bounded
completion, read acknowledgement and first-error behavior from 0224 remain.

0226 restores the OEM C-PHY command-mode initialization on each real MT6897
power-on. Optional register metadata identifies CMD_TYPE1_HS; only the
CMD_CPHY_6BYTE_EN bit is cleared, preserving reserved bits and existing
packing/completion/clock/reset behavior. Nested owners, D-PHY and other
layouts remain untouched. The existing bounded engine diagnostic includes
the mapped field for C-PHY.

0227 invalidates the DSC configured state when stopping either the primary core
or its resolved twin. After display-domain power loss, restart uses the initial
bypass path until the late DSC setup restores geometry/PPS, instead of enabling
an unconfigured encoder. The portable DSC sequence regression covers single and
dual cores, initial/configured operation and register loss across stop/restart.

0228 restores the complete MT6897 MMSYS C-PHY LSB routing word to the stock
zero value after display-domain power loss, rather than preserving fields
outside bits19:0. The masked MSB update and MSB-before-LSB sequence are retained.
The production-function regression covers both controllers, context loss,
validation-only/unsupported providers and reserved MSB fields.


0229 orders C-PHY analog-core startup before SDM/PLL power and analog shutdown
following PLL disable/isolation/power-off. The existing register values and
minimum core delay are preserved; the atomic PLL enable uses a bounded delay.
Signal callbacks retain lane forcing/PHY selection, and external PLL owners
retain the analog core until the last clock release. D-PHY MMIO/delay behavior
is unchanged. Production callback tests cover ordering, real rate boundaries,
repeated epochs, errors and nested/external owners.


0230 restores MT6897 direct-link OVL fetch controls before enabling each engine,
including dual-pipe twins. Startup preserves unrelated bits while enabling
BURST16 and output clamp, initializes complete request words for the two physical
layers, and restores low/high buffer thresholds. Other OVL variants retain their
existing startup path. Production-function tests cover register loss, both pipes,
masked and full-word ownership, enable ordering and unchanged legacy traces.


0231 separates the MT6897 DSC VERSION field at 0x200 from shadow control at 0x228.
Startup restores VERSION with the vendor mask while preserving other fields;
the existing FORCE_COMMIT/BYPASS control and sequence remain unchanged. Other
DSC variants retain the combined-register path. Production core/wrapper tests
cover versions, register seeds, enabled/disabled setup, twins and repeated epochs,
with identical legacy MMIO traces.


0232 prepares CCIF IRQ/poll/SRAM/status and in-flight TX work before platform
power-off, preserving AP resources when stop fails. Platform runtime-PM errors
and incomplete logical suspension propagate into a terminal FSM failure;
GET_MD_STATE reports pending STOP completion and latched errno. Reset and
clock-off remain in successful GATED completion. This does not implement full
DMA/transport teardown or retire module unload/manual-unbind restrictions.


0233 imports the MediaTek unused-domain consumer; 0234 integrates it with managed
runtime PM and describes the T880 PCIe PHY0 as its sole consumer. The existing
MAC0 parent follows normal genpd parent/child ordering. The driver is optional
and enabled only for T880; other unused domains and clock policy are unchanged.


0235 wires the UART0/1 bus inputs to their existing PERAO gates while retaining
26 MHz baud references. 0236 adds the C/N/S IMP I2C gate providers and connects
the I2C0/5/6 main and DMA clocks to their real gates, with the other group IDs
retained. 0237 separates the display PWM source and peripheral-gate inputs as
in the stock wiring. Consumer drivers own preparation and transfer/PM lifetime;
remaining global clock retention and DRAM policy are unchanged.


0238 describes MT6897 LVTS without an AP gate clock while preserving firmware
configuration and protection. 0239 adds the MT6897 SPMI 2.0 no-AP-clock variant
without changing other controllers' clock or IRQ behavior. 0240 gives the MT6897
revision-one UFS PHY its own compatible and no legacy MT8183 power/clock
operations. The host attachment and reference-clock protocol remain in place.
The corresponding DT inputs and bindings now describe these variant contracts;
other variants retain their required clocks and existing operations.

0241 adds a referenced snapshot of runtime PM suppliers. 0242 gives an active
MT6897 CRTC ordered references to its MMSYS controllers and the DRM device's
MMSYS parent. The driver drains component, mutex and supplier references after
checked stop before releasing those controllers in reverse order. Other variants
retain their existing links. 0243 rejects a genpd resume for quarantined
MT6897 roots even if a failed power-off left the domain logically on. 0244 tests
reference ownership, teardown order and fault admission.
