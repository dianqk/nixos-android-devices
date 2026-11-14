# SM8475 kernel support

[中文](README.zh.md)

Unicorn imports [`series.nix`](series.nix) for TLMM, the SoC device
tree, UBWC, PLL handoff, UFS clock-parent/retention fixes and GCC CX power
management. `config.nix` selects shared SM8450-family drivers; board queues
select the remaining patches.

The shared SoC supplies the UFS PHY's `UFS_PHY_GDSC` dependency. TLMM marks
EGPIO as a GPIO function; its explicit interrupt offsets match the core's
fallback. Asphalt retains its separate upstream queue under `asphalt/`; this
queue is imported only by Unicorn. Asphalt selects its UFS follow-up
patches explicitly. The
Lucid OLE PLL patch preserves bootloader-enabled PLLs; GCC binding, runtime PM
and the CX domain reference are applied together.

## UFS clocks and power

UFS AXI and ICE select GPLL3 at 850 MHz. SM8450/SM8475 controllers power down
the device and PHY during suspend because PHY state cannot survive CX collapse.
SM8475's three roots use `clk_rcg2_shared_ops` to force-enable live updates,
cache disabled configurations and park before parent gating. Hibern8 exit
errors propagate to the core, and testbus writes preserve the live divider.

Unicorn selects `ufs-performance-opps.patch` and `ufs-opp-init-order.patch`
through this queue. These add ICE scaling and coordinated CX/MX requests.
Asphalt extends upstream's existing OPPs with
`asphalt/patches/local/0036-sm8475-ufs-ice-mx-opps.patch` and selects the same
initialization-order fix explicitly. Its SM8475 turbo compatible, full UFS PHY
sequence and media integration are retained. The follow-up removes the host's
permanent NOM vote so the coordinated OPP request can use LOW_SVS at 75 MHz.
This changes Asphalt clock/power management; it does not add a higher maximum
frequency or establish a throughput improvement.
The OPP implementation provides two states:

| AXI / UniPro / ICE | Required CX / MX level |
| --- | --- |
| 75 MHz | 64 (`LOW_SVS`) |
| 850 MHz | 416 (`TURBO_L1`) |

The three clocks occupy indices 0, 3 and 8 of the nine-clock OPP array. Requests
propagate through `UFS_PHY_GDSC` to GCC's CX and MX parents; runtime PM alone
only controls domain power. ICE starts at 75 MHz/LOW_SVS before its driver
enables the clock. The initialization fix acquires all clock handles before
applying the initial OPP and tracks successful rate changes. Performance
requests rise before clocks and fall after them. Each board keeps its timing
compatible; SM8450 retains its single CX parent and controller behavior.

The levels come from the pinned OEM [GCC driver](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/blob/fa4513e61931e11a59e3f177ae590d4e090d7229/drivers/clk/qcom/gcc-waipio.c)
and [level mapping](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/blob/fa4513e61931e11a59e3f177ae590d4e090d7229/include/dt-bindings/regulator/qcom,rpmh-regulator-levels.h).
The [clock supplies](https://github.com/MiCode/kernel_devicetree/blob/c79d5587e59766264e81ca8a82e1525009699356/qcom/waipio-clock.dtsi)
and [regulator definitions](https://github.com/MiCode/kernel_devicetree/blob/c79d5587e59766264e81ca8a82e1525009699356/qcom/cape-regulators.dtsi)
map `vdd_mxa` to `mx.lvl`, not the separate active-only supply. Unicorn's observed
CMD DB maps the low request to CX 64 / MX 192; other consumers can raise the vote.

Validate both frequency directions, idle/Hibern8 transitions and UIC/SCSI errors
from RAM recovery with the root filesystem unmounted or read-only. Software
votes and clock readback do not measure physical voltage. Patch replay and
builds do not establish UFS stability or successful suspend/resume on either board.

## Board queues

USB repeaters, UFS timing, display PHYs and peripheral wiring remain board-specific.
Unicorn selects A730 and low-gear UFS fixes, and uses separate CSI2 PHY devices;
Asphalt uses integrated CSIPHY resources. Keep each camera driver with its device tree.
After shared changes, check both queues; see [Unicorn](unicorn/PATCHES.md) and
[Asphalt](asphalt/PATCHES.md) for configuration and build requirements.
