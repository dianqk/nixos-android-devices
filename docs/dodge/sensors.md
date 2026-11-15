# Dodge sensors

[中文](sensors.zh.md)

`hardware.dodge.sensors.enable` defaults to true for installed systems and false
for RAM recovery. It starts the SSC sensor listener through the secure ADSP
FastRPC device and exposes sensors through IIO Sensor Proxy. Accelerometer
samples are available; physical orientation remains unverified. Desktop shells
configure their own rotation policy.

The Dodge [firmware package](firmware.md) includes selected OEM registry defaults
and DSP shims in its single output; `sensors` aliases that output. A custom
`hardware.dodge.firmwareSource` must include `etc/sensors`, `dsp` and `seed/registry`.

Writable registry state lives in `/var/lib/ssc-sensors`, configurable through
`androidDevices.sensors.stateDirectory`. Defaults seed an absent directory;
existing calibration is retained. Handset-specific OEM calibration should be
provisioned privately before first start when available, retaining the
`registry/registry` group layout, `registry/parsed_file_list.csv` and
`registry/sns_reg_version`. Keep it outside firmware archives and Nix store inputs.

Inspect startup and request a short accelerometer stream:

```sh
systemctl status android-ssc-sensors.service iio-sensor-proxy.service
journalctl -b -u android-ssc-sensors.service -u iio-sensor-proxy.service
ssccli --sensor accelerometer --timeout 3
monitor-sensor --accel
```

Stop `monitor-sensor` with Ctrl+C to release its sensor claim. The supplied sensor
mount matrix is identity after SSC device-axis normalization; do not apply the
OEM BMI26x axis mapping a second time.
