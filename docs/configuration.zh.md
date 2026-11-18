# 配置自己的系统

设备专属选项统一使用 `hardware.<device>.*`，设备为 `asphalt`、`polaris`、`sheng`、`aurora`、`clover`、`marble`、`t880`、`dodge` 和 `unicorn`；
共享的启动、USB、recovery 等选项使用 `androidDevices.*`。

[English](configuration.md) · [安装指南](README.zh.md) · [USB 连接](usb-signaller.zh.md)

构建电脑需要 Linux 和启用 flakes 的 Nix。`buildSystem` 填电脑的架构：
`x86_64-linux` 或 `aarch64-linux`；所有受支持设备的目标架构都是 AArch64。
x86_64 电脑对本仓库定义或修改的编译包使用交叉工具链；普通上游系统包保持
AArch64 原生，以复用其二进制缓存。

## 构建平台与远程构建机

| 任务 | AArch64 构建电脑 | x86_64 构建电脑 |
| --- | --- | --- |
| 仓库内核、U-Boot 和修改过的编译程序 | 原生编译 | 交叉编译 |
| 普通上游系统包 | 优先原生缓存，缺失则本机编译 | 优先同一份 ARM 原生缓存，缺失则本机 QEMU 编译 |
| 项目固件、脚本、预编译程序、initrd/boot/rootfs 镜像 | 本机打包 | 使用 x86_64 工具本机打包 |
| 上游 NixOS 生成的配置 | 本机 ARM 构建 | 本机 QEMU 构建 |
| Fastboot、内核开发工具 | 在发起电脑运行 | 在发起电脑运行 |

两个平台都可以在没有其他 ARM 电脑的情况下完成系统构建。在 x86_64 的
**NixOS 构建电脑**上加入并激活以下配置，再发起构建：

```nix
boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
nix.settings.builders-use-substitutes = false;
```

该选项同时注册 QEMU、向 Nix 声明可执行的 ARM 平台并配置沙箱访问。应配置在
构建电脑上，而非手机模块里。其他 Linux 发行版需要配置沙箱内可用的 AArch64
binfmt 解释器，并在 Nix daemon 配置中加入 `extra-platforms = aarch64-linux`；
单独设置 `extra-platforms` 不会安装模拟器。

```sh
nix build .#system --option builders-use-substitutes false \
  --out-link result-system
```

Nix 优先下载可用的 ARM 原生缓存，缺失的上游任务和 NixOS 生成配置可通过 QEMU
执行，速度可能较慢。本项目的打包步骤使用主机工具，不执行被打包的 ARM 程序；
其输入闭包仍可能含有需要模拟执行的 ARM 构建任务。设备脚本的解释器和运行库仍然
引用 ARM 包。本地源码按构建平台选择工具链，不假定原生和交叉编译缓存互通。

远程构建机仍可选。`builders-use-substitutes = false` 保持由发起主机下载缓存，
再向已配置的远程构建机传输输入；使用本机 QEMU 时不要清空 `extra-platforms`。

类似的“主机组装工具 + 目标包内容”见
[nix.dev 镜像示例](https://nix.dev/tutorials/nixos/building-and-running-docker-images.html)；
[NixOS binfmt 模块](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/system/boot/binfmt.nix)
负责模拟器注册和 Nix 平台、沙箱配置。

## 从完整 flake 开始

将[完整消费示例](../examples/consumer/flake.nix)复制到自己的配置目录，命名为
`flake.nix`。它只调用公开模块和库函数，不依赖上游 `examples/` 的内部路径。
安装前修改以下内容：

1. 将 `buildSystem` 设为构建电脑架构。
2. 可选设置 `androidDevices.usbSerial`。每个型号默认使用固定名称（`POLARIS`、
   `ASPHALT` 等；RAM recovery 中为 `RECOVERY_POLARIS` 等），仅在需要区分同型号的多台设备时覆盖。
3. 将自己的 SSH 公钥填入 `users.users.root.openssh.authorizedKeys.keys`。
   不填公钥时，默认控制台系统没有配置可用的登录凭据。
4. 对 Polaris，按[设备识别步骤](polaris/first-install.zh.md)核对原厂 GPT 分区名。
   Recovery 会在内置 UFS 上定位并检查根文件系统标签。逐机精确存储契约为可选项。
5. 后续升级时保留首次安装使用的 `system.stateVersion`。

使用 Git 管理配置时，先跟踪源文件：

```sh
git init
git add flake.nix
nix flake lock
nix eval .#nixosConfigurations.phone.config.system.build.toplevel.drvPath
nix build .#system -o result-system
nix build .#boot -o result-boot
nix build .#boot-files -o result-boot-files
nix build .#bootstrap-info -o result-bootstrap-info
nix build .#recovery -o result-recovery
```

以上只构建文件。各指南将输出链接命名为 `result-<role>`，也可使用其他路径，
保持一致即可。随后按[设备首装指南](README.zh.md)准备分区并安装；固件和
EFI 文件仅在相应步骤需要时构建。system 与 bootstrap-info 必须来自同一锁定配置。

## 额外的内核直启镜像（Sheng / Clover）

U-Boot 保持默认：`boot` 和 `u-boot` 仍输出 U-Boot 固件。已有安装可额外构建
`boot-kernel`，把 Linux、配套直启 initrd 和设备 DTB 打包为 Android boot 镜像：

```sh
nix build .#devices.sheng.boot-kernel --out-link result-boot-kernel
# Clover 将 sheng 换成 clover；只构建实际需要的设备。
```

以上是仓库示例。自己的配置通过 `lib.mkArtifacts` 获得 Sheng/Clover 的
`boot-kernel`，对应 `config.system.build.mobileDirectBootImage`。它与同一锁定
配置的 `system`、`bootstrap-info` 配套，固定启动该系统 closure，不跟随之后的
system profile 变化。启动前须将完整 closure 部署到现有 ext4 根分区，并在保留
备用镜像期间为其保留 GC root。仅构建镜像不会部署系统或在设备上注册 GC root。

镜像需要配置中的 ext4 根分区和 FAT `/boot`；其 initrd 选择匹配的系统闭包，
并拒绝启动未完成的部署。

只有显式安装到 boot 分区后才替代 U-Boot（Sheng 为 `boot_b`，保留 A；Clover
为 `boot`，无槽位）。不写 rootfs、EFI 文件或 recovery。设备支持时先验证 RAM
启动。Clover 使用带检查的 `mobile-device fastboot` 流程；若镜像或目标检查拒绝，
应调查原因，不能绕过。构建命令不执行刷机。

`nixos-rebuild boot` 继续维护 EFI generations，不更新已刷入的备用镜像。
更新备用系统需要另外重建、部署 `boot-kernel`；刷回配套 `u-boot` 即恢复 EFI
菜单启动。两款设备的内核直启均未真机验证。

## 选择设备和系统角色

`lib.mkSystem { device; buildSystem; modules; }` 返回标准 NixOS 配置。
`device` 支持 `asphalt`、`polaris`、`sheng`、`aurora`、`clover`、`marble`、`t880`、`dodge` 和 `unicorn`；`modules` 中放自己的
NixOS 模块。可选参数 `specialArgs`、`overlays`、`nixpkgsConfig` 分别传递模块参数、
包覆盖和 Nixpkgs 配置。

| 模块提供的默认值 | Asphalt | Polaris | Sheng | Aurora | Clover LTE |
| --- | --- | --- | --- | --- | --- |
| 安装系统启动方式 | U-Boot/EFI | U-Boot/EFI | U-Boot/EFI | U-Boot/EFI | U-Boot/EFI |
| 根 GPT 分区 | `linux` | `userdata` | `linux` | `linux` | `userdata` |
| ext4 默认标签 | `NIXOS` | `NIXOS` | `NIXOS` | `NIXOS` | `NIXOS` |
| 选择 NCM 后的 USB 地址 | `172.16.43.1/24` | `172.16.42.1/24` | `172.16.45.1/24` | `172.16.46.1/24` | `172.16.44.1/24` |

五台设备的 ext4 默认标签统一为 `NIXOS`。已有安装应保留与实际文件系统一致的
配置标签和 recovery 存储契约；修改默认值不会自动重命名文件系统。

设备模块提供硬件、持久系统默认值及 recovery 工具，不创建演示用户或选择桌面。
USB 序列号由调用方设置。将消费示例用于其他板时，修改 `device`，删除两行
`hardware.polaris.*.enable`，再填写该设备的存储身份。安装系统默认启用 NCM。
开启 `androidDevices.usb.ssh.enable` 并配置 SSH 密钥，即可远程访问。
系统 ACM 默认关闭，可用 `androidDevices.usb.acm.enable = true` 开启，仓库示例会显式开启。
U-Boot 使用 ACM，RAM recovery 在 initrd 中直接配置 ACM+NCM，不运行 usb-signaller。
正常启动的 initrd 默认不开启 USB 管理；进入 system 后才由 usb-signaller 提供 NCM/可选 ACM。
安装配置统一使用 EFI；首次安装前须准备并验证 FAT `/boot`。

在**单独的配置**中设置 `androidDevices.recovery.enable = true` 即可得到 RAM recovery。
两者共享硬件/存储身份，不把桌面、用户服务、安装系统的 USB SSH 配置导入 recovery。
recovery 使用 [ACM/NCM 和 OpenSSH](recovery.zh.md)，不启动磁盘中的系统。更改主机名时，在两份配置中设置相同的
`hardware.<device>.systemHostName`，以便 recovery 识别目标系统。

已有构建框架也可直接导入 `nixosModules.<device>`，配合
`lib.mkBuildEnvironment { buildSystem; overlays; config; }.nixosSystem`。
每个设备模块都导入并启用标准通用支持和对应板级支持，例如：

```nix
imports = [ inputs.androidDevices.nixosModules.polaris ];
```

其他设备将 `polaris` 替换为 `asphalt`、`sheng`、`aurora`、`clover`、`marble`、`t880`、`dodge` 或 `unicorn`。无需额外导入
通用模块，也无需设置 `androidDevices.enable = true`。
桌面策略及逐机身份由使用者提供。

## 添加桌面和服务

桌面、用户、认证和通用系统精简使用标准 NixOS 配置。公共设备模块不导出桌面策略
或通用 minimal 系统模块。消费示例直接导入 Nixpkgs 的 `profiles/minimal.nix`；
可以删除该导入，也可以继续添加服务。

例如，在自己的安装系统中添加 Niri/Foot：

```nix
{
  users.users.alice = {
    isNormalUser = true;
    initialPassword = "change-before-use"; # 也可使用 hashedPasswordFile。
    extraGroups = [ "video" "input" "render" ];
  };
  programs.niri.enable = true;
  programs.foot.enable = true;
}
```

在本地 tty 登录后运行 `niri-session`。输出、按键、终端和自启动由自己的
配置管理。[桌面示例](../examples/desktop.nix)演示完整会话、显式的演示用户自动登录，
以及始终显示在底部并预留屏幕空间的 wvkbd 虚拟键盘。
复制需要的部分并自行修改，不把它作为上游模块接口导入。示例通过 `NIRI_CONFIG`
选择 `/etc/niri/config.kdl`，由 demo 的 tty1 登录启动 `niri-session`。
`demo` 使用 UID 1001，让全新安装的个人用户可使用 UID 1000。从旧版示例安装
切换时，需要单独检查现有账户 UID 和文件所有权。
示例文件中的 `example.desktop.scale` 设置内屏缩放，它不是导出的硬件模块选项。
Niri 使用默认屏幕方向；示例不添加输出 transform、旋转 metadata 覆盖或自动旋转
客户端。传感器支持仍可用于诊断或显式配置的旋转策略。触摸屏映射到 `DSI-1`，
窗口使用无间距的全宽列，
保留 wvkbd 的屏幕空间。Super+Return 打开终端，Super+左右切换列，Super+上下切换
工作区，Super+O 打开概览，Super+Q 关闭窗口，Super+Shift+E 退出会话。Print 截图；
需要指定保存路径时运行 `niri msg action screenshot-screen --path /tmp/screen.png`。
其他桌面同样使用标准
NixOS 模块。面板旋转、缩放和 UI 偏好属于具体会话配置。

Polaris 的 `hardware.polaris.radio.enable` 和 `hardware.polaris.audio.enable`
默认均为 `true`，消费示例为了控制台用途关闭两者。后续添加 Wi-Fi/音频时删除关闭
设置，按[设备说明](polaris/README.zh.md)配置无线身份，再启用 NetworkManager、
PipeWire 等服务即可，无需禁用或重新导入内部文件。音频与无线按需共享 DSP 服务。
其他设备保留各自的硬件默认值；传感器、指纹等可选功能见对应设备说明。

所有设备（包括 Polaris/Asphalt）默认使用上游 FFmpeg。
`androidDevices.video.ffmpegPackage` 仍可覆盖；[裁剪后的本地 H.264/HEVC 配置](video.zh.md)
及设备 V4L2 修复仅在诊断或专用本地媒体构建中按需选择。
蓝牙、PipeWire、Wi-Fi 凭据、用户、软件包及应用服务继续使用标准 NixOS 选项。

需要相机 CLI 时，在接收 `config` 的模块中设置
`environment.systemPackages = [ config.androidDevices.camera.package ];`，得到包含设备传感器
适配的 libcamera。运行 `cam --list` 查看摄像头；拍摄参数及限制见对应板的硬件参考。

## 挂起唤醒源

设备模块可在 `androidDevices.power.wakeup.sources` 中声明具名唤醒源（每个源是一组
sysfs 设备路径）；名称与已验证的唤醒行为见各设备的硬件说明。该策略默认关闭。
使用时启用并列出要保留的源：

```nix
androidDevices.power.wakeup = {
  enable = true;
  keep = [ "powerKey" ];
};
```

此后其他所有设备的唤醒（`power/wakeup`）会在启动时、设备出现或绑定驱动时以及每次
系统休眠前被禁用；保留的源维持驱动自身的设置。可用
`grep -l enabled $(find /sys/devices -path '*/power/wakeup')` 和
`android-devices-wakeup-policy` 服务日志检查结果。系统是否以及何时挂起（systemd
休眠设置、空闲守护进程、菜单）仍由你自己的配置决定。

## 随屏幕方向切换扬声器声道

应用把左右声道发送到扬声器 sink，sink 总是在相同的物理扬声器上播放。旋转屏幕后，
左右声道可能来自错误的一侧。有多个扬声器的设备模块可在
`androidDevices.audio.orientation.routes.{normal,"90","180","270"}` 中按输出变换
描述 ALSA 混音器设置，使左右声道保持在对应的一侧。该策略默认关闭：

```nix
androidDevices.audio.orientation.enable = true;
```

启用后会安装 `/etc/android-audio-orientation.json`、`android-audio-orientation`
命令和同名用户服务。切换由你的合成器集成触发：在旋转处理程序中以桌面用户身份
用新的输出变换调用该命令：

```sh
android-audio-orientation apply 90
android-audio-orientation status
```

`apply` 先确认每个控件存在，然后只设置列出的控件，并将方向记录在
`$XDG_RUNTIME_DIR` 中。激活音频配置会重写这些控件，因此 WirePlumber 每次启动或
重启时，用户服务都会重新应用记录的方向（没有记录时为 `normal`）。翻转变换会镜像
画面，命令会拒绝它们，不应用任何声道设置。没有数据的方向保持当前声道不变。各方向
是否已验证见设备的硬件说明。

## 只读 RTC 的系统时钟

部分 PMIC RTC 在关机时持续计数，但 Linux 无法设置它，因此每次启动时钟都从 RTC 的
原始计数开始（例如 1970-01-10）。这类板的设备模块会启用
`androidDevices.clock.rtcOffset`（Aurora、Clover 和 Polaris；仅已安装系统），
像 Android 的时间守护进程一样在用户态保存偏移：

| 选项 | 默认值 | 含义 |
| --- | --- | --- |
| `enable` | `false` | 启动时用 RTC + 已保存偏移恢复时钟，并保存偏移。 |
| `rtc` | `"rtc0"` | RTC 类设备（`/sys/class/rtc/<rtc>`）。 |

`rtc-offset-restore.service` 在 `time-set.target` 和 systemd-timesyncd 之前运行：
把时钟设为 RTC 计数加已保存偏移，只向前调整，并创建 `/run/rtc-offset/restored`。
若保存时的 RTC 计数大于当前计数，说明 RTC 已复位，此时丢弃已保存的偏移，时钟等待
NTP。早于 2026-01-01 的结果会被拒绝。偏移（`/var/lib/rtc-offset/offset`：RTC
秒数和偏移秒数）在每次 systemd-timesyncd 同步后（`rtc-offset-save.path`）和关机时
（`rtc-offset-shutdown.service`）保存，且仅当本次启动的时钟已同步或已恢复时才保存。
安装后或 RTC 复位后的第一次启动仍需一次 NTP。可用
`journalctl -b -u rtc-offset-restore -u rtc-offset-save -u rtc-offset-shutdown`
检查。

Linux 能设置的 RTC（设备树节点带 `allow-set-time` 或 `offset` nvmem cell）不要
启用此功能；内核会自行保持时间。

## 实时任务的频率钳制

`androidDevices.power.rtUtilClampMin`（默认 `0`）在已安装系统中设置
`kernel.sched_util_clamp_min_rt_default`。内核默认值（1024）会让每次实时任务唤醒（例如线程化
的触摸中断）都运行在最高 CPU 频率，并通过 CPU 带宽投票在空闲时抬高 DDR 频率。Pixel 设备的
init 文件使用 0。设为 `null` 可保留内核默认值。

## 按温度限制充电电流

有些充电固件像 Android 的温控守护进程那样，把充电温控留给操作系统。
`androidDevices.charging.thermalLimit` 按温度写入充电电流上限。输入由设备模块提供；
Aurora 按原厂温控配置设置分级，以电池温度为传感器。该服务默认关闭：

| 选项 | 含义 |
| --- | --- |
| `enable` | 运行 `charge-thermal-limit.service`（默认 `false`）。 |
| `currentFile` | 以 µA 为单位的可写上限，例如 `constant_charge_current`。 |
| `sensors` | 温度文件及换算到 m°C 的系数；读数最高者决定上限。 |
| `steps` | `{ trip; clear; current; }`，trip 按 m°C 递增，上限单位为 µA。 |
| `defaultCurrent` | 低于第一级时以及服务停止后的上限。 |
| `interval`、`refreshPolls` | 轮询周期（5 秒）和未变化上限的重写周期（12 次轮询）。 |

某一级从其 trip 温度开始生效，直到温度低于其 clear 温度。没有可读传感器时使用最后
（最低）一级上限。可用 `journalctl -b -u charge-thermal-limit` 检查；依赖它之前，
先在充电时对比 `current_now` 与上限。


## 电池养护充电区间

`androidDevices.charging.window` 在插电时让电池保持在部分电量：充到上限后停止充电，低于下限
时恢复充电，期间设备由充电器供电。它使用电池标准的 `charge_control_start_threshold` 与
`charge_control_end_threshold`，由充电驱动执行。该策略默认关闭；T880 模块提供电池路径和
75/80 % 示例：

| 选项 | 含义 |
| --- | --- |
| `enable` | 运行 `charge-window.service`。 |
| `battery` | 电池的 power_supply 目录。 |
| `startThreshold`、`endThreshold` | 低于下限恢复充电、达到上限停止（默认 75 与 80 %）。 |
| `requestGroup` | 可请求一次性充满的用户组（默认 `users`）。 |

需要充满时（例如出行前）创建 `/run/charge-window/full-charge`（示例会话中为
`nexusctl battery full-charge`）。区间暂时取消，直到充电器报告充满或拔下充电器后恢复。
`/run/charge-window/state` 为 `window START END`、`full-charge` 或 `off`。停止该服务会取消区间（0/100 %）。

## 选择构建产物

`lib.mkArtifacts configuration` 返回：

| 属性 | 用途 |
| --- | --- |
| `system` | 完整系统闭包，即 `config.system.build.toplevel` |
| `bootstrap-info` | 与该系统匹配的闭包注册/首装元数据 |
| `boot` | Android 格式镜像；安装 EFI 系统时为 U-Boot，RAM recovery 时为 Linux |
| `kernel` | 设备内核包 |
| `rootfs` | 持久系统的可选 ext4 镜像；Polaris 的镜像 UUID 默认由 `androidDevices.usbSerial` 生成，与 recovery 首次安装无关 |
| `boot-files` | 初始 EFI 文件树，所有安装系统均提供 |

rootfs 镜像在已有分区内扩容，不是含 GPT 的整盘镜像。可设置 rootfs 的 `name`、
`label`、`padding`、`device`、`maximumBytes`。仅构建 system/bootstrap-info
不需要生成 rootfs 镜像；Polaris 首装器接收系统闭包和元数据，不能用 rootfs 镜像替代。

## 更新、恢复与排障

首次安装成功且 EFI 系统的 USB SSH 可用后，在构建电脑运行：

```sh
nixos-rebuild boot --flake .#phone --target-host root@172.16.42.1
ssh root@172.16.42.1 systemctl reboot
```

重启后检查 `readlink /run/current-system` 和本次修改的服务。修改 USB/SSH 时优先
使用 `boot`，避免切断正在使用的传输。启动失败时使用独立 RAM recovery，
具体操作见 [`mobile-device` 指南](../pkgs/mobile-device/README.zh.md)。

| 问题 | 检查方法 |
| --- | --- |
| 未知 `androidDevices.*` 选项 | 使用 `mkSystem` 或导入设备模块；新选项需要更新锁定的输入版本 |
| 同型号多台设备的 USB serial 和 MAC 相同 | 为每台设备设置不同的 `androidDevices.usbSerial` |
| 其他设备构建 rootfs 缺少 UUID | 设置 `androidDevices.persistentImage.rootfs.uuid` |
| 启动后没有桌面 | 设备模块不启动桌面；在自己的配置中设置并启动所选会话 |
| USB 可见但 SSH 失败 | 检查电脑 DHCP/地址、公钥及 `journalctl -u sshd -u usb-signaller`；见 USB 指南 |
| 存储契约不匹配 | 按实机重新检查布局并构建匹配 recovery，不跳过校验 |

## 存储配置的一致性

`androidDevices.persistentImage.rootfs.label` 是镜像、格式化与 recovery 共用的
文件系统标签配置，默认为 `NIXOS`。
`linux`、`userdata` 是 GPT 分区名，不是 ext4 标签。

Asphalt/Sheng 的系统与 recovery 应共用 `androidDevices.boot.uefi.espSizeBytes`：
默认 1073741824（1 GiB），可改为实际字节数，或设为 `null` 以接受已有 ESP 大小；
更新时仍检查可用空间。`androidDevices.recovery.minimumRootBytes` 默认
17179869184（16 GiB），可按系统闭包大小调整。Recovery 保留唯一分区角色、
控制器、类型、边界与非重叠检查，不限制 Linux 分区编号或 root/ESP 顺序。
原厂布局规划器仍保护其识别的 Android 分区前缀；其他布局须按实测 GPT 手动准备。
