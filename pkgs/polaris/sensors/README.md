# Mi MIX 2S SLPI sensor data

Generic JSON comes from
[TheMuppets/proprietary_vendor_xiaomi_polaris](https://github.com/TheMuppets/proprietary_vendor_xiaomi_polaris/tree/9e9707959acceea4b990cba733d259aab64c183e/proprietary/vendor/etc/sensors),
commit `9e9707959acceea4b990cba733d259aab64c183e` (LineageOS 22.2).
The `POLARIS`/`321` selection has 33 files. Only line endings and trailing
whitespace are normalized; original hashes are in `SOURCE-SHA256SUMS`.
The builder emits 125 groups with a version-2 stamp and ICM206xx orientation
(-x,-y,+z). BH1745, AK991x, pressure/proximity defaults and algorithms are retained.
No per-phone calibration is included.

SLPI firmware and PD descriptors use the existing multimedia firmware source:
[MollySophia/firmware-xiaomi-polaris](https://github.com/MollySophia/firmware-xiaomi-polaris/tree/d88ffb2ee182d07567bf280fc4a8493f975ae977/lib/firmware/qcom/sdm845/polaris),
commit `d88ffb2ee182d07567bf280fc4a8493f975ae977`. These OEM assets have no
accompanying open-source license. Offline selection does not prove compatibility
with this firmware or physical screen coordinates on a particular phone.

See [configuration and validation limits](../../../docs/sensors.md).
