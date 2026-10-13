# Xiaomi 14 Ultra（aurora）：实验性 recovery 与 EFI 系统

[English](README.md)

支持等级：Tier 2。具体含义见[支持范围](../README.zh.md#支持等级)。

Aurora 提供实验性 B 槽 U-Boot → systemd-boot → NixOS 系统及独立 RAM recovery。
先完成下列底包、配置和安装步骤；音频、USB 主机和休眠等限制见
[硬件支持与实现参考](hardware.zh.md)。

## 安装前必须准备的原厂底包

**安装 NixOS 需要中国版 Android 14 原厂 fastboot 包 OS1.0.3.0.UNACNXM。
安装前必须先刷入这一精确版本的底包。** 其他 Android 14 版本、其他地区
版本或 Android 16 不能视为满足该前提。

| 项目 | 要求值 |
| --- | --- |
| 设备 | Xiaomi 14 Ultra，`aurora` |
| 原厂 fastboot 包 | `aurora_images_OS1.0.3.0.UNACNXM_14.0` |
| Android 版本 | `14` |
| 运行时 incremental build | `V816.0.3.0.UNACNXM` |
| Android 安全补丁 | `2024-02-01` |
| NixOS 运行时固件选择 | `hardware.aurora.firmwareVariant = "android14";`（默认） |

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

模块、独立固件包和仓库示例默认使用 Android 14。recovery 与已安装系统必须
选择同一版本，自定义 firmwarePackage/NVM 覆盖也需配套；切换后重建 initrd 并重启。
[旧版 Android 16 变体](firmware.zh.md#legacy-android-16-variant)不是受支持的安装底包；
Android 14 运行时固件在 Android 16 底层未经验证。原厂重新刷机或 Android OTA
可能改变底层，之后使用 NixOS 前需重新核对。详见[固件内容与限制](firmware.zh.md)。

首次 B 槽启动前，还需核对[原厂显示固件](#保留-b-槽启动显示固件)。

## 配置与构建

使用导出的模块和公共构建接口：

```nix
androidDevices.lib.mkSystem {
  device = "aurora";
  buildSystem = "aarch64-linux"; # 也可使用 "x86_64-linux"
  nixpkgsConfig.allowUnfree = true; # 原厂 GPU/ADSP 固件
  modules = [ {
    hardware.aurora.firmwareVariant = "android14";
    androidDevices.recovery = { enable = true; minimal = false; };
    androidDevices.initrdUsb = {
      enable = true;
      acm.enable = true;
      network.enable = true;
      address = "172.16.46.1/24";
    };
    boot.kernelParams = [ "clk_ignore_unused" "pd_ignore_unused" ];
  } ];
}
```

构建仓库示例：

```sh
nix build .#devices.aurora.recovery --out-link result-recovery
```

镜像使用 Android v0 头，包含带 Aurora 补丁队列的 Linux 7.3-rc6、追加的板级 DTB
和 systemd initrd。内核与 initrd 均包含在镜像中。板级 DT 使用从原厂核对的 USB 供电和固定内存保留区，
启用 PM8550B eUSB2 repeater、QMP combo PHY 与 WCD9395 mux；USB 使用 OTG、
默认 peripheral，最大速率 5 Gbps，方向 GPIO 已核对原厂设备树。

## 实验性 U-Boot

支持的启动路径见 [Android/U-Boot 兼容范围与 A/B 限制](../android-uboot-compatibility.zh.md)。

`nix build .#devices.aurora.u-boot --out-link result-u-boot`
构建 USB 控制台 RAM 固件，不改变 Linux recovery。已验证 ACM、六个 UFS LUN、
GPT 和块设备只读访问。启动前提、自动 reset 行为与限制见
[固件说明](../../pkgs/u-boot/sm8650/README.md)。已安装 EFI 到 Linux 交接通过；
将独立 recovery 保留在 `recovery_b`，通过[检查式安装流程](../u-boot-install.md)写入
`boot_b`，保留 A。单独 RAM 实验无需先改 userdata 分区。

## RAM 启动前提

保留原厂 A 槽，实验仅使用 B。另行备份设备特有的校准/NV 数据和 `dtbo_b`，
确认原厂镜像和进入 bootloader 的方式可用。原厂 DTBO 引用下游 DT 节点，无法直接
用于主线 DT。若 `dtbo_b` 已全零，无需写入。完成上文底包准备后，RAM 测试阶段不要擦除 `dtbo_a` 或再次执行原厂刷机脚本。

部分 bootloader 版本（例如 Android 16 底包 OS3.0.7.0.WNACNXM）在 `fastboot boot`
期间仍校验活动槽实体分区的 AVB 链。因此即使上传成功，空的 `boot_b` 也会因 AVB footer/header
无效而触发回退 A，Linux 尚未开始运行。遇到此情况，在原厂 Android 读取
`/dev/logfs/UefiLog*.txt` 确认。B 槽需要可用的校验配置；仅更换 RAM 镜像无法
补齐实体分区缺失的校验元数据。bootloader 已解锁时，仅将 `vbmeta_b` 的
verification-disabled 标志设为 2 即可通过认证，`vbmeta_system_a/b` 无需修改。
使用对应版本的原厂 `vbmeta.img` 作为恢复来源，写入后核验实际标志再重试。
fastboot 标准选项是与 `flash` 配合的 `--disable-verification`，并没有独立的
`disable-verify` 命令。目标分区必须明确带 `_b`。

此模式下 ABL 也会拒绝 OS version 为零的镜像。模块通过
`androidDevices.boot.android.osVersion` 和 `osPatchLevel` 提供与原厂 boot
一致的 14.0.0 / 2026-02-01 元数据，可在要求的 Android 14 底层启动；它不是要求底包的安全补丁日期，也不是 recovery
的操作系统版本。DT 导出符号表及 `arch_timer` 标签，供固件 hypervisor overlay
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
recovery prepare-install --check
recovery prepare-install --confirm-erase-userdata
```

第二条命令**不保留 Android userdata 数据**：将原 userdata 分配约一半
留给 Android，另一半分成 1 GiB FAT32 `linux-boot` 和 ext4 `linux`。
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
数据库及 EFI 文件后最后写入 boot_b。固件启用 ACM 后不再倒计时等待，直接从
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

完整 recovery 采用 [Rust daemon、UI 与交互 shell](../../pkgs/mobile-recovery-screen/daemon.md)。
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

首次准备 B 槽时，使用下方命令明确刷入配套原厂包的 `imagefv_b`，此后 NixOS
更新应保留它。不能因 Android A 槽正常就假定 B 槽该分区已有有效固件。
即使 `boot_b` 已安装 U-Boot，它仍参与原厂启动显示路径。该分区为空时，原厂 fastboot 与 U-Boot/EFI 都可能实屏黑屏，
但 USB 和帧缓冲渲染正常。此时 Android A 槽仍可正常显示，因此应对比启动固件
实际使用的槽位，不能只按前一个运行的系统判断原因。

出现此症状时，先检查原厂 UEFI 日志（root Android 下的 `/dev/logfs`）。
已确认的故障会出现 `pil-imagefv Failed to load metadata`，以及长度为零的
`logo.img`。先核对 `imagefv_b` 与原厂镜像，再考虑面板退出时序、tty或重启模式。
确认该分区异常后，仅用 **OS1.0.3.0.UNACNXM** 对应镜像恢复 B 分区，
不要执行原厂全刷脚本：

```sh
fastboot -s SERIAL flash imagefv_b /path/to/aurora_images_OS1.0.3.0.UNACNXM_14.0/images/imagefv.elf
fastboot -s SERIAL set_active b
fastboot -s SERIAL reboot bootloader
```

对应 `imagefv.elf` 为6,299,448字节，SHA-256：
`96d1f21d8c2802c6144832ab9117e6fd4bf9df01647298befb2449090e577d00`。
恢复后验证 B 槽 fastboot 显示，以及 Linux 重启到 bootloader 的完整流程。
此修复无需擦除 `misc` 或修改 Android A 槽。

## 硬件参考

[硬件支持、已验证范围与驱动实现](hardware.zh.md)；
[固件来源](firmware.zh.md)、[连接与设备身份](connectivity.zh.md)、[音频与校准](audio.zh.md)。
