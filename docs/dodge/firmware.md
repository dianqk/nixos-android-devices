# Dodge firmware

[中文](firmware.zh.md)

The exported `nixosModules.dodge` module defaults to the `dodge-firmware` package.
It fetches `dodge-firmware-LineageOS-24.0-5dd12b17e7-20261115.tar.zst` from the repository's
[`firmware` release](https://github.com/dianqk/nixos-android-devices/releases/tag/firmware).
Allow the unfree `dodge-firmware` and `dodge-firmware-zstd` packages in your Nixpkgs configuration.

The source is a OnePlus 13 PJZ110 running
`LineageOS 24.0-20261103-NIGHTLY-dodge`, with vendor/ODM incremental build
`5dd12b17e7` (Android 17, `CP2A.260605.016`). The asset names this observed
custom vendor build; its underlying stock ColorOS base is unverified.

The archive contains the Linux payload tree with a top-level `SHA256SUMS`:

- `lib/firmware`: GPU, Wi-Fi, Bluetooth, ADSP, CDSP, modem, SoCCP, video, audio topology and amplifier tables.
  The CDSP remoteproc files were added on 2026-11-15 from the handset's read-only
  `modem_a` image; the `dsp_a` userspace shell tree is not part of this archive.
- `share/alsa/ucm2`: audio profiles.
- `etc/sensors`, `dsp`, `seed/registry`: SSC runtime data and registry defaults.

This is a prepared runtime payload, rather than an OEM extraction tree. It does
not contain per-handset persist/calibration data. The package validates the archive
checksums and applies the maintained device UCM profiles. Recovery omits ADSP and
video images. Linux's generic `wireless-regdb` remains a separate upstream package;
the ROM's Wi-Fi `regdb.bin` is included in `dodge-firmware`.

To supply another matching payload, set `hardware.dodge.firmwareSource` to a
directory with this layout. Older custom extraction trees using `gpu`, `wlan`,
`audio` and `sensors/config` must first be mapped to the Linux payload layout.
`hardware.dodge.firmwarePackage` accepts a replacement package; its `audio`,
`modem` and `sensors` attributes must expose the corresponding data. The default
package aliases all three to its single output.

## Adding firmware artifacts

Add new files to the full payload tree, then rebuild the repository's one
per-device archive instead of publishing loose files or pinning individual
firmware files. Use a deterministic archive (sorted `tar` with mtime/uid/gid
zeroed) and single-thread `zstd -19`; regenerate the top-level `SHA256SUMS`,
update the provenance `README`, and update both the URL and SRI hash in
`pkgs/dodge/firmware-source.nix`. Verify one clean extraction with
`sha256sum -c SHA256SUMS` and confirm that all previously shipped files are
byte-identical before publishing the replacement archive.
