# 酷比魔方 iPlay 80 mini Ultra（t880）

[English](README.md) · [全部设备](../README.zh.md) · [支持状态](status.zh.md) · [安装指南](install.zh.md)

状态：**实验性；NixOS 可在 A 槽启动**（U-Boot → systemd-boot；面板上运行 niri，GPU 渲染；触摸尚不可用），国内名称为酷比魔方掌玩 Mini4
Ultra（Android 设备名 `T880`，主板 `p5n1_kb_t880_8883_b0`），SoC 为联发科
MT8883，属于 MT6897/天玑 8300 一类。原厂为 Android 16 与 6.1 GKI 内核。

U-Boot 镜像使用从 T880 本机读取的数值（运行时设备树、boot 镜像头、LK 日志与
GPT），已在设备上运行：屏幕、UFS（只读）、按键、看门狗，以及经 USB 2.0 线缆的
高速 USB fastboot/ACM。Type-C 直连与 SuperSpeed 尚未验证。Linux 7.3 与 RAM
recovery 可经 U-Boot raw FIT 暂存与 `bootm` 启动：屏幕控制台（simpledrm）、8 个 CPU、UFS
（全部 LUN 与分区）、USB NCM 网络与 SSH。在核对原厂
fastboot 身份并获准刷写之前，`mobile-device fastboot` 会拒绝 T880 镜像。

## 硬件支持

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| 启动（A 槽 U-Boot、systemd-boot、多代系统与回滚） | 可用 | Android 保留在 B 槽，`fastboot set_active b` 即可切回 |
| RAM recovery（屏幕菜单、USB 网络、分区、镜像写入） | 可用 | 经 U-Boot USB fastboot 从主机启动 FIT |
| 存储（UFS） | 可用 | UFS 4.0 HS-G5 x2，八个硬件队列（MCQ） |
| USB 设备模式（网络、SSH、U-Boot fastboot/ACM） | 可用 | Linux 下为 SuperSpeed（5 Gbit/s），插头方向由 Type-C 控制器给出（已测一个方向）；U-Boot 为高速 |
| USB Type-C 与 PD | 可用 | MT6375 端口控制器，仅 sink：方向检测与 5 V PD 协商（已用 PD 3.0 充电器与 Mac 端口测试） |
| 显示 | 可用 | 1600x2560，mediatek-drm 驱动两条显示管线（双 DSI、C-PHY、DSC），144/120/90/60 Hz，DPMS；在 mediatek-drm 接管前由 simpledrm 在引导程序帧缓冲上作启动控制台；默认使用物理扫描输出，通过 GCE/CMDQ 更新，两个 MM IOMMU 保持运行；显示的 IOMMU 地址转换仍未解决但已推迟，因为显示地址模式由设备固件控制（显示地址转换由设备固件控制）；偶发半屏黑屏、一次 DSI1 初始化超时及 DPMS 关闭时 GCE 仍活动的问题待解决；niri 示例会话 |
| GPU（Mali-G615，panthor） | 可用 | 固定 265 MHz；需要支持 v11 的 Mesa（OpenGL ES 3.1；Vulkan 经 PanVK，非一致性实现） |
| 音量键 | 可用 | 电源键尚未上报（位于 PMIC） |
| USB-C 直连与 USB-C 转 A 线 | 未测试 | |
| 触摸屏 | 可用 | Novatek NT36523N，10 点触控 |
| CPU/GPU 调频、温控 | 尚未支持 | |
| 背光与RTC | 可用 | 背光控制与RTC读取已验证 |
| 电池与充电 | 实验性 | MT6375 电池/输入状态与固定5V受限充电；120秒测试中亮度8的桌面亮屏时持续净充电，输入约9.4W、电池约7.0W。正常自动充电和终止设置已通过启动与120秒观察；充满与再充电尚未验证 |
| Wi-Fi | 可用 | MediaTek connsys 驱动（树外）、NetworkManager/iwd；需要原厂文件，见 [Wi-Fi](wifi.zh.md) |
| 蓝牙 | 实验性 | `hardware.t880.connectivity.bluetooth.enable`：BlueZ，可扫描与连接；支持控制器空闲休眠、唤醒与硬件电源开关，见 [Wi-Fi](wifi.zh.md#蓝牙实验性) |
| 音频 | 尚未支持 | |
| USB 主机/OTG、USB 3、DisplayPort 输出 | 尚未支持 | |
| CPU 空闲 | 可用 | 经 PSCI 进入各簇的 core-off 状态，前提是完成 MCUPM 启动握手（`mtk-mcupm`）；cluster 与 MCUSYS off 状态尚未支持 |
| 休眠 | 尚未支持 | |
| 硬件视频解码 | 部分支持 | V4L2/VA-API 支持 8 位 H.264/HEVC、VP9 profile 0 和 AV1 Main；裁剪、跳转与导出缓冲区检查通过；CPU 转换及重放可能开销较大 |
| 硬件视频编码 | 实验性 | V4L2 与原版 FFmpeg VA-API：H.264 Main CAVLC、HEVC Main，显式 AVBR/GOP30、单参考帧、无 B 帧及强制 IDR。HEVC 限于 1080p 像素面积；结束时仍有固件 FREE 协议错误 |
| 传感器、microSD、振动、摄像头、蜂窝网络 | 尚未支持 | |

## 已有内容

| 输出 | 内容 |
| --- | --- |
| `devices.t880.u-boot`（即 `boot`） | A 槽用的 header v4 boot 镜像：以 LZ4 内核形式打包的 U-Boot v2026.10，无 ramdisk（与原厂 boot 镜像一致）。 |
| `devices.t880.recovery` | 同一 U-Boot 镜像，ramdisk 为 FIT（内核、initrd、DTB）；限制见下文。 |
| `devices.t880.kernel` | Linux 7.3 加 [T880 补丁队列](../../pkgs/linux-kernel/mt6897/t880/PATCHES.zh.md)。 |
| `devices.t880.system`、`boot-files`、`bootstrap-info` | 示例：在面板（mediatek-drm）上运行 niri，并提供 USB 网络。GPU（Mali-G615，panthor）需要支持 v11 的 Mesa（Mesa main 或回移植）；nixpkgs 中的 Mesa 26.2 只能用 llvmpipe 渲染。 |

```sh
nix build .#devices.t880.u-boot --out-link result-u-boot
nix build .#devices.t880.recovery --out-link result-recovery
nix build .#devices.t880.kernel --out-link result-kernel
```

### 调制解调器元数据升级顺序

含队列补丁 0182 的内核需要 U-Boot 补丁 0036 转交实际的 LK 调制解调器描述符。
请先通过恢复环境的固件更新命令
升级 A 槽 U-Boot，再安装新内核。旧 U-Boot 仍可启动 Linux，但调制解调器元数据
不可用，蜂窝调制解调器保持禁用。NixOS 代际更新不会替换 `boot_a`。
已验证运行时描述符转交、正常调制解调器启动以及经更新后 U-Boot 启动 RAM recovery。
请保留可工作的引导程序镜像与 [USB RAM 恢复路径](install.zh.md)。


### 调制解调器停止失败

调制解调器 owner 会等待 FSM 停止完成及原始 GATED 状态后才报告完成。
尚未完成的停止返回 EINPROGRESS；平台或预停止失败返回锁存的错误码，owner
以非零状态退出。锁存失败后再次启动调制解调器前应先重启主机。仍不支持模块卸载
和手动解绑；仅有 GATED 状态不能证明物理电源域已关闭或 DMA/传输已完整清理。

NixOS 使用 A 槽；Android（原厂 vendor 上的 GSI，Virtual A/B）保留在 B 槽，
`fastboot set_active b` 即可切回。A 槽的原厂 LK 加载 `boot_a`；vendor_boot、
init_boot、dtbo 与 vbmeta 保持原厂。U-Boot 从 LK 传入的 FDT 读取内存、保留区、
initrd 范围和帧缓冲，持续喂看门狗并在 LK 帧缓冲上显示。默认流程：boot 镜像
ramdisk 中有 recovery FIT 时启动它，否则从 FAT 分区 `linux-boot`
启动 systemd-boot，否则停在 USB fastboot（序列号取自 LK，下载缓冲 128 MiB）：
`fastboot stage` 下载原始 FIT，再由 U-Boot `bootm` 启动，`fastboot oem console` 显示控制台，
`fastboot continue` 切换到 USB ACM 控制台（`run fastboot` 返回），
`fastboot reboot-bootloader` 进入原厂 LK fastboot。启动菜单（按住音量下）10 秒后
超时，提供相同选项。若 `autoreset_s`（90）秒内没有 USB 主机连接，U-Boot 让看门狗
复位设备；LK 将其计为启动失败，数次后回退到 B 槽的 Android。U-Boot 唯一写入的存储
是 misc 中 A 槽的 successful 位：仅在从 `linux-boot` 加载 `/EFI/BOOT/BOOTAA64.EFI`
成功之后。

LK 无法从 `boot_a` 交付 RAM recovery：把 47 MB 的 FIT 作为 boot 镜像 ramdisk 时，LK
在加载 `boot_a` 时断言失败；其 64 MiB ramdisk 区还与原厂 vendor ramdisk（约 27 MB）
共用。请用[原始 FIT 暂存命令](install.zh.md#2-从内存启动-recovery)从主机启动 recovery FIT。

recovery 为完整版本：面板上的屏幕 UI、Rust 存储 daemon 与 NCM/SSH。其存储模型保留
B 槽 Android，并检查设备（compatible、bootloader 序列号、misc 中选择 A 槽且 B 可启动的
AOSP boot control）。`recovery prepare-install --android-userdata SIZE --check` 按所选
Android 大小（[可选大小](../recovery.zh.md)）打印 userdata 范围内的拆分计划，其他部分不变：

| 条目 | 用途 | 大小 |
| --- | --- | --- |
| 80 `userdata` | B 槽 Android，不格式化（清零前 8 MiB） | 所选大小 |
| 83 `linux-boot` | FAT ESP | 1 GiB |
| 84 `linux` | ext4 根分区 | 其余空间 |

GPT 在条目数组现有扇区内由 82 项扩展为 84 项。拆分后 Android 需由其自带 recovery 恢复
出厂：LK fastboot → `fastboot set_active b` → `fastboot reboot recovery` → “Wipe
data/factory reset”（按新大小格式化 userdata 并重置 metadata 加密）→ 启动 Android；
`adb reboot bootloader` → `fastboot set_active a` 返回 NixOS。
Recovery 由主机提供：以 `recovery` 参数重启进入 U-Boot USB fastboot，
再执行[原始 FIT 暂存命令](install.zh.md#2-从内存启动-recovery)。音量键使用 SoC 键盘，电源键使用 PMIC 输入。
此路径需要 A 槽 U-Boot 正常；若损坏，先通过 stock LK fastboot 恢复 U-Boot。

写入 `boot_a` 的镜像必须填满 64 MiB 分区并带有 AVB hash footer：解锁的 LK 仍经
AVB 加载 `boot_a`，缺少可解析的 footer 与 vbmeta 时会在加载 boot 镜像头之前断言失败。
U-Boot 镜像已按此构建。

首次安装见[安装指南](install.zh.md)（分区、recovery 与 NixOS 系统；已在一台 T880 上验证）。

## U-Boot 中的重启路径

| 请求 | 结果 | 状态 |
| --- | --- | --- |
| `fastboot reboot`、`reset`（ACM） | PSCI 复位；LK 再次启动 A 槽并计入重试次数 | 已验证 |
| `fastboot reboot-bootloader`、`rebootmode bootloader`、菜单“Stock bootloader fastboot (LK)” | 进入 LK fastboot（product `p5n1_kb_t880_8883_b0`） | 已从 fastboot 与 ACM 验证；菜单按键未测试 |
| `fastboot reboot recovery` | LK recovery 模式加载 A 槽 U-Boot，等待主机经 USB fastboot 提供 FIT | RAM recovery |
| LK recovery 模式或 misc `boot-recovery`；ESP 缺失或 systemd-boot 返回 | 等待 U-Boot USB fastboot；只读 misc | RAM recovery |
| `fastboot reboot fastboot` | 被拒绝（“Cannot set fastboot flag”）；NixOS 侧没有用户态 fastbootd | 未实现 |
| `fastboot stage <FIT>` 后执行 `oem 'run:bootm ${fastboot_addr_r}'` | 下载原始 FIT，并从 RAM 启动选定配置 | 已验证 |
| `autoreset_s` 内无 USB 主机 | 看门狗复位；重试用尽后 LK 启动 B 槽 Android | 已验证 |
| 关机 | 没有 `poweroff` 命令；PSCI SYSTEM_OFF 可用但未测试（需按电源键开机；接线时 LK 可能进入充电模式） | 未实现 |


## 设备数值

| 项目 | 数值 | 状态 |
| --- | --- | --- |
| boot 镜像 | header v4，页 4096，LZ4-legacy 内核，无 ramdisk；LK 按 vendor_boot 把内核加载到 `0x40000000`、ramdisk 到 `0x66f00000`（上限 64 MiB）、DTB 到 `0x47c80000` | 已测量；U-Boot 按此打包 |
| 槽位与 boot 分区 | NixOS 用 A，Android 用 B；`boot_a` 64 MiB；无 recovery 分区 | 已测量 / 已确定 |
| 内存 | `0x40000000` 起 12 GiB；LK 保留区 57 个 | 已测量；运行时读取 |
| CPU、PSCI、GIC、timer | GICD `0x0c400000`、GICR `0x0c440000`、PSCI smc、13 MHz | 已测量 |
| UART | `0x11001000` mt6577，921600 | 已测量；U-Boot 未使用 |
| UFS | HCI `0x112b0000`（SPI 168，MCQ 177–184），PHY `0x112a0000`，`0x112bb000` 处的 ti,syscon 复位 | 已验证读取（gear 5、2 lane、GPT）；U-Boot 只读 |
| USB 设备模式 | mtu3 `0x11201000`（ippc `0x11203e00`），xsphy u2 `0x11e40000`，强制 VBUS | 已验证：高速 fastboot 与 ACM；U-Boot 解除原厂 bootloader 强制的 PHY 状态 |
| 看门狗 | RGU `0x1c00a000`，preloader 已启用 | 已测量；U-Boot 重新启动并喂狗（15 秒） |
| 按键 | 键盘控制器 `0x1c00e000`：音量下 index 0、音量上 index 1；电源键在 MT6363 | 已测量；U-Boot 只读键盘控制器 |
| 帧缓冲 | `0xfd11f000`，VRAM `0x2ee0000`，1600×2560 ARGB8888，pitch 6400 | 已测量（pitch 为推算） |
| compatible | `alldocube,t880`、`mediatek,mt6897` | 本项目选定 |
| Linux 存储 | 自 userdata 拆分 FAT `linux-boot` 1 GiB 与 ext4 `linux` | Android 保留所选大小，Linux 使用其余空间 |
| 原厂 fastboot | LK product `p5n1_kb_t880_8883_b0`；可从 Android（`adb reboot bootloader`）或 U-Boot（`fastboot reboot-bootloader`）经 reboot-mode 寄存器进入 | 已验证 |
| 内核与 recovery DT | 实测数值：simplefb、reboot mode、xsphy 与 mtu3 强制 VBUS；ramoops 使用独立的 DRAM 区（LK 会从 expdb 恢复其 pstore 区） | 已通过 U-Boot 原始 FIT 验证启动 |


充电只请求固定5V，最大3A；输入与电池电流设为最多2.1A，实测超过2.2A
停止，输入还受协商电流限制。设定 CV 为 4.40 V；采样值略高于这个调节目标
本身不视为过压。芯片 BATOV 等硬件故障状态会停止充电，BATOV 的具体电压阈值
尚未确定。低于 10°C 或达到 45°C 时停止，传感器或
电气异常锁定关闭。Recovery 禁止自动启动充电。未启用9V或PPS。
修正后的判定已通过短时充电测试，充满及涓流阶段仍未验证。
USB Wi-Fi、蓝牙、读卡器、音频和常用串口驱动作为模块保留；USB主机功能
尚未验证，外接适配器可能需要由使用者配置提供匹配固件。
