# TB320FC SLPI sensor data

OEM firmware and generic vendor defaults from Lenovo ZUI 17.0.339, TB320FC
(SM8475). SLPI uses `slpi.mdt` and the actual ELF segments; this installation
has no `slpi.b22`. Hexagon libraries and `fastrpc_shell_2` are in `dsp/`.
Android ARM64 daemons/property libraries and per-device calibration are excluded.
These OEM assets have no accompanying open-source license.

The subset matches `hw_platform=MTP`, `soc_id=531`: 50 JSON files. Line endings
and trailing whitespace are normalized; original SHA256 values are recorded in
`SOURCE-SHA256SUMS`. Binaries are unchanged. The shared builder merges identical
defaults and emits 329 groups with a version-7 stamp. BMI3x0 orientation is
(-x,+y,-z). Defaults also cover MMC56x3x magnetometer, STK3A5x light/proximity
and SSC algorithms. No per-device calibration is exported.

See [configuration and validation limits](../../../docs/sensors.md).
