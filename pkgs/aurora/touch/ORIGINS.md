# Touch source provenance

The SPI transport and native adapter derive from
[yoni13/armada-houji](https://github.com/yoni13/armada-houji/tree/5d6156dbb0ce23d0156040219be38bbc28aa15c8/ports/houji/touch),
pinned at `5d6156dbb0ce23d0156040219be38bbc28aa15c8`.
`stock-core.c` carries SPDX MIT; `sha256.c` is the public-domain
LibTomCrypt implementation from iw 6.17; the accompanying iw notice is in
[COPYING](COPYING). The kernel transport is GPL-2.0-only.
The OEM library and configuration are proprietary and retain their owners' rights.
Their unchanged payloads are maintained in
[firmware-xiaomi-aurora](https://github.com/dianqk/firmware-xiaomi-aurora/tree/60febc4751f8b939468bd57879d6831635d520d7/android14/touch),
separately from this adapter source.

Local changes: Aurora regulator wiring and geometry, Android 14 library/config
hashes, function addresses, three-argument decoded-frame allocation, 1722-byte
raw frame validation and checksum, output metadata offsets, and the temporal
update already performed inside Android 14's compute entry. Kernel input comes
only from the userspace processor; the transport checks the known controller
identity and geometry, enables raw reports, and quiesces recovery during removal.
See [the runtime interface](README.md).

The following original commit metadata is retained verbatim. The initial
commit introduced `native/stock-core.c`; the later commits modified the SPI
transport. None of these commit messages contained sign-off/review trailers.

Source: https://github.com/yoni13/armada-houji/commit/8c185d557d6afc90cdf0cef259986ac0065edeb9
Author: Yoni Yang <yoni980807@gmail.com>
Date: 2026-10-05T14:23:49Z

Houji: touch bus recovery, accurate battery percentage, sleep watchdogs, NFC logging

Touch:
- houji-tcm-probe resets and reconfigures the controller after any packet
  error (identity, report mode, touch reports, with backoff) and then
  re-enables its IRQ. A late GPI DMA completion past the SPI core's 200 ms
  limit used to stop touch until reboot. Debugfs houji-touch/recover
  triggers the same path.

Battery:
- Kernel patch 0028: the firmware linearizes capacity and, unplugged,
  updates it only on its 8-minute heartbeat, so it read 83% with 70% left.
  While discharging, report at most charge_now / charge_full and only let
  it fall; charging and full keep the firmware's figure.

Sleep:
- houji-sleep pauses systemd's service watchdogs for the suspend loop and
  restores them 5 s after the wake. Back-to-back dark wakes freeze
  userspace while CLOCK_MONOTONIC runs, and systemd killed armada-powerd
  (15 s watchdog) 16 times in a day.

NFC:
- The NFC manager logs where and how an operation failed, without payloads
  or card data, and names an unsupported activation's RF parameters.

Source: https://github.com/yoni13/armada-houji/commit/fde59dcff78fbffa7ede9c79645d2e49a20fa103
Author: Yoni Yang <yoni980807@gmail.com>
Date: 2026-09-30T18:35:10Z

Merge Armada 20260926 and enable Houji native suspend

Rebase the stock-ABL Xiaomi 14 port onto Linux 7.2.6 and the pinned Armada 20260926 image. Make native s2idle the default, retain light sleep as a fallback, and fix touch IRQ and decoder handling across suspend.

Include NFC Manager with persistent background tag emulation, update the reproducible build and preserving installer paths, and document the hardware validation and remaining limits.

Validated the full kernel and root image builds, installer and runtime regression checks, and on-device RTC and power-button wake with working Steam and touch.

Source: https://github.com/yoni13/armada-houji/commit/f5c689be6e603b259a5a85774d78c9cbd7cfefa4
Author: Yoni Yang <yoni980807@gmail.com>
Date: 2026-09-29T17:47:15Z

Add experimental Xiaomi 14 port with stock ABL boot

Build Houji kernel, userspace and internal boot images from pinned public inputs and bundled stock firmware. Include the guarded installer, device integrations, regression tests and build/flash documentation. Hide the incompatible generic installer on Houji.
