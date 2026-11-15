# Qualcomm modem and QTEE services

[中文](modem.zh.md) · [Module boundaries](modules.md)

Two shared modules run the Qualcomm modem (MPSS) on the mainline remoteproc
driver for the installed system. They are not used in RAM recovery.

- `androidDevices.modem`: rmtfs serving the modem's NV storage, tqftpserv, the
  unit that starts and stops MPSS, SIM provisioning and ModemManager over QRTR.
- `androidDevices.qtee`: QTEE userspace on the upstream QCOMTEE driver, for
  modems whose firmware checks licenses held by QTEE.

Device modules supply the remoteproc, NV storage and firmware; you normally
enable a device option rather than these modules directly:

| Device | Enable | Notes |
| --- | --- | --- |
| Aurora | `hardware.aurora.modem.enable = true;` | Experimental. Registration, mobile data and SMS; requires the Android 16 base OS3.0.308.0.WNACNXM and the license services. See [Aurora cellular modem](aurora/connectivity.md#cellular-modem-experimental). |
| Marble | `hardware.marble.modem.enable = true;` | Experimental, not yet verified on hardware. rmtfs on `modemst1`, `modemst2`, `fsg` and `fsc` (read-only by default), tqftpserv, the in-kernel pd-mapper and ModemManager; no QTEE license services. |
| Polaris | `hardware.polaris.radio.snapshotDirectory = "/path";` | Starts MPSS through `rmtfs -s` from a verified read-only calibration snapshot; no clock wait, SIM provisioning or ModemManager integration. See [Polaris](polaris/README.md). |

## `androidDevices.modem`

| Option | Default | Meaning |
| --- | --- | --- |
| `enable` | `false` | Enable the modem services. |
| `remoteproc` | `null` | Device name of the modem remoteproc (for example `4080000.remoteproc`); required for `remoteproc-unit`. |
| `startMethod` | `"remoteproc-unit"` | `remoteproc-unit`: `modem-mpss.service` writes `start`/`stop` through remoteproc sysfs. `rmtfs`: rmtfs starts MPSS itself and `modem-rmtfs.service` is the start unit. |
| `nvPartitions` | `[ ]` | GPT labels of the NV storage served by rmtfs. |
| `nvDirectory` | `null` | Serve NV storage from files in this directory instead (`rmtfs -o`). Set either this or `nvPartitions`. |
| `allowNvWrites` | `false` | Let rmtfs write NV data back. When false, modem writes stay in RAM and the service can only read the block devices. |
| `startAtBoot` | `false` | Start MPSS during boot; otherwise start `modem-mpss.service` manually. |
| `crashRecovery` | `false` | Let the kernel restart MPSS after a crash. |
| `timeSyncTimeout` | `120` | Seconds to wait for NTP synchronization, or for a clock restored by [`androidDevices.clock.rtcOffset`](configuration.md#system-clock-from-a-read-only-rtc) when enabled, before starting MPSS; `0` disables the wait. |
| `simProvisioning` | `true` | Activate the primary GW provisioning session for the first USIM if the modem has not. |
| `modemManager` | `true` | Enable ModemManager and start it with MPSS. The packaged daemon carries three local fixes: the netlink transaction use-after-free that crashed it on the first QMAP data connection, the multiplexed-bearer cleanup assert on IPA modems, and the `WDS Bind Subscription` needed before `Start Network` on SDM845-and-later firmware (otherwise every data call ends with `cm error: no-service`). |
| `ims.enable`, `ims.package` | `false`, `pkgs._81voltd` | Serve modem-requested IMS data connections through 81voltd and ModemManager. Does not change IMS registration settings. |
| `firmware` | `[ ]` | Modem firmware packages, installed in the root file system only. |
| `rmtfsPackage`, `tqftpservPackage` | packaged defaults | Replace rmtfs or tqftpserv. |
| `rmtfsVerbose`, `rmtfsMemoryDevice` | `true`, `/dev/qcom_rmtfs_mem1` | rmtfs logging and shared-memory device. |

The units are `modem-tqftpserv`, `modem-rmtfs`, `modem-mpss` (with
`remoteproc-unit`) and `modem-sim-provision` (with `simProvisioning`). rmtfs and tqftpserv do not restart on
their own, and `nixos-rebuild switch` does not restart the modem services;
reboot to apply their changes. A crashed MPSS is left alone rather than
stopped.

For modem firmware that requests an AP-provided IMS data service, set
`androidDevices.modem.ims.enable = true`. `modem-ims.service` starts with MPSS
after ModemManager and serves QRTR service 770. The modem requests the IMS APN
and IP family; ordinary data profiles remain separate. This supplies the IMS
data connection, while registration and SMS availability still depend on the
modem firmware and carrier.

Stopping 81voltd does not disconnect its existing ModemManager bearers. Before
manually restarting it, record its IMS bearer paths, stop `modem-ims`, then
explicitly disconnect and delete only those bearers with `mmcli`; retain normal
data bearers. Rebooting applies configuration changes with a fresh bearer set.

Back up the NV partitions before setting `allowNvWrites = true`, and never
restore another handset's NV data.

### SIM provisioning needs written NV

Activating the primary GW provisioning session writes to the modem's NV
(session index and card state). With read-only NV the firmware answers
`QMI error (3): Internal`, which reads like a power or SIM problem but is not:
the card stays readable (ICCID, applications) and its supply can be toggled
through `--uim-sim-power-on/off`. Pair `simProvisioning = true` with
`allowNvWrites = true` when the modem has no session of its own.

Cellular data also needs NetworkManager to own the connection: a bearer that
ModemManager starts directly comes up but passes no traffic, while an NM `gsm`
profile with the carrier APN configures the QMAP interface and routes.

## `androidDevices.qtee`

| Option | Meaning |
| --- | --- |
| `supplicant.enable`, `supplicant.package`, `supplicant.debug` | minkipc `qtee_supplicant` with the file system, time, RPMB and TA autoload listeners. Started by the services that need it. `debug` logs each listener request with its resolved path. |
| `persist.device`, `persist.mountPoint` | Mount the ext4 persist partition (default `/persist`; `nodev,nosuid,noexec,noatime`, no automatic fsck). |
| `persist.androidDataPath` | Also bind `<mountPoint>/data` at Android's path (for example `/mnt/vendor/persist/data`) for QTEE firmware that requests it. |
| `persist.writablePaths` | Directories under the persist mount the supplicant may write; the rest stays read-only to it. |
| `modemOpener.enable`, `modemOpener.package` | `mink-modem-opener`, publishing QRTR service 5013 (`IMinkModemOpener`) through which the modem opens QTEE services. Requires the supplicant. |
| `modemOpener.clientUid` | UID presented in the QTEE client credentials (Android's `ssgtzd` uses 1000). |
| `modemOpener.trace`, `modemOpener.transportTrace` | Log every call between the modem and QTEE, and MinkSocket's own transport trace. |
| `qwesd.enable`, `qwesd.package` | Qualcomm's prebuilt, unfree QWES daemon hosting the QMI QTEE license service. It may use only QRTR and Unix sockets. Allow the `qwesd` package explicitly. |

Enabled QTEE license services start before MPSS. Do not restart
`qtee-supplicant` or `mink-modem-opener` by hand while MPSS is running.

## Check a modem start

```sh
systemctl start modem-mpss.service
cat /sys/class/remoteproc/remoteproc*/name /sys/class/remoteproc/remoteproc*/state
journalctl -b -u modem-mpss -u modem-rmtfs -u modem-tqftpserv \
  -u qtee-supplicant -u mink-modem-opener
qrtr-lookup
mmcli -L
```

With `startMethod = "rmtfs"`, start `modem-rmtfs.service` instead.
