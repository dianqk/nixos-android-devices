# 设备 U-Boot

[English](README.md)

基线是官方 U-Boot **v2026.10**，提交
[`5508406582f6f7120dce0c4b3059819a41788db2`](https://git.u-boot-project.org/u-boot/u-boot/-/commit/5508406582f6f7120dce0c4b3059819a41788db2)。
`default.nix` 使用 nixpkgs 为该版本提供的 `buildUBoot` 源码并应用本地补丁；
`devices.nix` 选择具体板级包。配置与安装见[安装指南](../../docs/u-boot-install.zh.md)。

| 设备 | 软件包引用 |
| --- | --- |
| Dodge / SM8750 | `devices.dodge.boot-firmware` |
| Polaris / SDM845 | `devices.polaris.u-boot` |
| Asphalt / SM8475 | `devices.asphalt.u-boot` |
| Marble / SM7475（仅 U-Boot） | `devices.marble.u-boot` |
| Clover / SDM660 | `devices.clover.u-boot` |
| Sheng / SM8550 | `devices.sheng.u-boot` |
| T880 / MT6897 | `devices.t880.u-boot` |

## Polaris

Polaris 使用上游 `qcom_defconfig` 和 `board/qualcomm/qcom-phone.config`，本地补丁
处理 ABL framebuffer 预留和位图字体缩放。补丁头记录来源。环境基于上游
GPL-2.0+ 的 `qcom-phone.env`，从 UFS 上物理 GPT `system` 分区加载
`/EFI/BOOT/BOOTAA64.EFI`。Linux 将该 FAT 分区挂载为 `/boot`，并用 ext4
`userdata` 作为 `/`（含 `/nix/store`）。

安装器在放宽保留的 Android GPT 类型检查前会核对已挂载的 FAT 设备。该类型上
不持久化 EFI 变量。检查启动状态：

```sh
SYSTEMD_RELAX_ESP_CHECKS=1 bootctl --esp-path=/boot status
```

上游 GPL-2.0+ 的 8×16 字体用 `VIDEO_FONT_SCALE=3` 放大为 24×48 字形；其他板
默认为 1。`vidconsole` 排在 stdout/stderr 前，使 EFI 使用面板的 45×45 字符
网格。串口和 USB ACM 仍可用。使用方法和硬件限制见[启动菜单指南](../../docs/polaris/boot-menu.zh.md)。

## 共享 USB 控制台与输入

ACM 补丁允许在没有 USB 主机时启动，并支持之后连接控制台；它们限制卡住的传输，
并在断开时取消请求。按键补丁修正按下/释放事件；SPMI 和 PMIC GPIO 补丁保留板级
偏置与电源设置。板级连线仍留在各设备包中。

对打过补丁的 U-Boot 源码运行：

```sh
python3 tests/uboot-acm-lifecycle.py /path/to/patched/u-boot
python3 tests/uboot-font-scale.py /path/to/patched/u-boot
python3 tests/uboot-button-events.py /path/to/patched/u-boot
```

字体测试使用 AddressSanitizer/UndefinedBehaviorSanitizer，检查 1–4 倍缩放下的
全部 256 个字形、填充、旋转、分配失败和重新选择。仍需真机输入、显示和冷启动
检查。
