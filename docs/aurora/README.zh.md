# Xiaomi 14 Ultra（aurora）：实验性 recovery 与 EFI 系统

[English](README.md) · [支持状态](status.zh.md)

状态：见[硬件页](hardware.zh.md)和[支持状态](status.zh.md)。

Aurora 提供实验性 B 槽 U-Boot → systemd-boot → NixOS 系统及独立 RAM recovery。
先完成下列底包、配置和安装步骤；音频、USB 主机和休眠等限制见
[硬件支持与实现参考](hardware.zh.md)。

## 安装前必须准备的原厂底包

**安装 NixOS 需要中国版 Android 16 原厂 fastboot 包 OS3.0.308.0.WNACNXM。
安装前必须先刷入这一精确版本的底包。** 其他 Android 16 版本、其他地区
版本或此前支持的 Android 14 底包 OS1.0.3.0.UNACNXM 不能视为满足该前提。

| 项目 | 要求值 |
| --- | --- |
| 设备 | Xiaomi 14 Ultra，`aurora` |
| 原厂 fastboot 包 | 中国版 fastboot 包 `OS3.0.308.0.WNACNXM` |
| Android 版本 | `16`（build `BP2A.250605.031.A3`） |
| incremental build | `OS3.0.308.0.WNACNXM` |
| Android 安全补丁 | `2026-08-01` |
| NixOS 运行时固件 | OS3.0.308.0.WNACNXM 运行时文件（固定） |

先准备并刷入对应原厂底包，启动 Android 核对身份，再执行后文的 B 槽 recovery
和安装流程：

```sh
adb -s SERIAL shell getprop ro.product.device
adb -s SERIAL shell getprop ro.build.version.release
adb -s SERIAL shell getprop ro.build.version.incremental
adb -s SERIAL shell getprop ro.build.version.security_patch
```

这些属性用于确认正在运行的 Android；混刷或局部刷写后，不能据此证明所有固件
分区都匹配。首次准备使用完整、匹配的原厂 fastboot 包，保持 bootloader 解锁。
原厂刷机可能清除数据并覆盖双槽、AVB、DTBO，因此应在 Linux 分区和安装**之前**
完成。底包准备完成后，保留 Android A 槽，Linux 仅使用 B。不要将原厂全刷脚本
用于日常 NixOS 更新，也不要假定它会恢复原始 userdata/GPT 布局。

模块和独立固件包只包含 Android 16（OS3.0.308.0.WNACNXM）运行时固件，recovery
与已安装系统共用；自定义 firmwarePackage/NVM 覆盖必须来自同一版本。不再打包
Android 14 运行时固件，也不再支持 Android 14 底包。原厂重新刷机或 Android OTA
可能改变底层，之后使用 NixOS 前需重新核对。详见[固件内容与限制](firmware.zh.md)。

首次 B 槽启动前，还需准备 [`vbmeta_b`](#ram-启动前提)并核对[原厂显示固件](#保留-b-槽启动显示固件)。

### 从 OS1.0.3.0.UNACNXM 迁移已有安装

Android 14 安全固件会拒绝 Android 16 的 ADSP 镜像，因此底包和 NixOS 配置需一起更新：

1. 在 fastboot 下刷入 OS3.0.308.0.WNACNXM 原厂镜像，**不要**擦除 userdata 或
   重写分区表：Linux 的 `linux-boot` 与 `linux` 分区位于原 userdata 分配范围内。
   原厂镜像会替换 Android 槽位、AVB 和 DTBO，也可能替换 `boot_b` 与
   `recovery_b`，之后需重新安装 U-Boot 和 recovery。
2. 启动一次 Android A，核对上述身份属性，并确认 `linux-boot` 与 `linux` 分区仍在。
3. 按下文准备 `vbmeta_b` 并核对 `imagefv_b`。
4. 选择 B，用本版本构建的 U-Boot 镜像 RAM 启动（`fastboot boot`）现有 generation，
   然后更新已安装系统。
5. 按 [U-Boot 安装流程](../u-boot-install.zh.md)和[recovery 步骤](#将独立-recovery-安装到-b)
   安装新的 `boot_b` U-Boot 与 `recovery_b`。
6. 自定义蓝牙 NVM（`bluetoothNvm`）需从新版本重新生成；源自 Android 14 的 NVM
   与 Android 16 控制器固件不匹配。

## 配置与构建

使用导出的模块和公共构建接口：

```nix
androidDevices.lib.mkSystem {
  device = "aurora";
  buildSystem = "aarch64-linux"; # 也可使用 "x86_64-linux"
  nixpkgsConfig.allowUnfree = true; # 原厂 GPU/ADSP 固件
  modules = [ { androidDevices.recovery.enable = true; } ];
}
```

构建仓库示例：

```sh
nix build .#devices.aurora.recovery --out-link result-recovery
```

镜像使用 Android v0 头，包含带 Aurora 补丁队列的 Linux 7.3、追加的板级 DTB
和 systemd initrd。内核与 initrd 均包含在镜像中。板级 DT 使用从原厂核对的 USB 供电和固定内存保留区，
启用 PM8550B eUSB2 repeater、QMP combo PHY 与 WCD9395 mux；USB 使用 OTG、
默认 peripheral，最大速率 5 Gbps，方向 GPIO 已核对原厂设备树。

## 实验性 U-Boot

支持的启动路径见 [Android/U-Boot 兼容范围与 A/B 限制](../android-uboot-compatibility.zh.md)。

`nix build .#devices.aurora.u-boot --out-link result-u-boot`
构建 USB 控制台 RAM 固件，不改变 Linux recovery。已验证 ACM、六个 UFS LUN、
GPT 和块设备只读访问。启动前提、自动 reset 行为与限制见
U-Boot 固件说明。已安装 EFI 到 Linux 交接通过；
将独立 recovery 保留在 `recovery_b`，通过[检查式安装流程](../u-boot-install.md)写入
`boot_b`，保留 A。单独 RAM 实验无需先改 userdata 分区。

## RAM 启动前提

保留原厂 A 槽，实验仅使用 B。另行备份设备特有的校准/NV 数据，确认原厂镜像和
进入 bootloader 的方式可用。保留原厂 `dtbo_b`：其 overlay 引用主线 DT 不提供的
下游标签，U-Boot 镜像为 OS3.0.308.0.WNACNXM 原厂 DTBO 的全部标签提供空的接收
节点，ABL 合并因此成功且不改动真实节点（见 U-Boot 固件说明）。
全零的 `dtbo_b` 同样可用。完成上文底包准备后，RAM 测试阶段不要擦除 `dtbo_a` 或再次执行原厂刷机脚本。

要求的 bootloader 在 `fastboot boot` 期间校验活动槽实体分区的 AVB 链。未准备
`vbmeta_b` 时，空的或 Linux 的 `boot_b` 会因 AVB footer/header 无效而在 Linux
运行前回退 A，即使上传成功。bootloader 已解锁时，把原厂包自带的 `vbmeta.img`
以 verification-disabled 标志（2）刷入 `vbmeta_b`；`vbmeta_system_a/b` 和
`vbmeta_a` 保持不变：

```sh
fastboot -s SERIAL getvar current-slot
fastboot -s SERIAL flash --disable-verification vbmeta_b /path/to/factory/images/vbmeta.img
```

标志位是 `AVB0` 头偏移 120 处的大端 32 位字段，写入后读出 `00000002`（例如在
Linux 或 root Android 中执行
`dd if=/dev/disk/by-partlabel/vbmeta_b bs=1 skip=120 count=4 | xxd -p`）。
fastboot 选项是与 `flash` 配合的 `--disable-verification`，并没有独立的
`disable-verify` 命令。目标分区必须明确带 `_b`。未修改的 `vbmeta.img` 即恢复来源。
B 槽启动回退到 A 时，在原厂 Android 读取 `/dev/logfs/UefiLog*.txt` 确认。

此模式下 ABL 也会拒绝 OS version 为零的镜像。模块通过
`androidDevices.boot.android.osVersion` 和 `osPatchLevel` 提供与 OS3.0.308.0.WNACNXM
原厂 boot 头一致的 14.0.0 / 2026-08-01 元数据；它不是 recovery 的操作系统版本。DT 导出符号表及 `arch_timer` 标签，供固件 hypervisor overlay
使用。即使 `dtbo_b` 为空，该覆盖仍可能应用；应通过 UEFI 日志区分覆盖失败与
Linux 驱动失败。

`fastboot boot` 不会选择槽位。明确指定设备序列号，选择 B 并核对后再启动：

```sh
fastboot -s SERIAL getvar product
fastboot -s SERIAL getvar current-slot
fastboot -s SERIAL set_active b
fastboot -s SERIAL getvar current-slot
fastboot -s SERIAL boot result-recovery
```

这些命令不能证明原厂 bootloader 内部如何选择 DTBO。失败时保留镜像与启动日志。
镜像提供 ACM 控制台、USB NCM/SSH、UFS 块设备和原生 N1 显示；完整 recovery 使用
Rust daemon、VT 界面和交互式 `recovery shell`。
USB 串口提供本地 root shell；枚举成功后通过 `/dev/serial/by-id/` 连接。

示例同时启用 NCM 网络：设备地址 `172.16.46.1/24`，为主机提供 DHCP，SSH 端口22。
ACM 与 NCM 可同时枚举；USB3 状态与限制见[连接说明](connectivity.zh.md)。
默认允许通过这条 USB 网络以无密码 `root` 登录。需要公钥认证时，设置
`androidDevices.initrdUsb.ssh.requirePublicKey = true`，并提供
`androidDevices.initrdUsb.authorizedKeys`。完整 recovery 会在已验证的干净 Linux 根分区
复用或创建独立 SSH 主机密钥；存储不可用时退回 RAM 临时密钥，详见
[SSH 身份和连接配置](../recovery.zh.md#configure-and-connect)。
可先经 ACM 读取 `/run/mobile-recovery/ssh_host_ed25519_key.pub` 核验；
身份准备完成后不会保留目标挂载。

在 recovery shell 执行 `recovery reboot-bootloader --confirm` 返回
fastboot；确认没有残留recovery启动请求后，在主机切回A并正常重启Android：

```sh
fastboot -s SERIAL set_active a
fastboot -s SERIAL getvar current-slot
fastboot -s SERIAL reboot
```

此前的`fastboot reboot recovery`可能在共享BCB（`misc`）留下`boot-recovery`。
切到A并不会清除该命令，可能仍进入原厂recovery。应先检查BCB，不要误判槽位故障，
也不要擦除包含其它启动状态的`misc`。原厂recovery的ADB可执行
`adb -s SERIAL reboot bootloader`返回bootloader。

## 将独立 recovery 安装到 B

先按上述条件验证 RAM 启动，再把同一自包含镜像写入`recovery_b`。确认product为
`aurora`、active slot为B，且镜像小于报告的recovery容量（要求底包上为 100MiB）。
保留`recovery_a`及A槽其余分区：

```sh
fastboot -s SERIAL getvar product
fastboot -s SERIAL getvar current-slot
fastboot -s SERIAL getvar partition-size:recovery_b
fastboot -s SERIAL flash recovery_b result-recovery
fastboot -s SERIAL reboot recovery
```

已验证从分区独立启动、按镜像长度读回校验、ACM及NCM。运行环境仍完全在RAM中，
SSH 身份准备可能短暂挂载已验证的 Linux 根分区，完成后释放挂载。
这不是 B 槽 Android 回退系统，也不是已安装 Linux 系统。

## 首次分区、安装和增量更新（实验性）

完整 recovery 已接入共享首次安装、离线 `nixos-rebuild boot` 和 VT 菜单。
首次分区、安装、增量更新与已安装 EFI 启动均已实机验证。
`androidDevices.recovery.minimal = true` 可保留仅控制台模式。

构建示例系统及闭包元数据：

```sh
nix build .#devices.aurora.system --out-link result-system
nix build .#devices.aurora.boot-files --out-link result-boot-files
nix build .#devices.aurora.bootstrap-info --out-link result-bootstrap-info
```

在健康且独立的 B 槽 recovery 中执行：

```sh
recovery prepare-install --check                  # lists the offered sizes
recovery prepare-install --android-userdata 128G --check
recovery prepare-install --android-userdata 128G --confirm-erase-userdata
```

最后一条命令**不保留 Android userdata 数据**：按所选大小（32/64/128/256/512 GiB，
仅在 Linux 仍有至少 64 GiB 时提供，见 [recovery](../recovery.zh.md)）把原 userdata
分配的一部分留给 Android，其余分成 1 GiB FAT32 `linux-boot` 和 ext4 `linux`。
不缩容 F2FS，不保留 APK、加密数据及 ADB 授权。A、super、metadata、
校准及独立 recovery 分区不变。Android 的加密数据区仍须另行恢复出厂初始化；
Linux 格式化成功不表示 Android 已恢复可用。

工具检查主/备 GPT CRC、条目一致性、唯一标签、UFS 控制器、4 KiB 扇区、
挂载及设备占用。已有 Linux 分区或写入中断状态会拒绝自动重试。
先写备 GPT，再写主 GPT，回读通过才格式化。GPT 元数据证据留在
`/run/mobile-recovery/gpt-TASK_ID`，需拷回主机。此操作不是安全擦除。

Aurora 缺少可用的 slot_suffix 时，读取双份 GPT 中 Qualcomm 槽位属性，
要求 B 独占 active、非 unbootable、priority 非零且有 retry/success。
与 cmdline/bootconfig 的槽位提示冲突时拒绝。这证明下次启动选择 B，
不证明本次 RAM recovery 的加载来源，也不会伪造内核参数。

使用 [共享首次安装工具](../initial-install.zh.md) 导入完整闭包，核验 Nix
数据库并安装和校验 EFI 代际。更新 boot_b 固件使用[独立固件流程](../u-boot-install.zh.md#单独构建和刷写-u-boot)。
固件启用 ACM 后不再倒计时等待，直接从
外层 GPT 的 linux-boot 加载 EFI/BOOT/BOOTAA64.EFI，将 ABL 更新后重新定位的
DT 传给 EFI，加载返回则进入维护菜单。EFI/Linux RAM 交接和软件返回 recovery
尚未验证前，不应安装此实验固件。

```sh
recovery mount-target --rw
recovery rebuild boot --flake /path/to/config#aurora
recovery unmount-target
recovery deploy-check-boot
recovery reboot-system --confirm
```

更新复用已安装 Nix store；挂载为读写后，通过 `recovery generations` 查看代际，
`recovery select-generation NUMBER --confirm` 回滚。recovery 内拒绝 switch/test。
常规更新写 EFI 文件及代际，不重刷 Android boot 固件。

Wi-Fi、蓝牙、USB3 和 DisplayPort 的支持状态及本机蓝牙身份配置见
[连接支持与身份配置](connectivity.zh.md)。

完整 recovery 采用 Rust daemon、UI 与交互 shell。
ACM 默认进入 `recovery shell`，SSH 可直接运行 recovery 命令。设备端不包含
Python 运行时，也不保留旧 Shell 分区/安装后端。安装与更新复用目标 NixOS
自带的标准工具；这些工具可使用目标系统自身的 Python 依赖，不拷入 initrd。
任务不会因 UI 退出而终止；
输入传输中断会失败，完整接收后则独立完成本地安装。首次分区/安装、增量更新和已安装启动已在实机验证。

模块包含 GPU/ADSP 原厂固件，也可单独构建 `devices.aurora.firmware`；来源、哈希与加载分片检查见
[固件说明](firmware.zh.md)，硬件依赖见[连接支持](connectivity.zh.md)。

扬声器初始化、每台设备的原厂校准和播放格式见[音频配置说明](audio.zh.md)。

## 启动菜单与有线充电

在 U-Boot 接管时按住音量下进入维护菜单；正常启动仍无 U-Boot 倒计时。
音量键移动，短按电源选择。systemd-boot 增加重启、关机、OEM bootloader、
recovery B 和 Android A 入口，特殊目标有确认界面。Android A 选择会持续生效，
返回 NixOS 时通过 OEM fastboot 重新选择 B。

独立 RAM 充电环境安装在 `/EFI/android-devices/charger.efi`，只有 ABL 的完整
`androidboot.mode=charger` 参数触发自动进入；维护菜单也提供 **Start wired charging**。
显示电量及 USB 输入数据，20 秒自动关屏，短按电源切换显示，长按两秒请求普通重启；
确认拔线后五秒关机。本配置仅支持有线充电，不写充电限值。按键导航、关机插电进入、
显示切换和拔线行为尚未验证。

## 排障

### 保留 B 槽启动显示固件

首次准备 B 槽时，核对 `imagefv_b`；若与要求的原厂包不同，使用下方命令刷入，
此后 NixOS 更新应保留它。部分原厂刷机脚本会擦除两个 `imagefv` 槽位却只重写一个。不能因 Android A 槽正常就假定 B 槽该分区已有有效固件。
即使 `boot_b` 已安装 U-Boot，它仍参与原厂启动显示路径。该分区为空时，原厂 fastboot 与 U-Boot/EFI 都可能实屏黑屏，
但 USB 和帧缓冲渲染正常。此时 Android A 槽仍可正常显示，因此应对比启动固件
实际使用的槽位，不能只按前一个运行的系统判断原因。

出现此症状时，先检查原厂 UEFI 日志（root Android 下的 `/dev/logfs`）。
已确认的故障会出现 `pil-imagefv Failed to load metadata`，以及长度为零的
`logo.img`。先核对 `imagefv_b` 与原厂镜像，再考虑面板退出时序、tty或重启模式。
确认该分区异常后，仅用 **OS3.0.308.0.WNACNXM** 对应镜像恢复 B 分区，
不要执行原厂全刷脚本：

```sh
fastboot -s SERIAL flash imagefv_b /path/to/factory/images/imagefv.elf
fastboot -s SERIAL set_active b
fastboot -s SERIAL reboot bootloader
```

OS3.0.308.0.WNACNXM 的 `imagefv` 是 6,299,448 字节的 ELF，SHA-256：
`9b5cea4ff6e827895c0b8071ef442c8363530736af2f0de7afefdca687168b09`
（48 MiB 分区其余部分为零）。核对时比较分区前 6,299,448 字节。
恢复后验证 B 槽 fastboot 显示，以及 Linux 重启到 bootloader 的完整流程。
此修复无需擦除 `misc` 或修改 Android A 槽。

## 硬件参考

[硬件支持、已验证范围与驱动实现](hardware.zh.md)；
[固件来源](firmware.zh.md)、[连接与设备身份](connectivity.zh.md)、[音频与校准](audio.zh.md)。
