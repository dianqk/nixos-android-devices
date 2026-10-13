# Aurora connectivity preparation

[Device guide](README.md) · [ADSP firmware](firmware.md) · [中文](connectivity.zh.md)

| Function | Status |
| --- | --- |
| USB2 ACM/NCM | Works in recovery and the installed system |
| USB3 ACM/NCM (device mode) | Works at 5 Gbit/s in the installed system |
| ADSP battery reporting, Type-C device/sink | Works |
| USB host mode, data-role swap | Not supported yet |
| DisplayPort | Basic picture output works; DP audio, additional modes, sustained operation and coexistence with USB3 are not verified |
| Wi-Fi | 2.4/5 GHz scanning, 5 GHz association and bidirectional transfers work |
| Bluetooth | BR/EDR and LE pairing, encrypted L2CAP data and GATT reads work; audio profiles, HID/PAN and Wi-Fi coexistence are not verified |
| Cellular modem | Experimental; see [Cellular modem](#cellular-modem-experimental) |

All results assume the required OEM base, OS1.0.3.0.UNACNXM (Android 14).

## ADSP and Type-C

The `devices.aurora.firmware` artifact contains the OEM split ADSP images and
service descriptors. All 61 files are checked against their SHA-256 manifest;
a host MDT check verifies that required load segments exist at their declared
sizes and fit the Aurora reserved regions. The board enables ADSP and includes
both main and DTB firmware in initrd for the built-in PAS driver.

The connector graph uses OTG with a peripheral default. Fixed peripheral
mode does not register a DWC3 role switch, so UCSI would exhaust its deferred
probe retries. Device/sink role, ACM/NCM and battery reads work together;
USB host mode is not supported yet. Battery reporting translates Aurora's OEM
property IDs and current sign. The firmware's constant `power_now` value is
unavailable rather than presented as measured power. A reported `Charging`
status can coexist with net battery discharge under a limited USB input; check
`current_now`, `charge_counter`, temperature and the negotiated input limit.
Do not raise the input limit beyond the connected source's capability.

The mainline [SM8650 HDK description](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/arch/arm64/boot/dts/qcom/sm8650-hdk.dts?id=72d3fcf802c45d00b300f25b848a93c3a2bd7c7e)
is the closest Type-C graph reference. OEM Aurora data identifies WCD9395 at
I2C address 0x0e, reset GPIO152 and L15B 1.8 V. I2C3 is under QUPv3 ID0 and
uses GPI DMA1. The graph needs GLINK HS/SS/SBU endpoints, controller role switch,
combo PHY orientation and the DP controller. The QRD's additional NB7VPQ904,
Sheng's PS5169 and Asphalt's FSA4480 are different board wiring.

The combo PHY supplies are `vdda-phy` = L3G (0.88–0.912 V) and
`vdda-pll` = L3I (1.2 V). The connector has separate HS, SS and SBU endpoints;
DP0 is enabled. OEM Aurora's `usb3phy_portselect_default` identifies GPIO29 as
the cable direction signal. `orientation-gpios` connects it to UCSI so the
combo PHY selects the correct lanes; without it a reversed cable keeps the
PHY's default orientation and USB falls back to 480 Mbit/s.
The WCD9395 switch driver is built into the kernel because the shared recovery
initrd intentionally contains no kernel modules.

### USB3 operation

USB3 device mode (ACM/NCM) runs at 5 Gbit/s on the installed system. To check
the link, the host's `lsusb -t` must report `cdc_ncm`/`cdc_acm` at `5000M` and
the phone's UDC must report `super-speed`; configuring a SuperSpeed maximum alone
does not establish the link. Hubs, host peripherals and DP coexistence are not
verified.

If the kernel reports a UCSI PPM-reset timeout, keep the log; do not suppress
the error. A working USB2 link does not show that Type-C role management
initialized.

### USB roles

The board uses `dr_mode = "otg"`, a peripheral default, a DWC3 role switch and
a dual-role Type-C connector. UCSI, the combo PHY, WCD9395 and xHCI host support
are retained, including in the recovery kernel. Read the negotiated state with:

```sh
cat /sys/class/typec/port0/data_role
cat /sys/class/typec/port0/power_role
cat /sys/class/typec/port0/orientation
cat /sys/class/usb_role/a600000.usb-role-switch/role
```

Writing `host` or `device` to the Type-C `data_role` attribute requests PD
negotiation with a partner that supports data-role exchange. Data-role swap is
not supported yet: the request times out on the phone (or the partner refuses
it) and the port stays device/sink. Use a local console or Wi-Fi for such tests
because NCM disappears in host mode. Do not force DWC3 to host against another
active host to bypass rejected negotiation. See [USB modes](../usb-signaller.md#modes-and-peripherals)
for the existing userspace interface and its power/role limitations.

### Touch responsiveness during USB load

The touch driver gives its dedicated threaded IRQ FIFO priority 51, one level
above the default USB IRQ priority 50, so saturated NCM transfers do not delay
touch reads long enough for the controller to drop frames. Touch accuracy during
sustained USB saturation has not been checked interactively.

This does not change the SPI worker or shared workqueue priority. Malformed,
overflowing or discontinuous frames still cause safe input release/recovery;
diagnostics report both sequence counters and the read interval.

### Interpreting remaining Type-C logs

A PMIC-GLINK `Failed to create device link (0x180)` message can describe a
parent proxy created before UCSI registers the connector device. On a working
system, the eventual Type-C port has supplier links to WCD9395, QMP and DWC3:

```sh
ls -l /sys/class/typec/port0/supplier:*
```

The warning remains unresolved; it does not by itself establish a missing
runtime dependency or the cause of a DP failure. Check port registration,
actual supplier links and negotiated state. Do not remove firmware-node links
or globally suppress driver-core warnings as a workaround.

A rejected data-role request sends SET_UOR to firmware, which reports BUSY
until the command times out; the UCSI error path then resets the PPM and
connector. This is not a slow role change, so increasing the role-change wait
does not help.

### DisplayPort

The native MSM DP controller, combo PHY and GLINK HPD bridge register a `DP-1`
connector; `disconnected` is expected without a display. WCD9395 provides the
SBU/AUX path; Sheng's PS5169 redriver must not be copied to Aurora.

Basic picture output on an external DP monitor works. DP audio, additional
modes, sustained operation and DP/USB3 coexistence are not verified. Host USB
devices on a dock depend on USB host mode, which is not supported yet. To
inspect a connected display:

```sh
niri msg outputs
for connector in /sys/class/drm/card*-DP-*; do
  cat "$connector/status"
  cat "$connector/modes"
done
journalctl -k -b | grep -Ei 'displayport|dp_aux|link.train|ucsi|glink|usbss'
```

A connector node or an EDID alone does not establish display output; check for
link training and a stable visible image.

## WLAN and Bluetooth

OEM logs identify WCN7850 PCI 17cb:1107 and successful loading of `kiwi/amss20.bin`
and `kiwi/bd_n1.elf`. The latter is board data from the ROM, not a per-device NV
readback. CNSS2 source confirms that `phy_ucode20.elf` is the M3 payload.
The [radio package](firmware.md#radio-firmware) keeps the
matched OEM quartet and packages BDF/REGDB under the measured PCI/QMI key.
PCIe Gen2×2, MHI, QMI, BDF/REGDB/M3 download and WMI service-ready have passed.
The Aurora-only QMI resource advertisement avoids a WMI-init RDDM with this
OEM firmware. It follows the
[Houji implementation](https://github.com/yoni13/armada-houji/blob/f5c689be6e603b259a5a85774d78c9cbd7cfefa4/ports/houji/patches/0013-ath12k-houji-stock-qmi-mlo.patch)
and vendor CNSS2 Kiwi topology (one chip, two links, 32 peers), without enabling
host MLO or changing RX rings. 5 GHz 80 MHz EHT/NSS2 connections and
bidirectional transfers work; throughput and Wi-Fi conformance are not measured.
After failed WMI initialization, avoid unloading/unbinding ath12k: its cleanup
path can dereference an unallocated radio. Preserve logs and restart
from an independent management path; this failure is distinct from the firmware
assertion. Bluetooth's GENI UART also requires the explicit `serial1` alias.

WLAN_EN/BT_EN are GPIO16/17; PCIe0 uses PERST94/CLKREQ95/WAKE96. The shared WCN
PMU rails follow S4I, L15B, L3C, S2C, S3C, S1C and S6C. Preserve the additional
L6K 1.8 V antenna-share supply when translating OEM wiring. The upstream
[SM8650 QRD description](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/arch/arm64/boot/dts/qcom/sm8650-qrd.dts?id=72d3fcf802c45d00b300f25b848a93c3a2bd7c7e)
is a topology reference, not a substitute for Aurora voltage constraints.
The reused QRD topology is BSD-3-Clause, Copyright (c) 2023, Linaro Limited.

Bluetooth uses UART14 at 0x898000. Hamilton firmware/NVM files exist in BTFM,
and OEM logs identify ROM2.0, board ID0, falling back to `hmtnv20.b2e`.
DT explicitly selects that scoped NVM and patch filename. L6K is the PMR735D
antenna-share rail; it is held on at the OEM1.8V while a shared consumer lifetime
is pending. PCIe uses the shared upstream variable-IOMMU-cell SID parser fix.
Do not reuse another device's MAC address or its suspend/ath12k workarounds.
PCIe SID mapping, QMI/firmware startup, association, reconnect, pairing/audio and
Wi-Fi/BT coexistence are separate validation stages.

### WCN7850 regulatory range

Aurora uses the shared [single-pdev regulatory correction](../../pkgs/linux-kernel/patches/ath12k-single-pdev-reg.patch)
already carried for Sheng. A combined 5/6 GHz radio must retain its permitted
5 GHz range when the selected country has no 6 GHz rules. The patch also uses
nl80211 band indices for per-band capability lookup. It does not enable channels
forbidden by the firmware regulatory data or fix cross-pdev shared-state races.

### Bluetooth status and pairing

BR/EDR pairing initiated from either side (numeric comparison), encrypted
L2CAP data in both directions (security level 4, AES-CCM) and LE connections
in both central and peripheral roles with GATT service discovery and reads
work. Independent LE-only pairing, GATT notifications and bulk writes, audio
profiles, HID/PAN/OBEX, range, suspend/resume and sustained Wi-Fi coexistence
are not verified.

Enable power and pairability before requesting pairing and check both
numeric-comparison prompts. A discoverable or pairable window can expire; verify
its current state before diagnosing an authentication rejection as a firmware
failure. For an established BlueZ GATT connection, use its GATT D-Bus client
rather than opening a second raw ATT client on the same link.

### Per-device Bluetooth identity

Provide the handset's own Android Bluetooth address as `local-bd-address` on
`&uart14`'s `bluetooth` child, encoded as six little-endian octets. Nixpkgs device
tree overlay `filter` is a literal substring: use `qcom/sm8650-xiaomi-aurora.dtb`,
without a wildcard. Verify the address in the final built DTB, then with
`bluetoothctl show` after reboot. The generic factory NVM does not supply your
handset's identity; missing configuration leaves HCI unconfigured even after a
successful firmware download. Keep individual addresses and calibration outside
this public package; its firmware override supports a validated private NVM.

## Cellular modem (experimental)

The board DT enables the MPSS remoteproc, IPA v5.5 and the static rmtfs shared
memory. The stock Android 14 modem carve-outs match `sm8650.dtsi`. On hardware,
MPSS boots, the QRTR service set matches Android, ModemManager detects the SIM
and registers on LTE/5G NR, IPv4 and IPv6 mobile data work, and SMS can be sent
and received. This needs the license services below, including
`license.qwesd`: without them the modem stops after its first (~3 min) or
periodic (~15 min) Smart Transmit license check. Voice calls are out of scope.
The kernel carries [QRTR HELLO and announcement fixes](../../pkgs/linux-kernel/patches/qrtr-hello)
so that the modem finds rmtfs and TFTP during startup.

Enable it on the installed system (not RAM recovery) with the Android 14 base.
The shared options are described in [modem and QTEE services](../modem.md).
`hardware.aurora.modem` supplies Aurora's remoteproc, NV partitions, firmware
and license services to the shared `androidDevices.modem` module, which holds
the generic settings:

```nix
hardware.aurora.modem.enable = true;
androidDevices.modem = {
  startAtBoot = true; # false: start modem-mpss.service manually
  allowNvWrites = false; # default: modem NV writes stay in RAM
};
```

SMS needs no extra module: ModemManager sends and receives it (`mmcli
--messaging-create-sms`); a messaging or dialer application is a desktop
choice.

| Component | Behavior |
| --- | --- |
| Firmware | The firmware package's separate `modem` output: modem, modem DTB and IPA split MDTs plus the modem's read-only TFTP tree. It is installed only in the root file system, never in recovery. |
| `modem-tqftpserv.service` | Serves `/readonly/firmware/image/` from the directory containing `modem.mdt`; writable requests go to `/var/lib/tqftpserv`. |
| `modem-rmtfs.service` | `rmtfs -P -v [-r]`: serves `modemst1`, `modemst2`, `fsg` and `fsc` by partition label. It does not start or stop MPSS. |
| `modem-mpss.service` | Waits up to `timeSyncTimeout` (120 s) for the system clock to be synchronised, then starts MPSS through remoteproc sysfs after the services above, and pulls in SIM provisioning and ModemManager. Stopping it, also at shutdown, writes `stop` only while MPSS is `running`; a crashed MPSS is left alone. |
| `modem-sim-provision.service` | (`simProvisioning`, default on) If the modem has not activated the primary GW provisioning session 10 s after a USIM is detected, activates it for the first USIM with `qmicli`; then ModemManager starts. |
| Smart Transmit license (`license.enable`, default on) | `qtee-supplicant.service` (minkipc) with write access limited to `/persist/data/pfm`, and `mink-modem-opener.service`, which publishes QRTR service 5013 for the modem's QTEE sessions. See [QTEE](#qtee-and-the-modem-license). |
| QRTR name service and PD mapper | In-kernel (`net/qrtr/ns.c`, `QCOM_PD_MAPPER`); no userspace daemons. |
| ModemManager | Enabled by default with libqmi over QRTR; started with MPSS. |
| IPA | The `ipa` module is blacklisted while modem support is disabled. The kernel carries the [IPA v5.5 configuration fix](../../pkgs/linux-kernel/patches/ipa-v5.5-config.patch) (upstream RFC): mainline's v5.5 endpoint table matched IPA 5.0/5.1, so modem downlink went to an endpoint the AP never drained. |

The SM8650 PAS driver keeps `auto_boot` disabled, so `modem-mpss.service`
starts MPSS once the QTEE supplicant, the modem opener, tqftpserv (the modem
reads its carrier configuration over TFTP) and rmtfs are up. rmtfs and
tqftpserv use `Restart=no`, and MPSS crash recovery is disabled unless
`androidDevices.modem.crashRecovery = true`, so a failing modem stays offline
instead of restarting in a loop.

Stopping and starting a healthy modem (`systemctl restart modem-mpss`) works:
the kernel carries a [PAS change](../../pkgs/linux-kernel/patches/pas-reassign-exclusive-regions.patch)
that gives the modem's exclusive DSM memory back to Linux after each stop and
assigns it again at the next start, as Android's driver does; before it, a
restart hard-reset the phone a few seconds after the modem came back. With
`crashRecovery = true` the kernel restarts the modem the same way after a
crash. Recovery from a real modem crash has not been observed yet.

With `allowNvWrites = false`, rmtfs (`-r`) reads each NV partition once and
keeps the modem's writes in RAM; they are lost when rmtfs stops. The service's
device cgroup also allows only read access to those partitions. Back up
`modemst1`, `modemst2`, `fsg` and `fsc` before allowing writes; never restore
another handset's NV data.

Check a test start with:

```sh
systemctl start modem-mpss.service
cat /sys/class/remoteproc/remoteproc*/name /sys/class/remoteproc/remoteproc*/state
journalctl -b -u modem-mpss -u modem-rmtfs -u modem-tqftpserv \
  -u qtee-supplicant -u mink-modem-opener
qrtr-lookup
mmcli -L
```

Known gaps: the stock kernel serves `qcom,memshare` requests from the modem;
mainline has no memshare service, and the effect on this modem is unknown. The
in-kernel PD mapper lists the stock modem `root_pd` (`gps/gps_service`) but not
its `oem_pd` (`oempd/srv1`) descriptor.

### QTEE and the modem license

The modem firmware checks a Smart Transmit license held by QTEE about 190 s after
it starts and stops with `Smart Transmit License Check Failure` when it cannot.
On Android, `ssgtzd` publishes QRTR service 5013 (`IMinkModemOpener`); the modem
opens `CTunnelInvokeMgr` (UID 124) in QTEE through it, and QTEE reads and updates
its license store in `/persist/data/pfm` through the supplicant's file system
listener.

`androidDevices.qtee` provides the open-source equivalent from
[minkipc](https://github.com/qualcomm/minkipc) on the upstream QCOMTEE driver:

- `supplicant`: `qtee_supplicant` with the file system, time, RPMB and TA
  autoload listeners. It is started by the services that need it.
- `persist`: mounts the persist partition at `/persist` (`nodev,nosuid,noexec,
  noatime`, no automatic fsck). The listener uses a requested path as it is when
  its directory exists. Aurora's QTEE asks for Android's
  `/mnt/vendor/persist/data/...`, so `persist.androidDataPath` binds
  `/persist/data` there; only that directory is bound, and the rest of
  `/mnt/vendor/persist` on the root file system (sensor registry data) stays
  visible. The supplicant may write only `persist.writablePaths` (Aurora:
  `/persist/data/pfm`, also through the bind), and the rest of the partition
  (calibration and other secure files) stays read-only to it.
- `modemOpener`: `mink-modem-opener`, minkipc's `MinkModemOpener` on the
  MinkSocket QRTR transport, without the Android-only parts of the HLOS Mink
  daemon. Like the vendor `ssgtzd`, it keeps each modem client's registered
  object (up to 10) until that client unregisters it. `clientUid` presents
  another UID (Android's `ssgtzd` runs as 1000) in the QTEE client credentials
  if QTEE refuses the default.

The modem keeps objects registered with the bridge and QTEE sessions open
while it runs. `nixos-rebuild switch` therefore does not restart the modem,
rmtfs, tqftpserv, supplicant or bridge units; reboot to apply their changes.
Do not restart `qtee-supplicant` or `mink-modem-opener` by hand while MPSS is
running; restarting the supplicant does not restart the bridge.

Set the clock before MPSS starts. The RTC is not usable, so time comes from
NTP; MPSS started with an unset clock stalls in initialisation (`DOG detects
stalled initialization` about 40 s later). Without a network the start proceeds
after the timeout, so set the clock first (`timedatectl set-time`) on an
offline phone.

For diagnosis, `modemOpener.trace` logs every call between the modem and QTEE
that passes through the bridge (method number, argument counts and sizes,
result, duration and object releases), `modemOpener.transportTrace` adds
MinkSocket's own trace, and `supplicant.debug` logs each file system and time
listener request with its resolved path:

```nix
androidDevices.qtee = {
  supplicant.debug = true;
  modemOpener.trace = true;
};
```

```sh
journalctl -b -u qtee-supplicant -u mink-modem-opener
```

- `qwesd` (opt-in, unfree): Qualcomm's prebuilt QWES daemon for Qualcomm
  Linux, fetched from Qualcomm at build time. It hosts the QMI QTEE license
  service. On Aurora the modem repeats its Smart Transmit check about 15 minutes
  after start and stops when the check fails; set
  `hardware.aurora.modem.license.qwesd = true` to run the daemon before MPSS.
  It may use only QRTR and Unix sockets (no IP networking), writes only
  `/var/cache/qwes`, and is never restarted on its own or by a switch. Allow
  the package explicitly:

  ```nix
  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) [ "qwesd" ];
  ```

  Its licence (`LICENSE.qcom-2`, installed with the package) permits
  redistribution of the binaries for Qualcomm chipsets only and forbids reverse
  engineering. Qualcomm may remove the download (meta-qcom no longer fetches it);
  with a saved `qwes_1.0_armv8a.tar.gz` (SHA256
  `7bb20daa916e4b13e54948ab90af92e9c2e6129cc22da1a23b924adb3f0610d4`), add it to
  the store first: `nix-store --add-fixed sha256 qwes_1.0_armv8a.tar.gz`.

The bridge reconstructs a few definitions that minkipc does not publish
(`IPrimordial`, the primordial and generic object handles, `Object_OP_unwrapFd`)
from the vendor `libminksocket_vendor.so`, and leaves out the close notifier and
shared-memory transfer, which QRTR cannot carry.

