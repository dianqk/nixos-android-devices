# Unicorn cameras

[中文](camera.zh.md) · [Device guide](README.md)

`camera-sensors.patch` and `camera-bringup.patch` implement native V4L2
RAW10 capture for the three D-PHY modules and the IMX707 C-PHY main module. It is built by the Unicorn kernel queue; the example system
includes the project's patched libcamera and `v4l-utils`.

| Module | Linux I2C address | Receiver | Implemented mode |
| --- | --- | --- | --- |
| S5KJN1 ultra-wide | CCI0/master0, `0x3d` | CSIPHY0 | 4080 × 3072, RAW10 |
| S5KJN1 telephoto | CCI1/master0, `0x2d` | CSIPHY1 | 4080 × 3072, RAW10 |
| OV32B40 front | CCI1/master0, `0x10` | CSIPHY3 | 3264 × 2448, RAW10 |
| IMX707 main | CCI0/master1, `0x10` | CSIPHY2, three-trio C-PHY | 4096 × 3072, RAW10 (source implementation) |

Both JN1 modules have captured RAW10 frames with repeated start/stop cycles.
Front/main identification still NACKs, including with the CCI parent held active.
Bayer order, exposure and software ISP remain unverified. The
driver exposes one binned mode per sensor, exposure, analogue gain and vertical
blanking, and powers the sensor down when capture stops. Autofocus, OIS, flash,
HDR, full-resolution modes and calibrated ISP tuning are not implemented.
In particular, the telephoto lens has no focus actuator control yet.

The original controller-only configuration explains `/dev/video0` through
`/dev/video19` without a camera in `cam --list`. These nodes describe CAMSS
capture engines, not successfully probed sensors. The new graph connects each
sensor through its PHY to CAMSS. `CONFIG_DMABUF_HEAPS=y` and
`CONFIG_DMABUF_HEAPS_SYSTEM=y` provide the software ISP's buffer allocator.
The kernel builder verifies requested overrides against the final `.config`.

The S5KJN1 driver has a separate `s5kjn1-unicorn` model so its 19.2 MHz mode
cannot be confused with the upstream 24 MHz sensor configuration. Its gain
unit is 1/32; `ov32b40-unicorn` uses 1/256. The libcamera helpers match these
units; `imx707-unicorn` uses `1024 / (1024 - code)` with codes 0–1008. Image processing uses libcamera's simple/software ISP pipeline; no
Android camera HAL is used.

## Build and use

```sh
nix build .#devices.unicorn.kernel
nix build .#devices.unicorn.system
```

After deploying the resulting system and booting its kernel, on the phone:

```sh
cam --list
cam --camera 1 --info --list-properties
cam --camera 1 --capture=5 --file='frame-#.bin'
```

Camera numbers depend on probe order. The files are raw stream buffers, not
JPEGs. Recovery does not load the full camera stack.

If enumeration is empty, collect `media-ctl -p -d /dev/media0` and kernel
messages for `unicorn-sensors`, `CCI`, `csiphy` and `pm8008`. A failed chip-ID
read, deferred supplier or missing media link must be resolved before capture.

## Provenance and remaining main-camera work

Routing and power supplies follow the Unicorn DT and Cape CSI PHY DT at
[LineageOS devicetrees revision
2e649a7f3e762903eedad43d8256b91e28b512d8](https://github.com/LineageOS/android_kernel_xiaomi_sm8450-devicetrees/tree/2e649a7f3e762903eedad43d8256b91e28b512d8/qcom/camera).
All modules use a 19.2 MHz MCLK. Sensor addresses below are Linux 7-bit
addresses, converted from the OEM's 8-bit addresses.

Register data comes from this device's stock vendor sensor-module files:

| File | SHA-256 |
| --- | --- |
| `com.qti.sensormodule.unicorn_sunny_s5kjn1_ultra.bin` | `4166818ae2ba1af41d2c8e46f1e02461b48fa2056fce877d1ad7259f3b1c5209` |
| `com.qti.sensormodule.unicorn_ofilm_ov32b40_front.bin` | `69044ab202ea50b2e9fe41eb79ad600b4240725ed047e29a9f540ed6f85de9b2` |

Only init settings and resolution index 1 are included. S5KJN1 uses 40 init
writes and 277 mode writes; the telephoto mode matches the ultra-wide mode
byte for byte. OV32B40 uses 2450 init writes and 202 mode writes. Register
write order, widths and delays are retained, with a 5 ms wait after OV software
reset. JN1 orientation is explicitly zero for its declared native GRBG format;
the OEM's combined stream/180-degree-flip write is not used. No EEPROM, OTP,
per-device calibration or Android executable is included in the patch.

The generic container layout was cross-checked with
[qti_parameter_bin.py, revision 2669026](https://github.com/geocausa/SP11X1ECamera/blob/266902649612533d97c5d0bef07d4e3aa3c745a3/tools/qti_parameter_bin.py).
The native sensor API follows Linux 7.3-rc6's `s5kjn1.c`; OV register controls
and HTS units were compared with the
[Rockchip OV32B40 driver, revision 77168c8](https://github.com/rockchip-linux/kernel/blob/77168c8d5ab82399f65a80e9f807b50ba37cf483/drivers/media/i2c/ov32b40.c).
Mode timing is not a measurement: front-camera exposure timing and reported
frame duration in particular need hardware confirmation.

`camera-bringup.patch` carries C-PHY bus type through CAMSS into the generic
PHY and SM8450's **CSID 680** receiver. The three physical trios map to common
lane-enable bits 1, 3 and 5 (`0x2a`). The board uses the distinct
`xiaomi,unicorn-csi2-phy` compatible. It retains the existing D-PHY clock
calculation and uses the OEM `v2.1.3-xiaomi-l2s` tables for the main camera,
including all 26 ordered CDR ceilings. It does not use X1E80100's v2.1.2
register values for this endpoint.

C-PHY framework work is adapted from [George Neacsu's v3 series](https://lists.openwall.net/linux-kernel/2026/10/16/2063);
CAMSS integration follows the [PHY API C-PHY configuration work](https://lists.openwall.net/linux-kernel/2026/10/17/241),
adapted to the pinned kernel's interfaces. Hardware settings come from
[camera-kernel revision 3b30ba7](https://github.com/LineageOS/android_kernel_xiaomi_sm8450-modules/blob/3b30ba7df6608c97c0ba2d55d679a6b5987c4c66/qcom/opensource/camera-kernel/drivers/cam_sensor_module/cam_csiphy/include/cam_csiphy_2_1_3_hwreg.h),
SHA-256 `dfa067cd42e5f8a37383289965201a4cac1fa209a7e0305af477239cde2b78de`.

IMX707 register source:

| File | SHA-256 |
| --- | --- |
| `com.qti.sensormodule.unicorn_semco_imx707_wide.bin` | `4ab05c4d4d24856ed48e7f61845d1d025ac2ba3d8b5b7400ae2eb1346dee40fc` |

`tools/unicorn-camera-tables.py` validates that exact source file, section
bounds, unique symbol IDs, referenced payload types and scalar write
operations. It preserves register order, data widths and per-write delays.
This module uses 268-byte resolution records; the older SP11 decoder's
252-byte layout is unsuitable. Sensor-version **0** init table (symbol 3357,
1044 writes) and resolution index **1** (symbol 316, 81 writes) are selected.
The second init table is an alternative version, never appended to the first.
To reproduce the register header from an owner's stock file:

```sh
python3 tools/unicorn-camera-tables.py /path/to/com.qti.sensormodule.unicorn_semco_imx707_wide.bin \
  --header /tmp/unicorn-imx707-regs.h --manifest /tmp/imx707-provenance.json
python3 tests/unicorn-camera-tables.py
```

The mode has HTS 13536, VTS 6450 and a VT pixel clock of 2,621,440,000 Hz
(about 30.025 fps). Its C-PHY symbol rate is **1,715,200,000 symbols/s per
trio**; V4L2 link frequency is **857,600,000 Hz**, half that symbol rate.
The exact coded bit rate per trio is symbol rate × 16/7. The OEM CDR table
uses rounded 2.28 bits/symbol ceilings; its first matching entry is
4,560,000,000 bits/s. These are separate from the VT pixel clock and the
D-PHY DDR clock. The board-specific receiver currently accepts only this
mode's symbol rate, with the stock settle **register count 30**. The legacy field is named
`settleTimeNs`, but [CamX serializes it multiplied by 200000000](https://github.com/bjzhou/CamxChi/blob/main/camx/src/core/camximagesensordata.cpp),
and the KMD divides by that same factor; treating 30 as nanoseconds and
converting again would be incorrect. Other modes need timing validation.

IMX707 power follows the sensor driver's power-up table (symbol 12): AFVDD
(PM8008 L7, 3.104 V, 10 ms), AVDD (GPIO70, 1.86 V), DVDD (GPIO2,
1.25 V, parent S12), IOVDD (PM8008 L5, 1.8 V), AUXVDD (PM8008 L6,
3.104 V, 1 ms), MCLK2 (19.2 MHz, 1 ms), reset release (GPIO126, 2 ms).
The shorter table at symbol 8613 belongs to EEPROM access, not a sensor
power override. Both extra supplies are retained even though actuator/OIS
control is deferred. The sensor's native RGGB order is
requested by clearing the stock 180-degree flip; Bayer order still requires
scene verification. Automatic frame-length extension is disabled so the
VBLANK control sets frame length. The stock auxiliary PDAF packets are
**filtered**: RDI matches VC0/DT0x2b RAW10, excluding VC0/DT0x30; no PDAF
stream is exposed to applications.

The queue also includes the [SM8475 camera-collapse fixes](https://lore.landau.one/lkml/20261020142157.1749-1-sushmit718@gmail.com/T/):
`camcc-retain-flops.patch` programs the GDSC retention and wait values, and
`camcc-park-clocks.patch` parks disabled camera RCGs on XO. These address
the first candidate's observed power-domain restart failure; repeated
capture still needs verification on the rebuilt kernel.

## Front-camera diagnosis and independent enumeration

The pre-change phone logs showed repeated OV32B40 ID-read `-ENXIO` (I²C
NACK), including reprobes. Its cause has **not** been established as a
hardware failure. No chip-ID bypass or fake successful probe is provided.
The driver now uses the OEM word read at `0x300b`, expecting `0x3242`,
instead of the previous three-byte read starting at `0x300a`. MCLK5 and MCLK2
use the OEM 4 mA pin drive instead of the SoC default 2 mA. AVDD/IOVDD/
DVDD/MCLK/reset use the OEM 1/1/1/1/5 ms power-up delays. The sensor is
identified again on every capture start.

CCI errors identify the master, address, I²C message number, read-data or
write/address phase, length and errno. Enable dynamic debug for the sensor
to record each power-up stage and the regulator framework's voltage values:

```sh
sudo sh -c 'echo "file unicorn-sensors.c +p" > /sys/kernel/debug/dynamic_debug/control'
sudo journalctl -k -b --no-pager
```

Reported voltages and GPIO levels reflect software state; they do not prove
physical voltage, reset edges or MCLK waveforms at the module connector.
An address-phase NACK after correct software sequencing still needs electrical
measurement before declaring a hardware defect.

CAMSS creates sensor media links and registers subdevice nodes during each
successful bind, without waiting for every sensor. The complete callback
only finishes node registration. Failure rollback removes only the new
sensor's links/nodes; unbind clears its PHY association. This also fixes the
previous situation where a front-camera NACK hid already-bound JN1 modules.
The DMA heap retains group `video`/mode `0660` and gains `uaccess` for the
active local desktop session.

## Acceptance status

The source changes remain experimental until the following phone tests pass:

- Five boot probes per sensor, with successful ID reads on the candidate kernel.
- Twenty capture start/stop cycles per sensor, with repeat ID reads and power release.
- At least 300 consecutive frames each; verify dimensions, monotonic timestamps,
  actual scene/Bayer order, exposure response, and no CSI errors.
- Software ISP preview as the active desktop user, including DMA heap ACL access.
- A failed front/main probe leaves other ready cameras usable; regress ultra/tele.

Use a revertible boot entry when testing a candidate kernel.
