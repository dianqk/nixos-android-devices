# 配置自己的系统

设备专属选项统一使用 `hardware.{asphalt,polaris,sheng,aurora,clover}.*`；
共享的启动、USB、recovery 等选项使用 `androidDevices.*`。

[English](configuration.md) · [安装指南](README.zh.md) · [USB 连接](usb-signaller.zh.md)

构建电脑需要 Linux 和启用 flakes 的 Nix。`buildSystem` 填电脑的架构：
`x86_64-linux` 或 `aarch64-linux`；五款设备的目标架构都是 AArch64。
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
2. 为每台设备设置独有且稳定的 `androidDevices.usbSerial`。
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
`device` 支持 `asphalt`、`polaris`、`sheng`、`aurora`、`clover`；`modules` 中放自己的
NixOS 模块。可选参数 `specialArgs`、`overlays`、`nixpkgsConfig` 分别传递模块参数、
包覆盖和 Nixpkgs 配置。

| 模块提供的默认值 | Asphalt | Polaris | Sheng | Aurora | Clover LTE |
| --- | --- | --- | --- | --- | --- |
| 安装系统启动方式 | U-Boot/EFI | U-Boot/EFI | U-Boot/EFI | U-Boot/EFI | U-Boot/EFI |
| 根 GPT 分区 | `linux` | `userdata` | `linux` | `linux` | `userdata` |
| ext4 默认标签 | `NIXOS` | `NIXOS` | `NIXOS` | `NIXOS` | `NIXOS` |
| 选择 NCM 后的 USB 地址 | `172.16.43.1/24` | `172.16.42.1/24` | `172.16.45.1/24` | `172.16.42.1/24`（共享默认值） | `172.16.44.1/24` |

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
androidDevices.usbSerial = "my-polaris-01";
```

其他设备将 `polaris` 替换为 `asphalt`、`sheng`、`aurora` 或 `clover`。无需额外导入
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
| 未设置 USB serial | 在共享设备配置中填写 `androidDevices.usbSerial` |
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
