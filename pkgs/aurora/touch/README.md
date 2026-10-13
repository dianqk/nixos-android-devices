# Aurora touch runtime

The exported Aurora module enables this service for an installed Android 14
configuration. Recovery does not include the processor or Android library.
To disable it, set `hardware.aurora.touch.enable = false`.
Build independently with `nix build .#devices.aurora.touch`.

The S3910P controller sends sensor frames over SPI. The kernel exposes those
frames through `/dev/aurora-touch-raw`; this single-threaded adapter executes
only the core calculation path of the OEM library, then creates
`Xiaomi 14 Ultra Touchscreen` through uinput. The input axes are 0..143999 and
0..319999, matching Android's 100-fold coordinate precision. Desktop libinput
normalizes these coordinates; they are not a screen resolution.

This is an experimental compatibility adapter, not a reimplementation of the
proprietary algorithm or a complete Android runtime. It requires ARM64 with
4 KiB pages and the exact China OS1.0.3.0.UNACNXM Android 14 controller firmware
(packrat 4337601, config N1CTE022). It does not flash the controller.
The OEM inputs are fetched from the pinned
[firmware repository](https://github.com/dianqk/firmware-xiaomi-aurora/tree/60febc4751f8b939468bd57879d6831635d520d7/android14/touch)
and installed unchanged:

| File | Android path | SHA-256 |
| --- | --- | --- |
| libtouchreport.so | /odm/lib64/libtouchreport.so | 25354d7b53285a086e94d32543848f22e472cae958c65bdad0f5545e0a37947f |
| aurora_syna_thp_config.ini | /odm/firmware/aurora_syna_thp_config.ini | 125577bcf8e8816e7f425264a222a4488a5497ff7f1bd7fe200169908cfe20fd |

Both hashes are checked before execution. The OEM files are proprietary, retain
all rights of their owners, and are not covered by the source-code license.
No handset calibration or identity data is bundled. See [source provenance](ORIGINS.md).

## Diagnostics

```sh
systemctl status aurora-touch
journalctl -b -u aurora-touch
sudo evtest /dev/input/aurora-touch
sudo libinput debug-events --device /dev/input/aurora-touch
sudo libinput record /dev/input/aurora-touch > touch.yml
```

Install the upstream `evtest` and `libinput` tools in the consuming configuration.
The input symlink exists only while the service is running. Validate movement,
multiple contacts, individual releases, edges, rotation, screen-off wake, and
absence of spontaneous contacts. Successful idle replay alone does not validate
physical touch accuracy, gestures, palm rejection, suspend or stylus support.

The transport allows one reader. Overflow, malformed frames, missing sequences
and a two-second stall terminate the decoder session and destroy its virtual
input device, releasing contacts. systemd restarts the processor with fresh
state. Gap diagnostics include both the transport and controller counters plus
the kernel capture interval: a continuous transport counter with a controller
jump means the loss precedes the userspace queue. The dedicated touch IRQ runs
at FIFO51, just above Linux's default IRQ FIFO50, to prevent a saturated USB3
NCM interrupt thread from delaying controller reads. The SPI pump and decoder
retain ordinary scheduling. This does not disable frame integrity checks.
SPI errors reset/re-identify the controller with bounded backoff; the
shared GENI controller is never unbound. The first 100 frames initialize the
OEM algorithm before contact reporting. Suspend invalidates the stream session;
full system suspend remains unverified.

For bounded raw capture, stop the service before running the following command
and start it again afterwards. Captures can contain touch activity; share them
only deliberately. The output file must not already exist. Replay never creates
uinput devices.

```sh
p=$(readlink -f /run/current-system/sw/bin/aurora-touch)
d=${p%/bin/aurora-touch}/share/aurora-touch
sudo systemctl stop aurora-touch
sudo "$p" "$d/libtouchreport.so" "$d/aurora_syna_thp_config.ini" \
  --live /dev/aurora-touch-raw 10 /tmp/touch.htrf
sudo systemctl start aurora-touch
"$p" "$d/libtouchreport.so" "$d/aurora_syna_thp_config.ini" /tmp/touch.htrf
```

HTRF records contain a 24-byte header (magic, LE32 sequence, LE64 monotonic
nanoseconds, LE16 payload length, six reserved zeros) and a 1722-byte payload.
Capture is capped at 4096 records; processing continues for the requested time.
The raw-frame checksum, geometry and extension bounds are validated before
calling the library. Only explicitly modeled libc/math imports are allowed.
Fixed function/data addresses are specific to this pinned binary; replacing a
hash alone is not a library upgrade.
