# T880 Wi-Fi

[English](wifi.md) · [T880 指南](README.zh.md)

T880 的 Wi-Fi（MT6897 connsys 与 MT6637 射频）使用 MediaTek connsys 驱动，针对设备内核以树外方式构建（`devices.t880.connectivity-modules`）：conninfra、connfem、wmt_chrdev_wifi 和 gen4m Wi-Fi 驱动。`wlan0` 由使用 iwd 后端的 NetworkManager 管理。

## 配置

`nixosModules.t880` 在已安装系统上启用 `hardware.t880.connectivity`。`t880-wifi` 服务在启动时：

1. 加载驱动模块；
2. 写入 Android `nvdata` 分区中的本机校准数据；
3. 在 NetworkManager 和 iwd 启动前打开 Wi-Fi。

`nvdata` 中保存 `APCFG/APRDEB/WIFI` NVRAM 记录，其中包括 MAC 地址。服务会先把块设备设为只读，再以只读方式挂载。

Wi-Fi 固件本身由 bootloader 从 `connsys_wifi_<slot>` 加载。驱动还会读取 Android vendor 分区（`/vendor/firmware`）中的两个原厂配置文件：`conninfra.cfg` 和 `connfem.cfg`。这些文件是专有文件，本项目不提供。可以用以下两种方式之一提供：

- **把固件目录作为软件包使用。** 原厂 Android 14 文件的布局为 `wifi/{SHA256SUMS,conninfra.cfg,connfem.cfg,...}`（以及 `bluetooth/...`）。把该目录传给固件包，并允许这个 unfree 软件包：

  ```nix
  hardware.t880.connectivity.firmwarePackage =
    androidPackages.devices.t880.firmware.override {
      # 布局相同的目录，或一个发布归档：
      firmware-source = androidPackages.mkFirmwareArchive {
        name = "t880-firmware-source";
        url = "https://example.org/t880-firmware.tar.zst"; # 根目录：wifi/、bluetooth/、SHA256SUMS
        hash = "sha256-…";
      };
    };
  ```

- **放在设备上的目录中。** 把文件复制到 `hardware.t880.connectivity.firmwareDirectory`（默认 `/var/lib/android-devices/t880-firmware`），服务会把它们链接到 `/lib/firmware`。

未配置固件时，该服务会被跳过。

## 添加连接

凭据不属于系统配置，在运行时添加网络：

```sh
nmcli device wifi connect <SSID> --ask
```

如果不想把密码保存在 NetworkManager 的配置中，可以把密钥设为由 agent 持有，并在连接时提供：

```sh
nmcli connection add type wifi ifname wlan0 con-name <name> ssid <SSID> \
  wifi-sec.key-mgmt wpa-psk wifi-sec.psk-flags 2
nmcli connection up <name> passwd-file <file>   # 802-11-wireless-security.psk:<密码>
```

iwd 仍会把每个已连接网络的密码写入 `/var/lib/iwd`。如果只想把它保存在内存中，可以在 `/var/lib/iwd` 挂载 tmpfs。

如需通过 Wi-Fi 使用 SSH，让 sshd 监听所有地址，并在 `wlan0` 上开放 22 端口：

```nix
services.openssh.listenAddresses = lib.mkForce [ ];
networking.firewall.interfaces.wlan0.allowedTCPPorts = [ 22 ];
```

## 状态与限制

- 已验证 5 GHz 802.11ax 的 station 模式（2x2，链路速率 1201 Mbit/s）。每次启动时，校准会在 Wi-Fi 第一次打开前运行一次。
- 管制域为默认的全球管制域，发射功率来自本机 NVRAM。
- 不启用蓝牙时，预校准只针对 Wi-Fi 运行（`conninfra.t880_precal_wait_bt=0`）。

## 蓝牙（实验性）

`hardware.t880.connectivity.bluetooth.enable = true;` 会加入 MediaTek `bt_drv` 驱动。
- 控制器注册到内核蓝牙协议栈，因此需要用 `hardware.bluetooth.enable` 启用 BlueZ。
- 蓝牙地址在启动时从本机 nvdata（`APCFG/APRDEB/BT_Addr`）读取，不会写入配置。
- 蓝牙会在 Wi-Fi 打开前完成注册，因此会运行原厂的蓝牙与 Wi-Fi 预校准。固件包必须包含 `bluetooth/` 中的文件（`BT_FW.cfg`）。

控制器会进入固件持有的空闲休眠状态，并为 HCI 流量唤醒。在 BlueZ 中关闭蓝牙会关闭蓝牙硬件，重新打开时 Wi-Fi 仍保持可用。更新时请移除自定义的 `t880_no_sleep` modprobe 设置；驱动不再提供此参数。

已测试：LE/BR 扫描、在 BlueZ 中反复开关、在 Wi-Fi 同时运行时的 L2CAP 数据传输（约 260 kB/s，l2ping 7–15 ms）。

## 故障排查

- `journalctl -u t880-wifi` 显示启动过程。出现 “missing ...” 表示固件文件不在配置所指的位置。
- `dmesg | grep -E "WIFI|wlan|conninfra"` 显示驱动侧信息。驱动默认只记录错误。
- 驱动运行时不能干净地重新加载。更换驱动模块后需要重启。
