# Aurora Android 14 sensor integration

[中文](sensors.zh.md)

The `sensors` output of the Aurora firmware package consumes pinned
[OEM data](https://github.com/dianqk/firmware-xiaomi-aurora/tree/60febc4751f8b939468bd57879d6831635d520d7/android14/sensors). It requires
China OS1.0.3.0.UNACNXM (runtime V816.0.3.0.UNACNXM), the same baseline as the
ADSP firmware. It contains 68 OEM configuration files and 10 Hexagon DSP files;
no handset-specific calibration or Android daemon is included.

`SOURCE.json` records the original ROM paths and SHA-256 values; `SHA256SUMS`
checks the unmodified files. Config selection follows `/odm/etc/sensors/config/json.lst`
for MTP / SoC 557. That OEM list also names three absent secondary SAR files
(`sm8650_sx937x_1.json`, `sx937x_1.json`, `sx937x_reg_1.json`); these are omitted.
The duplicate vendor/ODM CHRE configuration differs only in platform selectors;
its selected sensor values match, and the ODM copy is retained.

The common registry generator uses the `file-group` layout: filenames include
the originating JSON filename, `parsed_file_list.csv` indexes those records,
and `config/json.lst` lists the selected configuration files. Aurora firmware
opens the latter through `/odm/etc/sensors`; omitting this path can assert in
`sns_registry_sensor.c` and crash the ADSP. The module supplies explicit bind
paths rather than creating global Android filesystem links.

LSM6DSO acceleration/gyro use the OEM orientation (+Y, +X, -Z) inside SSC.
The shared libssc/SensorProxy integration consumes the resulting Android device
coordinates; no additional Sheng mounting matrix is applied. Factory bias is
per-device: retain it privately in the writable Linux registry, never distribute
one handset's calibration as a board default. Existing Linux state is not reseeded
on upgrades; normalization preserves JSON values and the firmware's `DIR` marker.

The `sensors` output is separate from firmware `out`; RAM recovery does not
start the listener or include these sensor data files.
