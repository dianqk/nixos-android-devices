# 通过 USB 连接并更新系统

[配置系统](configuration.zh.md) · [安装路径](README.zh.md) · [English](usb-signaller.md)

<a id="enable-the-device-connection"></a>
## 启用设备连接

已安装系统默认使用 USB NCM 和 U-Boot/UEFI。启用 SSH 并配置公钥：

```nix
{
  androidDevices.usbSerial = "my-phone-01";
  androidDevices.usb.ssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY"
  ];
}
```

模块提供 USB NCM、管理链路上的 DHCP，以及绑定到 USB IPv4 地址的 SSH。SSH 默认
使用密钥；不会添加演示密码或用户。设备使用以下默认地址。如果与局域网/VPN 或
另一台已连接设备冲突，用 `androidDevices.usb.signaller.address` 覆盖。
USB 序列号决定 gadget 的 MAC 地址，应设为唯一值。

| 设备 | 设备 IPv4 地址 |
| --- | --- |
| Asphalt | `172.16.43.1/24` |
| Polaris | `172.16.42.1/24` |
| Sheng | `172.16.45.1/24` |
| Clover | `172.16.44.1/24` |

U-Boot 提供 ACM 控制台。RAM recovery 独立提供
[ACM/NCM 和 OpenSSH](recovery.zh.md)。已安装系统使用 NCM，示例中显式启用了可选的
ACM 登录控制台。正常启动的 initrd 默认不启用 USB 管理；usb-signaller 在 stage 2
启动。Recovery 直接在 initrd 中配置其 gadget，不运行 usb-signaller。可选的早期启动
ACM/NCM 使用 `initrdUsb`，并在 switch-root 前拆除其 gadget。USB 传输不负责选择
启动方式、准备存储或安装 U-Boot。
`androidDevices.usb.ssh.enable` 只配置 USB 访问；如需通过 Wi-Fi 或其他接口使用 SSH，
直接使用 `services.openssh` 并设置其监听和认证策略。

<a id="connect-from-the-computer"></a>
## 从电脑连接

连接支持数据传输的 USB 线。在电脑上用 DHCP 配置新出现的以太网接口。使用
NetworkManager 的电脑：

```sh
nmcli device status
# Replace USB_INTERFACE with the new USB Ethernet interface.
nmcli device connect USB_INTERFACE
ip -4 address show dev USB_INTERFACE
ssh root@172.16.42.1
```

电脑应获得同一子网内的地址（通常为 `.2`）。该链路不提供默认路由、DNS 或互联网
转发，因此电脑的正常网络连接不受影响。设备不需要桌面登录；NetworkManager 可以
独立于 networkd 管理的 USB 接口来管理 Wi-Fi。

SSH 失败时，从本地控制台或其他可用连接检查：

```sh
ip -4 address show usb0
systemctl status usb-signaller sshd.socket
journalctl -b -u usb-signaller -u sshd -u systemd-networkd
```

没有出现 USB 以太网接口，通常说明线缆、端口或 gadget/控制器有问题。有地址但无法
SSH 访问，则指向凭据、DHCP/路由或 SSH 配置。已安装系统无法启动时，RAM recovery
仍是备用手段。Asphalt 和 Polaris 的 NCM/SSH 更新已通过硬件验证。Sheng 使用 7.3
内核，已通过已安装 B 槽位 U-Boot/EFI Linux、NCM/SSH 和 Wi-Fi 验证。Asphalt 各接口
的支持情况不同，见其[硬件说明](asphalt/hardware.zh.md)。

<a id="optional-acm-console"></a>
## 可选 ACM 控制台

设置 `androidDevices.usb.acm.enable = true;`，在开发者模式下与 NCM 一同提供 ACM
串口登录控制台。默认为 `false`；公开 USB 示例显式启用了它。内核必须包含
`USB_CONFIGFS_ACM`。在电脑上通过 `/dev/serial/by-id/` 下以设备序列号命名的链接连接。
gadget 端口出现后，`serial-getty@ttyGS0` 启动一个后台等待程序。它读取所选控制器的
状态，不打开或重置 TTY，并在 USB 枚举达到 `configured` 后运行 getty。这表示 USB
已完成配置，不一定表示电脑上的程序已打开该串口。等待不会推迟启动或本地登录。
断开连接会挂断串口会话；重启后的服务会再次等待枚举。

登录行为遵循你配置的 getty/登录策略；模块不创建用户、密码或 root 自动登录。公开
桌面示例只在本地 tty1 自动登录 demo；ACM 控制台显示普通登录提示。最小实验示例
保留其显式的 root 自动登录策略。

ACM 不能替代 NCM 或 SSH，启动也不会等待电脑打开它。仅充电/主机模式下 ACM 消失，
回到开发者模式后恢复。U-Boot 的 ACM 是独立的控制台，在交给 Linux 时结束；已安装
系统会重新枚举自己的 USB gadget。RAM recovery 使用独立的
`androidDevices.initrdUsb.acm.enable` 设置。

如需不使用 socket 激活的 SSH，设置 `services.openssh.startWhenNeeded = false;`。
修改 USB 或唯一的 SSH 监听时，保留另一条已建立的管理通道，直到**新**连接成功。
激活命令执行成功本身不能证明替换后的监听可以访问。

<a id="standard-updates"></a>
## 标准更新

电脑获得 NCM 地址并可通过 SSH 访问后，设备就是普通的 NixOS 远程目标。假设你的
flake 导出 `nixosConfigurations.phone`：

```sh
nixos-rebuild boot --flake .#phone --target-host root@172.16.42.1
ssh root@172.16.42.1 systemctl reboot
```

`switch` 也可用于立即激活。更新 USB 守护进程、网络、SSH 或其配置时，优先使用
`boot` 后重启：`switch` 期间重启传输可能断开客户端。修改管理传输时保持 Wi-Fi SSH
可用。根据目标架构使用合适的原生、交叉或远程构建机进行构建。

标准安装器更新 store、系统 profile、EFI 内核/initrd/DTB，以及 FAT `/boot` 上的
系统代条目。普通更新不会刷写 U-Boot 或 recovery。传输完成与激活/启动成功需分别
检查。initrd 进入紧急模式时，仍需使用本地/U-Boot 控制台或独立 recovery；该后端
有意不为正常 initrd 添加网络。

<a id="modes-and-peripherals"></a>
## 模式与外设

支持的模式为 `developer_mode`、`charging_only` 和 `host_mode`。MTP、网络共享和
大容量存储未提供，因为这里没有配置相应的服务和策略。USB 角色切换默认仅限 root；
普通用户可以通过系统总线查询守护进程。

要让指定用户无需 `sudo` 或 polkit 提示即可切换模式，指定一个控制组并将这些用户
加入其中：

```nix
{
  androidDevices.usb.signaller.controlGroup = "usb-mode";
  users.users.alice.extraGroups = [ "usb-mode" ];
}
```

模块会创建该组，并添加 D-Bus 规则，只允许其成员调用 `set_mode`；守护进程总线名
的所有权和其他方法仍仅限 root。usb-signaller 自身不检查调用者，因此 D-Bus 策略
就是全部授权。**风险：**任何成员都可以在无提示的情况下切换到 `charging_only` 或
`host_mode`，立即断开 USB 网络、ACM 控制台以及经 USB 的所有 SSH 会话。只添加本来
就可以管理该设备的用户，并保留另一条管理通道（Wi-Fi SSH 或本地控制台），以便
切回 `developer_mode`。默认值 `null` 不添加组或规则。组成员身份在用户下次登录时生效。

```sh
busctl call com.meego.usb_moded /com/meego/usb_moded com.meego.usb_moded get_modes
busctl call com.meego.usb_moded /com/meego/usb_moded com.meego.usb_moded mode_request
# These disconnect USB networking; issue them locally or through Wi-Fi SSH.
# Members of controlGroup may omit sudo.
sudo busctl call com.meego.usb_moded /com/meego/usb_moded com.meego.usb_moded set_mode s host_mode
sudo busctl call com.meego.usb_moded /com/meego/usb_moded com.meego.usb_moded set_mode s developer_mode
```

| 连接对象 | 所需行为与其余边界 |
| --- | --- |
| 电脑 | 设备角色 + NCM 提供 DHCP 和已配置的 SSH。 |
| 鼠标/键盘 | 主机/VBUS 通路正常时，由标准 USB HID 和桌面输入栈处理。usb-signaller 不提供供电或输入驱动。 |
| U 盘/读卡器 | 主机/VBUS 以及 USB Storage/UAS/SCSI 提供块设备。挂载和文件系统权限属于普通操作系统/桌面策略；这个最小 Niri 示例没有自动挂载界面。 |
| 显示器/扩展坞 | USB-C DP 需要实际的 DP 走线、CC/PD、方向/mux/PHY 和 DRM 支持，再加上合成器的输出策略。仅写入数据角色无法启用 DP。DisplayLink 是独立的 USB 图形通路。 |

usb-signaller 监视 Type-C 事件，但本集成未实现自动主机策略或桌面模式选择对话框。
接线完整的内核 connector 驱动可能已经提供自动角色切换；不完整的端口仍需要板级
CC/VBUS/角色/mux 工作。未实现多接口仲裁。仅完成驱动配置不等于实际外设测试。


软件包补丁和上游细节记录在[软件包说明](../pkgs/usb-signaller/README.md)中。
