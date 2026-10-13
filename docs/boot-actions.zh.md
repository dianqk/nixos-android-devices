# 引导菜单中的电源与重启操作

[English](boot-actions.md)

全部五个设备模块都在 systemd-boot 中启用 **Reboot The System**、**Power Off The System**、
**Reboot to bootloader** 和 **Reboot to recovery**。Asphalt、Sheng 和
Aurora 还启用 **Reboot to Android**。这些操作在 Linux 之前执行。更新固件时，
请保留可用的独立 RAM recovery。

| 设备配置 | Recovery | Android | 固件后端 |
| --- | --- | --- | --- |
| Polaris / Clover | OEM recovery 目标 | 未启用 | Qualcomm PON |
| Asphalt / Sheng / Aurora | 安装在 `recovery_b` 中的 NixOS RAM recovery | Android `boot_a` | Qualcomm SDAM + GPT A/B + UFS boot LUN |

所有设备的重启目标均尚未经过真机验证；编译和模拟故障测试无法验证 OEM 固件的行为或已安装的 recovery。

<a id="configure"></a>
## 配置

导入导出的设备模块，例如 `nixosModules.sheng`。设备模块提供默认值；共享
模块使用显式选项，而不是按设备名选择。可以单独禁用某项操作：

```nix
{
  androidDevices.boot.actions = {
    reboot = true;
    poweroff = true;
    bootloader = true;
    recovery = true;
    recoveryTarget = "slot-b"; # Asphalt/Sheng; "oem" for Polaris/Clover
    android = true;           # Requires the Qualcomm A/B firmware backend
  };
}
```

辅助程序在各配置间共享。固件构建会显式选择可复用的 `pon` 或 `qcom-ab`
配置；后者包含 SDAM 和 UFS 槽位后端。原生构建和交叉构建使用相同策略，仅编译器
平台不同。RAM recovery 配置不会安装此 EFI 菜单或辅助程序。

<a id="automatic-slot-b-confirmation"></a>
## 自动确认 B 槽

Sheng、Asphalt 和 Aurora 共用一个 U-Boot 补丁以及 Qualcomm GPT/UFS 后端。
`fatload` / `bootefi` 从唯一的 `linux-boot` ESP 成功加载
`/EFI/BOOT/BOOTAA64.EFI` 并设置其加载选项后，U-Boot 会在启动该 EFI 镜像前
将 **`boot_b` 标记为成功**。这确认的是固件/存储/EFI 加载阶段；并不保证系统代
菜单能显示或 Linux 能正常工作。其他 EFI 路径、设备和分区不会触发确认。此钩子
不涵盖 EFI BootOrder/启动管理器条目的执行。

只修改两份 GPT 副本中的成功位和所需的 CRC。Android A、类型 GUID 和唯一
GUID、活动标志、优先级、重试计数、UFS boot LUN、BCB 以及分区内容均保持不变。
B 已标记为成功时无需写入。剩余重试次数为零的最后一次允许尝试仍可被确认；
Android A 可启动、BCB 为空以及 `recovery_b` 都不是前提条件。

通用固件配置显式启用确认，并提供 ESP 名称和 EFI 路径。Polaris 和 Clover
不启用此功能。不同的分区/LUN 位置在运行时探测；此 Qualcomm 后端不适用于使用
AOSP `misc` boot-control 元数据的设备。Asphalt 已有此最小成功位更新的真机
证据；新钩子以及 Sheng 的 OEM 行为仍需真机验证。

Asphalt 仅为 **B 槽成功确认** 允许 LUN6 和 LUN7 上存在零元数据布局。该兼容
设置来自一台实测设备，并不代表所有 Asphalt 的出厂布局。每个启用的候选 LUN
都会在运行时检查：其完整的 LBA0、LBA1 和末尾块必须可读。若三者都是全零，
可在 GPT 检查中略过；否则必须与其他所有带 GPT 的 LUN 一样通过完整的双 GPT
检查。因此，这些 LUN 上带有有效 GPT 的其他 Asphalt 设备仍受支持。不存在或
已禁用的候选 LUN 无需例外。元数据块为零并不意味着整个 LUN 为空；固件绝不会
为通过此检查而格式化 LUN。所有启用的 LUN 仍必须存在。其他设备默认没有例外；
Android 和 recovery 操作不使用这个仅用于确认的例外。

固件设置编译进 U-Boot，而不是通过 `setenv` 设置：

```text
CONFIG_EFI_MOBILE_BOOT_ACTION=y
CONFIG_EFI_MOBILE_BOOT_ACTION_QCOM_AB=y
CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM=y
CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_ESP="linux-boot"
CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_PATH="/EFI/BOOT/BOOTAA64.EFI"
CONFIG_EFI_MOBILE_QCOM_AB_CONFIRM_NON_GPT_LUN_MASK=192
```

最后一项是十进制位掩码：在 Asphalt 上，192 选择第 6 位和第 7 位。
共享配置接受显式的 `confirmationNonGptLunMask`，默认值为 0；它绝不按设备名
选择例外。未核实其他硬件的布局前，不要将 Asphalt 的掩码照搬过去。读取失败、
CRC 错误和副本冲突仍视为错误，候选 LUN 也不例外。非零元数据永远不适用零元数据例外。

确认出错时会记录日志，并继续执行 EFI。遇到返回的写入或回读错误时会尝试恢复
GPT；恢复失败则在该 U-Boot 会话中禁用后续确认和特殊启动操作。先写备份及回读
校验并不能使被中断的 GPT 更新在断电时保持原子性。需将重新构建的 U-Boot 安装到
`boot_b` 才能启用此行为；仅更新 EFI 文件不会更新固件。

<a id="android-slot-switch-checks"></a>
## Android 槽位切换检查

Android 操作将持久活动槽改为 A，并请求 OEM 重启。它不会从 U-Boot 链式加载
Android 内核。其布局策略独立于 B 槽自动确认：

```text
CONFIG_EFI_MOBILE_QCOM_AB_ANDROID_NON_GPT_LUN_MASK=192
```

共享固件配置的 `androidNonGptLunMask` 默认为 0；Asphalt 针对实测的 LUN6/7
候选使用 192。Recovery 仍要求完整 GPT。每个启用的 LUN 都必须纳入检查。只有
LBA0、LBA1 和末尾块读出均为零的已配置候选才适用；任何非零元数据都要经过
完整 GPT 验证。带有 boot ID 的 LUN 不能使用此例外。

在提供 Android 操作前以及执行前，固件都会将 UFS boot selector ID 1 和 2
与包含 `xbl_a` 和 `xbl_b` 的物理 LUN 对应起来。boot ID 映射缺失、重复、
被禁用或位置错误时，拒绝执行该操作。配置描述符必须启用 boot 功能。不假定
selector 值等于普通 LUN 编号。

仅凭 BCB 命令为空，并不能排除 OTA 快照操作。固件还会读取位于
`misc + 32 KiB` 的 64 字节 Virtual A/B 记录。此实现只接受版本 2、已知 magic、
源槽位为 0 或 1、保留字节为零且状态为 NONE 的记录。源槽位记录的是历史写入，
无需与当前 B 槽一致。UNKNOWN、SNAPSHOTTED、MERGING、CANCELLED、不支持的
格式和读取错误都会拒绝执行；固件绝不会清除或取消快照状态。支持其他格式或
CANCELLED 需要进一步审查。其他系统区记录保持不变，且无需为零。

这些检查确认的是元数据前提条件，而不是每个 Android/早期固件载荷的完整性或
能否成功启动。在真正尝试切换槽位前，请保留经过独立验证的 recovery 和返回 B
槽的流程。固件日志会标明 GPT LUN、boot 映射、快照或槽位/请求方面的失败。

<a id="build-install-and-update"></a>
## 构建、安装与更新

按照[配置指南](configuration.zh.md)构建相互匹配的 system、boot-files 和 U-Boot
输出，然后遵循经过检查的 [U-Boot 安装流程](u-boot-install.zh.md)。在
Asphalt/Sheng 上，保留 Android A，并将 NixOS recovery 安装到 **`recovery_b`**，
与安装在 **`boot_b`** 中的 U-Boot 分开。参见 [recovery 指南](recovery.zh.md)。
菜单不会安装或替换这两个镜像；它可以检查分区元数据，但不能保证 recovery 载荷
可用。

EFI 辅助程序和条目随初始 boot-files 包以及后续标准 NixOS 引导器更新一起安装。
禁用某项操作后，下次更新会移除其条目；禁用全部特殊操作会移除辅助程序。

普通的 `nixos-rebuild boot` 会更新 EFI 文件，但不会替换物理 boot 分区中的
U-Boot。已有安装需要单独执行经过检查的 U-Boot 更新才能提供此接口。旧固件会
拒绝不支持的操作并返回菜单。新的 `recovery-b` 能力与 OEM recovery 不同，
因此旧的 PON 后端不会误执行它。

<a id="use-and-troubleshoot"></a>
## 使用与排障

特殊条目会显示确认界面，默认选中 **Cancel**。使用音量上/下键选择，短按电源键
确认；也可以使用串口/USB ACM 控制台输入。Escape 取消。即使将特殊条目保存为
默认项，也不会定时自动执行。取消和返回的操作错误都会回到系统代菜单。

Bootloader 指 **OEM bootloader fastboot**，不同于 U-Boot fastboot 和 Android
用户空间的 fastbootd。重启和关机使用 systemd-boot 的内置条目，不会切换槽位。

对于 Polaris/Clover，recovery 操作请求进入 OEM recovery 目标，使用其中已安装
的内容；它不会直接启动 EFI NixOS recovery。这些操作仅修改 PON 的原因字节，
保留第 0 位，校验回读并请求 PSCI 重置。它们不写入任何分区或槽位元数据；已有的
BCB 请求可能影响最终进入的目标。

对于 Asphalt/Sheng：

- **Recovery** 要求 B 为活动且可启动的槽位、UFS boot LUN 为 2、GPT 一致且存在
  `recovery_b`。它只修改 SDAM 重启模式位，并保留第 0 位。
- **Android** 要求 A 可启动、同样经过验证的活动 B 槽状态、`misc` 中的 BCB 命令为
  NUL 空、boot-LU 映射已验证，且快照处于已知的 NONE 状态。
  待处理的 recovery/OTA 命令会被拒绝，而不是被悄悄清除。它修改成对分区的类型
  GUID 和活动标志，以优先级 3 和七次重试选择 `boot_a`，清除 A 的成功/不可启动
  标志，并选择 UFS boot LUN 1。B 的成功/重试标志保留；其优先级变为 2。XBL
  选择使用 boot LUN，其条目保持不变。
  Android A 的选择会一直保持，直到另一次经授权的槽位切换，例如 OEM fastboot
  的 `set_active b` 或 Android 的 boot-control 接口。再次选择 B 时，会按该接口
  重置其成功/重试状态。
- **Bootloader** 只需要 SDAM/PSCI 后端；存储不可用并不妨碍进入 OEM fastboot。

槽位检查要求：每个启用的 UFS LUN 都存在、逻辑扇区为 4096 字节，带 GPT 的 LUN
具有受支持的 GPT 头部和 128 字节条目，主/备份数组一致且 CRC 有效，名称唯一，
A/B 对完整且一致。布局未知或损坏、槽位/boot LUN 状态不一致、缺少 recovery
分区或存在未完成的 BCB 命令时，会拒绝执行，不重置也不写入。
如果某项操作不可用，请先通过 Linux 或 RAM recovery 检查这些条件再重试。即使
固件拒绝提供某项能力，特殊菜单仍然可见，以便诊断。

GPT 写入会保留分区内容、唯一 GUID、几何参数、PMBR 和填充。它只更新发生变化的
元数据块，先写备份再写主 GPT，并校验不经缓存的回读。修复后的 U-Boot SCSI 写入
路径使用 FUA 实现持久写入。遇到返回的 I/O、回读或重置错误时，后端会尝试恢复
GPT、boot LUN 和原始原因值，尝试所有恢复步骤，并报告汇总的恢复错误。恢复失败
会在该固件会话中禁用后续特殊操作；重启或重试前请检查状态。

跨多个 LUN 的 GPT/boot LUN 切换无法在突然断电时保持原子性。请使用可靠的电源；
回滚保证覆盖的是返回的错误，而非断电。不会写入任何分区载荷、Android super 内容
或熔丝。

看门狗设置失败时会立即返回上级菜单。完全无法加载的条目遵循 systemd-boot 配置的
`reboot-on-error` 策略。
