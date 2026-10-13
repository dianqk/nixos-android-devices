# 模块边界

[English](modules.md)

使用者导入 `nixosModules.<device>`，在 `hardware.<device>.*` 下配置设备专属选项，
在 `androidDevices.*` 下配置共享功能，详见[配置指南](configuration.zh.md)。每个设备
导出都包含共享模块并启用其板级支持。`modules/` 下的内部路径属于实现细节，不供
使用者导入。

<a id="adding-or-maintaining-a-device"></a>
## 添加或维护设备

可复用的 NixOS 支持放在 `modules/mobile/`，硬件策略放在
`modules/devices/<device>/`。

共享模块不得查询设备代号、维护设备列表，或按设备系列选择行为。其输入在设备模块
中配置：

| 设备提供的输入 | 共享使用方 |
| --- | --- |
| 主机平台、主机名、控制台和平台内核参数 | NixOS 和 `base.nix` |
| 内核、固件和 `hardware.deviceTree.name` | 内核/initrd 和 UEFI 模块 |
| `boot.firmwarePackage` | 已安装系统的启动产物 |
| `boot.directKernel.enable` 和 `boot.android.*` | 可选的直接内核镜像和 RAM recovery 镜像 |
| `boot.uefi.device` 和 `boot.uefi.requireStandardEsp` | 启动分区挂载和安装器检查 |
| `persistentImage.rootfs.device` | 已安装的 ext4 根 |
| `usb.signaller.address`、`usb.signaller.controlGroup`、控制器和序列号 | USB 管理模块 |
| `recovery.targetHostName` 和 `recovery.daemon.*`（槽位模型、compatible、控制器、启动请求、存储角色、UFS 安全模式） | Recovery 守护进程配置 |

除标准 NixOS 选项外，表中的选项前缀都位于 `androidDevices` 下。
`hardware.<device>.systemHostName` 等设备专属选项只由该设备模块声明和使用，
由它将值显式传给网络和 recovery 配置。

`androidDevices.deviceName` 是产物/显示标签。共享模块可以将其用于文件名、标题和
recovery 身份标记，但不得用它选择软件包、分区或硬件策略。新设备不应需要在共享
模块中添加分支。

已安装系统通过 `boot.firmwarePackage` 提供 UEFI 固件镜像。RAM recovery 由提供的
内核和 Android 启动参数构造 Android boot 镜像，不需要固件包。补充的直接内核产物
由 `boot.directKernel.enable` 单独启用，在 recovery 配置中不存在。

`boot.uefi.requireStandardEsp` 默认为 true，此时检查标准 GPT ESP 类型、预期大小
和更新所需的剩余空间。现有 Polaris/Clover 模块将其设为 false，因为它们在物理
`system` 上保留厂商 GPT 类型；Asphalt 和 Sheng 保持标准 ESP 策略。两种模式都验证
`/boot` 为 FAT，且其挂载来源与配置的物理分区一致。关闭标准 ESP 检查是板级存储
决策，不是绕过安装失败的手段。修改前请先阅读各设备的安装指南。

共享硬件服务接受显式的设备输入。例如，[基带和 QTEE 模块](modem.zh.md)从设备模块
（`hardware.aurora.modem`、`hardware.polaris.radio`）获得 remoteproc 名称、NV 分区
或目录、启动方式和固件，而不是按设备名选择。

板级脚本与其设备模块放在一起；例如 Polaris UFS 安全模式脚本位于
`modules/devices/polaris/`。设备专属的软件包实现位于 `pkgs/`；这一边界并不意味着这些工具可以接受任意硬件。

<a id="validation"></a>
## 验证

`tests/mobile-module-boundary.nix` 只导入共享模块，并配置一个未注册的设备标签、
显式分区、DTB 和固件包。它在两种构建平台上检查标准/厂商 FAT 策略、直接内核选择、
recovery 输入以及缺少固件时的拒绝。其测试夹具仅用于求值，不是可启动镜像。

`tests/eval-platforms.nix` 覆盖五款受支持设备及其现有产物约定。修改公共选项或在
模块之间移动策略时，运行[开发指南](development.zh.md)中的检查。构建和硬件验证
独立于这些求值检查。
