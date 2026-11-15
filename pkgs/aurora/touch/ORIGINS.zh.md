# 触摸源码来源

[English](ORIGINS.md)

SPI 传输和原生适配器来自
[yoni13/armada-houji](https://github.com/yoni13/armada-houji/tree/5d6156dbb0ce23d0156040219be38bbc28aa15c8/ports/houji/touch)，
固定提交 `5d6156dbb0ce23d0156040219be38bbc28aa15c8`。`stock-core.c` 使用 SPDX MIT；
`sha256.c` 是 iw 6.17 中的公有领域 LibTomCrypt 实现，iw 声明在 [COPYING](COPYING)。
内核传输为 GPL-2.0-only。OEM 库和配置为专有资产，权利归其所有者。未修改的
payload 位于 [Aurora 固件 release 归档](../../../docs/aurora/firmware.zh.md#固件来源)
的 `touch/` 中，与本适配器源码分开。

本地改动：Aurora regulator 接线和几何、Android 14 库/配置哈希、函数地址、三参数
解码帧分配、1722 字节原始帧校验/checksum、输出元数据偏移，以及 Android 14
compute entry 内已有的 temporal update。此模式下内核输入只来自用户空间处理器；
驱动检查已知控制器身份和几何，启用 raw report，并在移除时静默 recovery。`aurora-tcm`
中的默认固件触摸报告解码器遵循 Synaptics TouchComm 驱动的 TouchCom report config
格式，不使用 OEM 库。运行时接口见 [README](README.zh.md)。

以下原始提交元数据原样保留。最初提交引入 `native/stock-core.c`；后续提交修改 SPI
传输。这些提交消息都没有 sign-off/review trailer。

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
