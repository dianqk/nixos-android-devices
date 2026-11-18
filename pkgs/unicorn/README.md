# Unicorn firmware inputs

`devices.unicorn.firmware` supplies the six GPU files, complete split ADSP and
SLPI images, the original matching OEM WLAN AMSS/M3/BDF/regulatory quartet,
WCN6855 Bluetooth firmware and Linux's signed regulatory database.
`hardware.unicorn.firmwarePackage` can replace the package. The device module
installs it in the running system and includes GPU/PAS files in the initrd.

OEM files come from [dwuggh/firmware-xiaomi-unicorn](https://github.com/dwuggh/firmware-xiaomi-unicorn/tree/1dd4c4d1eb9d1c00a63795fd7d897ec2a59a0b3b),
commit `1dd4c4d1eb9d1c00a63795fd7d897ec2a59a0b3b`. The corresponding
[`snapshot-20261113` release](https://github.com/dwuggh/firmware-xiaomi-unicorn/releases/tag/snapshot-20261113)
is downloaded as `.tar.zst` using the URL and SHA256 pinned in
[firmware-source.nix](firmware-source.nix), following the shared firmware archive
workflow. Builds fetch it automatically and verify its top-level `SHA256SUMS`.
OEM payloads are not stored in this repository.

[The input manifest](manifest.json) records the 61 original OEM files, lengths,
SHA256 hashes and source locations. DSP/WLAN entries also record partition byte
extents. The snapshot was verified against installed firmware on 2026-11-13;
this date does not identify an official ROM build. The package compares the
release's input manifest with this local manifest before installing files.

Extraction, Linux layout conversion and release tools live in the firmware
repository. The package is marked unfree. Private identity and calibration data
are not included. `hardware.unicorn.firmwarePackage` can select another package;
package-scope overrides can replace `devices.unicorn.firmware-source` with a
compatible runtime tree.

WLAN uses unchanged `amss20.bin` bytes installed as `amss.bin`, paired with the
same OEM `m3.bin`. The ath11k API2 `board-2.bin` preserves `bd_l2sgf.elf` in its
BOARD record and `regdb_xiaomi.bin` in its REGDB record. Its full PCI/QMI key is
listed in the manifest. Selection follows Unicorn L2S/project8, chip bit0x10,
and board255 in [MiCode's driver source](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/fa4513e61931e11a59e3f177ae590d4e090d7229).
Board255 can also mean a missing optional QMI TLV; confirm the reported key in
the running kernel. Linux's `regulatory.db` is separate from the OEM WLAN REGDB.

Bluetooth files and notices come from `linux-firmware.src` in the project's
locked Nixpkgs; signed `regulatory.db`/`regulatory.db.p7s` come from that same
Nixpkgs' `wireless-regdb`. Bluetooth uses `wcnhpbtfw21.tlv` and
`wcnhpnv21g.bin`, which that source's `WHENCE` identifies as WCN685x UART
firmware. The build checks the patch TLV length and its product/ROM fields
against the handset's measured `0x13`/`0x0201`, and records the selection in
`installed-files.json`. Its `hpbtfw21.tlv` and `hpnv21g.bin` have different bytes and are
listed for QCA2066; they are not aliases for the installed WCN685x files.
The kernel's WCN6855 setup also tries the old names after a transfer error.
An error for `hpbtfw21.tlv` can therefore follow an earlier timeout while
transferring the available `wcnhpbtfw21.tlv`. Check the first transfer result
before treating the fallback filename as a missing package input.

OEM radio firmware may leave addresses unset, so
controller discovery alone does not establish RF operation. Supply identities
at runtime if needed, outside firmware packages and the Nix store.

Build the firmware package:

```sh
nix build .#devices.unicorn.firmware
```
