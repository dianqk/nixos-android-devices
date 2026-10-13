# SSC sensors and screen rotation

[中文](sensors.zh.md)

Enable the board's sensor support in your installed configuration:

```nix
hardware.asphalt.sensors.enable = true;
# Or: hardware.polaris.sensors.enable = true;
```

This page covers Asphalt and Polaris. Aurora's sensors are described in
[Aurora sensors](aurora/sensors.md); Sheng's optional `hardware.sheng.sensors`
services are listed in [Sheng hardware](sheng/hardware.md).

Polaris and Asphalt desktop examples enable sensor support for diagnostics, but
keep Niri's default screen orientation without an automatic rotation client.
Recovery leaves sensor services disabled. With `lib.mkSystem`, pass
`nixpkgsConfig.allowUnfree = true`, or a predicate permitting `asphalt-sensors`
and `polaris-sensors` (including their `-zstd` firmware variants): these packages contain proprietary OEM data. Ordinary
NixOS configurations use `nixpkgs.config.allowUnfreePredicate` instead.

Build the selected board's data independently, for example:

```sh
nix build .#devices.asphalt.sensors --out-link result-sensors
```

For Polaris, replace `asphalt` with `polaris`.
The kernel/DTS changes also require updating the
installed system and generation boot files through the normal device procedure.
Enabling the userspace option on an older kernel is insufficient.

These boards use SLPI SSC through QRTR/QMI, native Qualcomm `sdsprpcd sensorspd`,
libssc and iio-sensor-proxy. A kernel IIO accelerometer node is not required.
The proxy exposes acceleration/orientation, ambient light, proximity and compass
when firmware advertises those sensors. Libssc's CLI also supports magnetometer
and gyroscope readings. No automatic brightness or proximity display policy is set.

## Check startup

```sh
systemctl status android-ssc-sensors iio-sensor-proxy
journalctl -b -u android-ssc-sensors -u iio-sensor-proxy
ssccli --sensor accelerometer --timeout 10
ssccli --sensor light --timeout 10
ssccli --sensor proximity --timeout 10
ssccli --sensor compass --timeout 10
ssccli --sensor gyroscope --timeout 10
monitor-sensor --accel
```

The proxy waits for actual accelerometer samples with bounded retries. On failure,
check `/dev/fastrpc-sdsp`, SLPI firmware loading, QRTR discovery and listener logs.
Polaris uses the existing userspace PD mapper; Asphalt uses SM8450's in-kernel
mapper. Do not add a competing locator daemon. The optional FastRPC PDR
subscription acknowledges sensor-PD notifications; it does not implement full
recovery from a static-PD crash.

The listener maps `/vendor/etc/sensors`, `/vendor/dsp`, `/persist/sensors` and
`/mnt/vendor/persist/sensors` inside its own service namespace. Writable state
lives in `/var/lib/ssc-sensors`, including the registry parent, version stamp and
temporary/cache files. Defaults are copied only on first start; later generations
retain calibration. Updated defaults do not automatically replace existing state.
Preserve the state before intentionally reseeding it.

## Desktop clients

The executable is exported as `packages.<buildSystem>.sensor-rotate`. Run it
inside the compositor session, with the compositor IPC tools in `PATH`:

```sh
mobile-sensor-rotate --compositor sway --output DSI-1
mobile-sensor-rotate --compositor niri --output DSI-1
mobile-sensor-rotate --compositor hyprland --output DSI-1 \
  --touch-device 'nt36523n-capacitive-touchscreen'
```

For Polaris on Hyprland, `--touch-device 'synaptics-*'` selects the internal RMI
touchscreen when exactly one device matches. Inspect `hyprctl devices -j` when
another Synaptics touch device is connected: ambiguity prevents rotation. The
client maps and rotates that touchscreen while preserving monitor geometry.
Sway/Niri users should bind the touchscreen to `DSI-1` in compositor configuration.
Run one rotation consumer per output.

Initial and changed orientations, undefined readings, duplicate events and angle
direction are handled. `--offset 90` adds a counterclockwise screen offset.
SSC acceleration events already use the Android device coordinate frame. The
sensor module patches libssc to preserve those samples: SSC attribute 20 is
placement metadata, not a transform to apply again. The proxy's SSC backend
adapts the device axes to its orientation classifier; Z remains outward for
face-up/face-down detection. The identity default for
`androidDevices.sensors.mountMatrix` represents only a residual screen mounting
correction. Do not repeat the DSP chip-axis mapping or compensate for incorrect
panel installation metadata with a rotation-client offset.

Asphalt's native display mode is portrait, 1600×2560, with panel rotation 0.
Use the compositor's default output transform and the rotation client's default
orientation mapping. Niri combines the requested rotation with DRM panel
installation metadata; it should continue doing so for correctly described
hardware. A preferred desktop orientation belongs in session policy, not DTS.

## Validation limits

Registry generation, userspace packaging, source/configuration checks, driver and
DTB compilation have been exercised. Remaining hardware coverage includes
long-running samples, four screen directions, touch alignment, cold boots and
suspend/resume. Android property bridge directives are omitted because
the native listener cannot load the Bionic-only library, and the captured Asphalt
registry lacked those optional property files. Whether either firmware requests
the bridge despite those directives being absent remains a runtime question.
On Polaris, the packaged firmware and defaults have produced accelerometer
samples through the native listener. Four screen directions, cold boots and
suspend/resume still require device validation.

See [libssc documentation](https://libssc.dylanvanassche.be/docs/) and data
provenance for [Asphalt](../pkgs/asphalt/sensors/README.md) and
[Polaris](../pkgs/polaris/sensors/README.md).

### Updating SSC packages

Update the FastRPC package and the sensor data together, then reboot so SLPI
initializes fresh. An older FastRPC listener or older sensor data combined with
current packages can corrupt listener requests or crash the firmware registry
parser. The listener uses coherent FastRPC allocations and rejects truncated or
oversized wire frames.

The sensor service reorders existing registry JSON before starting, preserving
stored values and calibration. Do not delete the state directory to apply this
fix. Firmware expects `owner` before group entries and `type`, `ver`, `data` in
that order even though JSON itself does not require object key ordering.
The service exposes the same read-only configuration at `/vendor/etc/sensors`
and `/system/vendor/etc/sensors`: Polaris firmware reads the latter directory
even when the existing registry files are present. Without it, SSC can answer
QMI requests while exposing neither the registry nor accelerometer sensor.
Polaris also needs two FastRPC sessions for the listener's allocator and
transport connections, with exported SDSP buffers allocated from its shared memory pool.
Update the kernel and sensor module together; then reboot to initialize SLPI
with the corrected configuration.
Older libssc versions could incorrectly interpret placement as a mounting matrix
and report an all-zero fallback while retaining fractional off-diagonal entries.
Update the sensor module's libssc/proxy pair together; do not counteract that bug
with calibration changes. Validate four physical screen orientations and touch
after updating.
