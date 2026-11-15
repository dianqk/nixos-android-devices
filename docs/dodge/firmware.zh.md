# Dodge 固件

[English](firmware.md)

导出的 `nixosModules.dodge` 默认使用 `dodge-firmware` 包。它从仓库的
[`firmware` release](https://github.com/dianqk/nixos-android-devices/releases/tag/firmware)
获取 `dodge-firmware-LineageOS-24.0-5dd12b17e7-20261115.tar.zst`。在 Nixpkgs
配置中允许 unfree 的 `dodge-firmware` 和 `dodge-firmware-zstd`。

来源是一台运行 `LineageOS 24.0-20261103-NIGHTLY-dodge` 的 OnePlus 13 PJZ110，
vendor/ODM incremental 为 `5dd12b17e7`（Android 17，`CP2A.260605.016`）。资产名
描述这个观察到的自定义 vendor 构建；其底层 ColorOS 基础未验证。

归档包含带顶层 `SHA256SUMS` 的 Linux payload 树：

- `lib/firmware`：GPU、Wi-Fi、蓝牙、ADSP、CDSP、modem、SoCCP、视频、音频
  topology 和放大器表。CDSP remoteproc 文件于 2026-11-15 从手机只读 `modem_a`
  镜像加入；`dsp_a` 用户空间 shell 树不在归档中。
- `share/alsa/ucm2`：音频 profile。
- `etc/sensors`、`dsp`、`seed/registry`：SSC 运行时数据和 registry 默认值。

这是准备好的运行时 payload，不是 OEM 提取树。不包含每机 persist/校准数据。包会
校验归档 checksum 并应用维护的 UCM profile。Recovery 省略 ADSP 和视频镜像。
Linux 通用 `wireless-regdb` 仍是独立上游包；ROM 的 Wi-Fi `regdb.bin` 包含在
`dodge-firmware` 中。

要提供另一个匹配 payload，将 `hardware.dodge.firmwareSource` 设为具有该布局的
目录。使用 `gpu`、`wlan`、`audio` 和 `sensors/config` 的旧提取树必须先映射到
Linux payload 布局。`hardware.dodge.firmwarePackage` 可替换包；其 `audio`、
`modem` 和 `sensors` 属性必须暴露对应数据。默认包将三者都别名到单一输出。

## 添加固件文件

把新文件加入完整 payload 树，然后重建仓库的每设备归档，不要发布散落文件或单独
固定固件。使用确定性归档（排序 `tar`，mtime/uid/gid 归零）和单线程
`zstd -19`；重新生成顶层 `SHA256SUMS`，更新来源 `README`，并更新
`pkgs/dodge/firmware-source.nix` 中的 URL 与 SRI。发布替换归档前，用
`sha256sum -c SHA256SUMS` 验证一次干净解压，并确认所有旧文件字节一致。
