# Android/NixOS 开发主机

[English](host.md)

在连接手机或平板的电脑上导入独立的主机模块。它不导入设备模块，也不选择内核、
引导程序、用户、SSH 密钥或网络后端。

```nix
{
  imports = [ inputs.androidDevices.nixosModules.host ];
  androidDevices.host = {
    enable = true;
    users = [ "developer" ]; # An existing local user; new groups need a new login.
    adb.extraDeviceIds = [ "18d1:d00d" ]; # Explicit USB permissions for this setup.
  };
}
```

<a id="tools"></a>
## 工具

| 类别 | 包含的工具 |
| --- | --- |
| 连接与部署 | `adb`、`fastboot`、现有的 `mobile-device`、OpenSSH、rsync、picocom |
| DTB 与检查 | dtc/fdtget/fdtput、file、jq、Python 3、strace、lsof、lsusb |
| 镜像（`imageTools.enable`） | U-Boot 工具、binutils、GPT/分区/文件系统工具、cpio 和常用压缩工具 |
| 网络检查（`networkTools.enable`） | iperf3、ethtool、tcpdump |

Android boot/AVB 和 sparse 镜像工具（`avbtool`、`mkbootimg`、`unpack_bootimg`、
`lpunpack`、`simg2img`）随 `android-tools` 提供。镜像/网络工具组默认启用；将任一
设为 false 可减小主机安装体积。`extraPackages` 用于扩充工具集。这些都是主机原生
软件包，在调试 AArch64 设备的 x86-64 工作站上也是如此。Python 安装在主机上；本模块
不会将其加入 recovery 或设备。内核编译仍在 `nix develop .#kernel` 中进行，见
[开发指南](development.zh.md)。现有带检查的刷写/部署流程见
[mobile-device](../pkgs/mobile-device/README.zh.md)。安装工具不会执行刷写、擦除、
分区或音频播放，也不启动测试服务。

<a id="acm-consoles-and-usb-networking"></a>
## ACM 控制台与 USB 网络

通过 `/dev/serial/by-id/` 选择控制台，并用
`picocom --baud 115200 --flow n /dev/serial/by-id/<console>` 显式打开。打开控制台
可能中断引导程序倒计时；不要无意中一直开着。`usb.consoleSerials` 只将列出的 USB
序列号字符串排除在 ModemManager 探测之外。上面列出的用户获得 `dialout` 和
`adbusers` 访问权限。额外的 `adb.extraDeviceIds` 为 vendor:product 对，将设备访问
权限授予该组和本地活动 seat 用户。不会安装全局可写的规则。USB 产品标签不能证明
设备身份。

在使用 NetworkManager 的主机上进行 NCM 管理：

```nix
{
  networking.networkmanager.enable = true;
  androidDevices.host.usb = {
    consoleSerials = [ "my-debug-device" ];
    networks.phone-usb = {
      mac = "02:00:00:00:00:01"; # Replace with the gadget's HOST-side MAC.
      uuid = "11111111-2222-3333-4444-555555555555"; # Choose a stable unique UUID.
      # address = "192.0.2.2/24"; # Optional host address; default uses gadget DHCP.
    };
  };
}
```

按 MAC 匹配，而不是使用随 USB 端口变化的接口名。这些 profile 是本地管理链路：
不提供默认路由，也不接受 gadget 下发的 DNS/额外路由，且在这些 profile 上禁用
IPv6。其他 USB 扩展坞和 Android 网络共享连接互不影响。核对 gadget 配置中的主机侧
MAC，保持主机与设备地址不同，并在 SSH 或 iperf3 测量前检查
`ip route get <device-address>`。经普通局域网路由的过期地址并不代表 USB 连接成功。

`adb.enable` 和 `usb.enable` 默认跟随顶层 `enable`，也可单独选择，用于只需连接、
不安装完整工具集的主机。USB profile 要求已启用 NetworkManager；本模块不会切换
主机的网络管理器，也不打开防火墙端口。SSH 别名、主机密钥、地址、设备清单和凭据
应放在使用者配置中。

<a id="usb-compatibility"></a>
## USB 兼容性

只对已确认存在电源管理问题的接口设置
`usb.disableAutosuspend = [ "vendor:product" ];`。它会添加针对性的 udev
power/control 规则、TLP 拒绝列表（不会启用 TLP），以及内核的 `k`（NO_LPM）USB
quirk。内核命令行在主机重启后生效。该设置默认为空，不会改变所有 USB 设备。

<a id="diagnosis-workflow"></a>
## 诊断流程

用 `adb -s <serial>` 或 `fastboot -s <serial>` 显式选择目标；写入前检查身份/槽位。
用 `lsusb -t` 和 `ethtool <interface>` 检查传输协商，用 `ip route get` 选择测量路径，
并双向运行 `iperf3`。只在需要时启动监听，并显式选择防火墙放行。`usbmon`/抓包需要
相应的主机权限；本模块不会在登录时启用抓包。

通过 SSH/ACM 收集设备日志（`journalctl -b`、`dmesg`、失败的系统/用户单元）。
GPU/视频测试（`vulkaninfo`、`vainfo`、ffmpeg/mpv）、输入/旋转检查以及
`bluetoothctl`/`btmon` 应在被测端运行。在工作站上安装这些工具无法验证手机的驱动。
在设备的系统配置中选择它们；不要为了与主机一致而向 RAM recovery 添加大型诊断栈。
OEM 备份和运行时采集数据应放在软件包源码之外，并在结果中记录底包固件版本。
