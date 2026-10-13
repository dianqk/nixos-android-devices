# Root TTY 示例

[English](minimal.md)

`examples/polaris/minimal.nix` 是一个独立的已安装 U-Boot/EFI 示例。它在控制台
自动以 root 登录，没有普通用户或图形会话，也不包含 Wi-Fi/蓝牙/音频用户态。
系统服务账户仍然保留。现有内核及其 USB 外设驱动保持不变。只包含显示固件。

usb-signaller 在启动时进入 NCM 开发者模式。networkd 为 USB 主机提供 DHCP；手机地址为
`172.16.42.1`。不需要 NetworkManager。自己的系统请使用
[使用者配置](../configuration.zh.md)，设置 `hardware.polaris.radio.enable = false`、
`hardware.polaris.audio.enable = false`，并启用 USB 网络/SSH。自行选择凭据，并配置
唯一的 USB 序列号。Recovery 在内置 UFS 上解析原厂 GPT 分区名并检查文件系统标签；
已安装系统和 recovery 配置应使用相同的根分区标签。
见[首次安装](first-install.zh.md)。

这个有意开放的实验示例在 `172.16.42.1` 上接受**空密码的 root SSH 登录**，不分发
个人密钥。SSH 只监听配置的 USB 地址，防火墙只在 `usb0` 上开放 22 端口。任何连接到
该 USB 管理链路的人都拥有 root 权限。用 `ssh root@172.16.42.1` 连接；客户端提示输入
密码时，提交空密码即可。桌面示例的仅密钥认证不受影响。

两种构建平台上都可用的软件包：

- `devices.polaris.minimal.system`：完整的系统闭包。
- `devices.polaris.minimal.bootstrap-info`：匹配的 recovery 注册信息和清单输入。
- `devices.polaris.minimal.rootfs`：ext4 `system.img`，首次启动时扩展。
- `devices.polaris.minimal.boot-files`：匹配的 EFI 文件，不是 FAT 分区镜像。
- 现有的 `devices.polaris.u-boot` 和 `devices.polaris.recovery` 提供固件和 RAM recovery。

构建系统和首次安装元数据：

```sh
nix build .#devices.polaris.minimal.system -o result-system
nix build .#devices.polaris.minimal.bootstrap-info -o result-bootstrap-info
```

对于自定义的 `nixosConfigurations.polaris-minimal`，通过 USB 更新：

```sh
nixos-rebuild boot --flake .#polaris-minimal --target-host root@172.16.42.1
ssh root@172.16.42.1 systemctl reboot
```

主机构建并传输缺失的 store 路径；手机保留 Nix 和 `switch-to-configuration`，用于
安装标准 EFI 系统代。手机上不包含 Nixpkgs 源码或本地重建工具。Recovery 的
`install-initial` 使用 system 和 bootstrap-info，`deploy` 则更新已有系统。这些
recovery 流程不使用 rootfs 镜像，也不需要单独下载 ESP。保留 RAM recovery，以应对
启动失败或 USB 配置出错。

## 安装后自定义

准备好所需分区后，匹配的 U-Boot + FAT ESP + 最小 ext4 根即可启动这个初始系统。
另外保留一个 recovery 镜像。小型 rootfs 在首次启动时于 userdata 内扩展；FAT 应使用
已准备好的完整 boot 分区，为将来的系统代留出空间。

之后可以将配置保存在电脑上，构建添加了用户、服务或桌面的新系统。将其导出为
`nixosConfigurations` 条目，并运行上面的 USB 更新命令。在该配置中保留 Polaris
设备模块、UEFI 存储路径、根文件系统身份和 USB 访问。普通的配置/内核更新只安装
系统代，不重新刷写根文件系统或 U-Boot。电脑必须提供适用于 AArch64 的原生、交叉或
远程构建机；最小系统手机不是构建工作站。

以后要在自己的配置中启用无线/音频，将相应的 `hardware.polaris.radio.enable` /
`hardware.polaris.audio.enable` 选项设为 `true`，提供无线身份数据，并配置常规
NixOS 服务。通用的控制台/桌面策略放在自己的模块中。不需要导入任何上游示例或
内部源文件。从这个有意无密码的实验镜像迁移时，确保保留你预期的 USB 认证策略。

配置回归检查（不写入设备）：

```sh
nix eval --json --impure --expr 'import ./tests/polaris-minimal.nix { flake = builtins.getFlake (toString ./.); }'
```
