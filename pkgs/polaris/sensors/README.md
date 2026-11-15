# Mi MIX 2S SLPI sensor data

[中文](README.zh.md)

Generic JSON comes from
[TheMuppets/proprietary_vendor_xiaomi_polaris](https://github.com/TheMuppets/proprietary_vendor_xiaomi_polaris/tree/9e9707959acceea4b990cba733d259aab64c183e/proprietary/vendor/etc/sensors),
commit `9e9707959acceea4b990cba733d259aab64c183e` (LineageOS 22.2).
The `POLARIS`/`321` selection has 33 files. Only line endings and trailing
whitespace are normalized; original hashes are in `SOURCE-SHA256SUMS`.
The builder emits 125 groups with a version-2 stamp and ICM206xx orientation
(-x,-y,+z). BH1745, AK991x, pressure/proximity defaults and algorithms are retained.
No per-phone calibration is included.

SLPI firmware and PD descriptors come from the per-device `firmware` release
archive, assembled from MollySophia/firmware-xiaomi-polaris at `d88ffb2`. These OEM assets have no
accompanying open-source license. Offline selection does not prove compatibility
with this firmware or physical screen coordinates on a particular phone.

See [configuration and validation limits](../../../docs/sensors.md).
