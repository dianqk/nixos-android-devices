# Xiaomi Redmi Note 12 Turbo / POCO F5 (marble)

[中文](README.zh.md) · [All devices](../README.md) · [Support status](status.md) · [Kernel patches](../../pkgs/linux-kernel/sm7475/marble/PATCHES.md)

Status: **experimental.** U-Boot on `boot_b` starts on
hardware with the USB ACM console, screen, buttons and read-only UFS access.
The RAM recovery boots on hardware through `fastboot boot` (Linux 7.3, USB
console and networking, UFS, touch and keys). On a phone with the 36 0d 0b
panel a test build lit the screen from boot and the installed system starts
its graphical session on it; the current kernel is not yet verified (see [Display panels](#display-panels)). The phone (model 23049RAD8C) uses the Snapdragon 7+ Gen 2 (SM7475), which shares
the SM8450/SM8475 clock, pin and UFS blocks. Android stays on slot A; NixOS
uses slot B only.

## Outputs

| Output | Content |
| --- | --- |
| `devices.marble.u-boot` | Header v4 boot image for `boot_b`: U-Boot v2026.10 as a gzip kernel with the board DTB appended, no ramdisk. |
| `devices.marble.kernel` | Linux 7.3 with the [Marble patch queue](../../pkgs/linux-kernel/sm7475/marble/PATCHES.md) and `qcom/sm8475-xiaomi-marble.dtb`. |
| `devices.marble.recovery` | RAM recovery: the same U-Boot image with a FIT (kernel, initrd, DTB) as its ramdisk. |
| `devices.marble.firmware` | Stock OEM firmware (unfree), outputs `out`, `dsp`, `modem`, `audio` and `sensors`; see [firmware](firmware.md). |
| `devices.marble.system` | Example console system with USB networking (not tested; see [Install NixOS](#install-nixos-experimental)). |

```sh
nix build .#devices.marble.u-boot --out-link result-u-boot
nix build .#devices.marble.recovery --out-link result-recovery
```

Use the exported module `nixosModules.marble`; options of this board are under
`hardware.marble.*`.

## U-Boot

Each boot starts the USB ACM console (`/dev/ttyACM*` on the host) and the
screen console, then scans UFS. Without a `linux-boot` ESP U-Boot opens its
menu: list the partition tables of all UFS LUNs (read-only), USB serial
console, shell, reset and power off. Volume keys move, Power selects; hold
Volume Down while U-Boot starts to open the menu directly. UMS and Fastboot
are not offered because the ACM console holds the only USB gadget slot.

After the UFS scan U-Boot counts down 3 s before booting. Any key on the ACM
console or a volume key stops it at the U-Boot shell (`run menucmd` opens the
menu); an idle shell boots again after 60 s.

With an ESP, U-Boot loads `/EFI/BOOT/BOOTAA64.EFI` from `linux-boot` and then
marks slot B successful: it sets only `boot_b`'s successful bit in both GPT
copies of its LUN, after checking all UFS GPTs and the slot flags, so ABL
stops counting down B's retries. It writes nothing else (no BCB, PON state or
environment); a failed check is logged and the boot continues. See
[boot actions](../boot-actions.md#automatic-slot-b-confirmation).

Open the ACM console in raw mode without echo (for example
`picocom -b 115200 /dev/ttyACM0` or `screen /dev/ttyACM0`). A plain
`cat /dev/ttyACM0` leaves the terminal echoing the menu's escape sequences back
to U-Boot, where they act as key presses and can select a menu entry such as
Power off.

## RAM recovery

The recovery image is started by the stock bootloader (ABL) like U-Boot. ABL
loads a header v4 image together with `vendor_boot_b` and places the image's
ramdisk after the vendor ramdisk. U-Boot reads `vendor_boot_b`'s header (read
only), finds the FIT marked `android-devices,payload = "ram-recovery"` after
the vendor ramdisk, copies it into its fastboot buffer and boots it. A boot
image without such a FIT (the installed `boot_b`) boots normally. The recovery
uses USB serial `RECOVERY_MARBLE` with USB networking at `172.16.48.1`.

Start it from the stock bootloader's fastboot mode with slot B active and a
valid `dtbo_b` (see below); nothing is written to the phone:

```sh
fastboot set_active b
fastboot boot result-recovery
ssh root@172.16.48.1
```

The recovery's SSH server accepts root without a password. If the client
offers several keys first it may reach the server's authentication limit; add
`-o PubkeyAuthentication=no` in that case.

## Display panels

Marble phones are fitted with one of two M16T panels, "36 02 0a" or
"36 0d 0b", each with its own Linux driver. U-Boot reads the panel name that
ABL reports and selects the matching driver and vddd voltage in the device
tree it hands to Linux, so one build serves both. 36 0d 0b is verified on
hardware; 36 02 0a is not tested by this project. See
[display panels](display.md) for the panel table, the selection, how to check
which panel a phone has, and the display handover the kernel needs.

## Storage

NixOS uses the userdata allocation of LUN 0 (`userdata` is its last
partition): recovery's `prepare-install` keeps a chosen size for Android
userdata (64 or 128 GiB on the 256 GB model) and creates the FAT ESP
`linux-boot` (label `BOOT`) and the ext4 root `linux` (label `NIXOS`) from the
rest. The kept Android userdata is erased; Android on slot A needs a factory
data reset afterwards. Slot A, `super`, `misc`, `metadata`, `dtbo_*` and the
calibration partitions are preserved. See [recovery](../recovery.md).

## Install NixOS (experimental)

Not yet tried on hardware. The module installs the stock GPU, video, Wi-Fi,
Bluetooth, ADSP and SLPI firmware ([firmware](firmware.md), unfree: allow
`marble-firmware` and `marble-firmware-zstd`); the modem is optional
(`hardware.marble.modem.enable`, experimental, see [modem](../modem.md)), and
so is audio (`hardware.marble.audio.enable`, see [Audio](#audio)).
The installed system is reached over USB (serial `MARBLE`, ACM console and SSH
at `172.16.48.1`).

1. Build the recovery, the system and its closure information from the same
   locked configuration (`devices.marble.*` here, or your own configuration
   importing `nixosModules.marble`):

   ```sh
   nix build .#devices.marble.recovery --out-link result-recovery
   nix build .#devices.marble.system --out-link result-system
   nix build .#devices.marble.bootstrap-info --out-link result-bootstrap-info
   nix build .#devices.marble.u-boot --out-link result-u-boot
   ```

2. Start the RAM recovery (see [RAM recovery](#ram-recovery)) and split the
   storage once if `linux-boot` and `linux` do not exist yet (see
   [Storage](#storage); from the recovery screen, or):

   ```sh
   mobile-device recovery --target root@172.16.48.1 prepare-install --android-userdata 64G
   mobile-device recovery --target root@172.16.48.1 prepare-install --android-userdata 64G \
     --gpt-backup ./marble-gpt-original --execute
   ```

3. Check the backup GPT of the boot LUN. Stock ABL updates only the
   primary GPT when it switches slots (`fastboot set_active b`); the stale
   backup makes every recovery write operation and U-Boot's slot
   confirmation refuse. If the check reports a repair, review it and confirm
   (only the backup copy is written; see
   [recovery](../recovery.md#stale-backup-gpt-after-an-oem-slot-change)):

   ```sh
   ssh root@172.16.48.1 recovery repair-backup-gpt --check
   ssh root@172.16.48.1 recovery repair-backup-gpt --confirm
   ```

   Run the check again after any later `fastboot set_active`.

4. If the device lacks compatible U-Boot, flash it separately to `boot_b`
   from RAM recovery:

   ```sh
   mobile-device recovery --target root@172.16.48.1 install-image ./result-u-boot \
     --partition /dev/disk/by-partlabel/boot_b
   mobile-device recovery --target root@172.16.48.1 install-image ./result-u-boot \
     --partition /dev/disk/by-partlabel/boot_b --execute
   ```

5. Check, then install. This streams the closure into the empty `linux` and
   installs systemd-boot and the generation into `linux-boot`. Reboot explicitly
   after installation succeeds.

   ```sh
   mobile-device recovery --target root@172.16.48.1 install-initial \
     "$(readlink -f result-system)" --bootstrap-info ./result-bootstrap-info
   mobile-device recovery --target root@172.16.48.1 install-initial \
     "$(readlink -f result-system)" --bootstrap-info ./result-bootstrap-info --execute
   mobile-device recovery --target root@172.16.48.1 reboot system --execute
   ```

ABL then starts U-Boot from `boot_b`, which loads systemd-boot from
`linux-boot` and marks slot B successful, so ABL no longer falls back to
Android. Earlier generations stay selectable in the systemd-boot menu. The
menu offers no reboot to recovery or Android yet: to return to the recovery,
enter the stock fastboot mode (Volume Down while powering on) and
`fastboot boot result-recovery`; `fastboot set_active a` returns to Android.
See [first installation](../initial-install.md) for failure handling.

## Audio

Status: both speakers and the bottom microphone work on hardware (Linux
7.3): music plays cleanly from each speaker at the stock Android amplifier
level, and the microphone records. Voice calls, the earpiece as a call
output and wired headsets (headphones and headset microphone) are not
supported yet. `hardware.marble.audio.enable = true;` (off by default)
installs:

- the AW88263S speaker amplifier configuration
  `qcom/sm8475/xiaomi/marble/aw88261_acf.bin`, derived from the stock
  `aw882xx_acf.bin` of the firmware source (the `audio` output, see
  [firmware](firmware.md));
- the AudioReach topology `qcom/sm8450/SM8475-Xiaomi-Marble-tplg.bin`, built
  from [`pkgs/marble/audio`](../../pkgs/marble/audio): MultiMedia1 playback
  to both speakers on the tertiary TDM interface (96 kHz, 32-bit, four-slot
  frame; slots 0-2 driven as on stock Android), MultiMedia3 capture from
  the WCD9385 through `TX_CODEC_DMA_TX_3`;
- the ALSA UCM configuration (verb `HiFi`, devices `Speaker` and `Mic`) for
  PipeWire and WirePlumber, and `alsa-utils`.

The card is `SM8475-Xiaomi-Marble` (driver `sm8450`). Controls are named by
the physical position of the speaker, as in the stock pin names
(`aw882xx_reset_active_top`/`_bot`):

| Control prefix | Amplifier | TDM slot | Speaker |
| --- | --- | --- | --- |
| `Speaker Top` | AW88263S at I2C 0x34 | 0 (left) | top, at the earpiece end; gpio52 switches it to the earpiece |
| `Speaker Bottom` | AW88263S at I2C 0x35 | 1 (right) | bottom edge |

The UCM `Speaker` device plays to both. The UCM verb sets both
amplifiers to their `Music` profile at volume 349 of 360 (0.25 dB steps,
-2.75 dB, the profile's own value, which stock Android also keeps while
playing); there is no host speaker protection, so set a moderate level with
the PipeWire sink volume. The microphone is AMIC1 through ADC1 and TX macro
DEC0. Kernel details: [Speaker TDM on 7.3](../../pkgs/linux-kernel/sm7475/marble/PATCHES.md#speaker-tdm-on-73).

Check the card and controls without playing anything:

```sh
cat /proc/asound/cards
aplay -l; arecord -l
alsaucm -c SM8475-Xiaomi-Marble list _verbs
amixer -c SM8475-Xiaomi-Marble contents | grep -A2 -E "Speaker (Top|Bottom)"
```

## Sensors

Status: experimental; the accelerometer and screen rotation are verified on
hardware in all four orientations. `hardware.marble.sensors.enable` (off by default) wires the SLPI sensors
into the shared [SSC sensor support](../sensors.md): `sdsprpcd sensorspd` on
`/dev/fastrpc-sdsp`, libssc and iio-sensor-proxy. The firmware's `sensors`
output carries the SSC registry defaults, generated from the stock sensor
configuration in the firmware archive ([firmware](firmware.md)), and the
SLPI FastRPC libraries. The kernel loads the SLPI firmware and subscribes to
its `msm/slpi/sensor_pd` domain
([SLPI sensors](../../pkgs/linux-kernel/sm7475/marble/PATCHES.md#slpi-sensors)).

```nix
{
  hardware.marble.sensors.enable = true;
}
```

iio-sensor-proxy then reports the screen orientation from the BMI26x
accelerometer; a session rotates its output with any iio-sensor-proxy client
(for example iio-niri for niri on `DSI-1`). The accelerometer reports Android
device axes, so the default identity mount matrix applies (the shared SSC
backend already adapts them for iio-sensor-proxy); a different value is only
a residual correction and must be confirmed in all four orientations.

The registry is seeded once into `/var/lib/ssc-sensors` and kept across
updates; calibration that the SLPI writes stays there. Factory calibration
from Android's persist partition is not imported (orientation does not need
it). Other SSC sensors (ambient light and proximity of the TCS3701,
magnetometer, SAR) are in the registry but not set up or checked.

Check after boot:

```sh
systemctl status android-ssc-sensors iio-sensor-proxy
ssccli --sensor accelerometer --timeout 2
monitor-sensor --accel
```

## Suspend and wakeup

Status: experimental; `deep` suspend is verified on hardware with UFS
`spm_lvl` 3. The firmware offers `deep` (PSCI system suspend, the kernel's
default) and `s2idle`. `hardware.marble.suspend.memSleep` (default `null`,
the kernel's choice) adds `mem_sleep_default=` when set;
`hardware.marble.suspend.ufsSpmLevel` (default `null`) writes the UFS
host's `spm_lvl` at boot when set. `null` keeps the kernel's level 5 from
patch 0081 (as on Asphalt, where the UFS PHY does not keep its state across
a CX collapse). With the SM8475 UFS series (0082-0091) level 5 resumes from
`s2idle` on Marble; before it, the UFS controller could not be re-enabled
after a suspend at level 5. `s2idle` is selectable but not yet measured
on Marble. The PMK8350 RTC
alarm is enabled for RTC wake (the firmware owns the RTC time; Linux cannot
set it).

Verified with `deep` on battery: `pm_test` at every level; RTC wake and
power-key wake from real suspends of 20–35 s; after resume Wi-Fi, the
remoteprocs (modem, ADSP, SLPI), ModemManager, audio, display, touch, sensors
and UFS reads work.

SoC low-power state: on kernels before patches 0080/0081 and the camera
clock controller driver, the SoC never reached its sleep states during
suspend (`/sys/kernel/debug/qcom_stats` `aosd`, `cxsd` and `ddr` counts
stayed 0, about 137 mA average drain). The `sync_state()` of the RPMh power
domains, GCC, GPUCC and the interconnects stayed pending because the camera
clock controller, the GMU and the QCE node had no driver; until then the
RPMh power domains hold every rail at its highest level and the
interconnects keep their boot bandwidth. The kernel now builds the camera
clock controller driver, carries the shared GMU series and disables QCE, so
these complete. A first 74 s `deep` suspend with them still did not reach CX
or DDR sleep (`aosd`/`cxsd`/`ddr` counts 0; DDR stayed at its lowest
frequency); the remaining votes are not yet identified. The installed
system no longer passes `clk_ignore_unused` and `pd_ignore_unused`: unused
clocks and power domains are switched off at boot, and display, touch,
storage, USB, Wi-Fi, modem, sensors, audio devices, cameras and `s2idle`
keep working. `hardware.marble.ignoreUnusedClocksAndDomains = true` restores
them; RAM recovery keeps them. The installed system does not pass
`regulator_ignore_unused` either: every regulator in use has a consumer, and
storage stays error-free under write load. `hardware.marble.ignoreUnusedRegulators = true` restores
it; RAM recovery keeps it. A boot log line `sync_state() pending due to …` names a consumer
that still blocks it.

The device module declares wakeup sources for the shared
[wakeup policy](../configuration.md#suspend-wakeup-sources): `powerKey`,
`volumeKeys` (volume-up), `rtc` (alarm and alarmtimer), `battery` (battery
manager battery supply), `usbPower` (battery manager USB and wireless
supplies, UCSI), `adsp` (ADSP remoteproc: battery manager, Type-C and audio),
`modem` (MPSS: calls and SMS over QMI), `mobileData` (IPA), `sensors` (SLPI
remoteproc), `thermal` (TSENS) and `wifi` (WCN6855). Keep only
`powerKey`, `volumeKeys` and `rtc` for now; plugging in USB does not wake the
device yet:

- The remoteprocs (`adsp`, `modem`, `sensors`) wake the device: long deep
  suspends ended about every seven minutes without a Linux wake interrupt
  while the glink and AOSS message counters advanced (most likely the battery
  manager's periodic status from the ADSP). Without a policy that suspends
  again after such a dark wake, keeping them only shortens the suspend.
  Calls and SMS (`modem`) need that policy first. On the kernels without the
  `sync_state()` fixes above, a suspend with only `powerKey`, `volumeKeys`
  and `rtc` also ended after about 450 s without a wake interrupt.
- `wifi` is not a useful source: the WCN6855 is powered off during suspend
  and powered up again on resume.
- `mobileData`: with no SIM or data connection the IPA woke the device a few
  seconds into suspend without a wake interrupt.
- `battery` and `usbPower`: these battery manager and UCSI supplies receive
  the same periodic ADSP status over pmic_glink. With `battery` the device
  woke after about two minutes; with `usbPower` (and no other glink source)
  after about three, again without a wake interrupt.
- `thermal` is not needed for a suspended device.

With every driver default enabled the device wakes almost immediately. For
example:

```nix
{
  androidDevices.power.wakeup = {
    enable = true;
    keep = [ "powerKey" "volumeKeys" "rtc" ];
  };
}
```

Known issue: in two of eight resumes the WCN6855 firmware crashed shortly
after resume (PCIe correctable errors, then `firmware crashed:
MHI_CB_EE_RDDM`); ath11k restarted it and Wi-Fi reconnected within about
15 seconds. It occurred whether or not `wifi` was a wakeup source.

## Test and install

Check the image first (see the package README). Then, from the stock
bootloader's fastboot mode:

1. Optional, without writing: `fastboot boot result-u-boot`.
2. Install to slot B only and switch to it:

   ```sh
   fastboot flash boot_b result-u-boot
   fastboot set_active b
   fastboot reboot
   ```

Do not write `boot_a`, `super`, `userdata`, `persist`, `modem*` or `fsg`.
Until an installed system's EFI entry is loaded (which marks slot B
successful), ABL falls back to slot A after its retry count is used up;
`fastboot set_active a` returns to Android at any time, and
`fastboot set_active b` resets the count.

**Keep `dtbo_b` valid.** Unlike Asphalt and Aurora, where `dtbo_b` may be
erased, Marble's ABL refuses to boot slot B (normal boot and `fastboot boot`)
when `dtbo_b` is erased or invalid: it decrements the retry count and stays in
fastboot. Restore it from `dtbo_a` if it was erased. The overlay only changes
the DT ABL passes to U-Boot; Linux gets its DTB from U-Boot.

## Acknowledgements

This port builds on the work of iLtanaka (Tatsuki Tanaka):

- [u-boot-marble](https://github.com/iLtanaka/u-boot-marble): the U-Boot port
  whose commits make up this package's patch series
- [linux-marble](https://github.com/iLtanaka/linux-marble): the mainline Linux
  port whose commits make up the kernel patch queue
- [pmaports, branch `marble`](https://github.com/iLtanaka/pmaports/tree/marble):
  postmarketOS packaging, including the kernel command line used here
- [firmware-xiaomi-marble](https://github.com/iLtanaka/firmware-xiaomi-marble)
- [Wiki page](https://wiki.nura.eco/wiki/Xiaomi_POCO_F5_/_Redmi_Note_12_Turbo_(xiaomi-marble))

The SM8475 pin controller, device tree and the SM8475 UFS, cpufreq and
pd-mapper support are by Danila Tikhonov; the SM8450 display, RPMh and GPU
device-tree changes are by Jens Reidel, from the
[sm8450-mainline](https://github.com/sm8450-mainline) project.
