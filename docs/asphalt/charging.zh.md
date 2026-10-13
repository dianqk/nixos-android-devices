# Y700 2023：关机充电

[设备指南](README.zh.md) · [English](charging.md)

Asphalt 模块默认启用 `androidDevices.charger.enable`。仅插电启动时，ABL 的
`androidboot.mode=charger` 标记选择 ESP 上的 `EFI/android-devices/charger.efi`。
独立 Linux/initramfs 在 RAM 中运行，不挂载系统根分区或启动桌面。
正常按电源键开机仍进入 systemd-boot，包括已连接 USB 时。

## 构建与更新

```sh
nix build .#devices.asphalt.charger --out-link result-charger
```

自定义配置使用 `lib.mkArtifacts` 的 `charger` 输出。初装启动文件包含该镜像；
`nixos-rebuild boot` 会在 ESP 上原子替换它。**先安装启动文件，再按
[安装流程](../u-boot-install.zh.md)更新 `boot_b` 中的 U-Boot**。
正常系统更新不会刷写固件。保留 Android A、super 和独立 RAM recovery。

禁用 `androidDevices.charger.enable` 仅停止生成和更新镜像，不删除旧镜像，也不改变
已有固件的充电分流。应先调整固件策略，再删除文件。充电镜像缺失或执行返回时尝试
关机；失败则保留手动菜单，不自动启动 NixOS。充电与正常 EFI 启动均保留 B 槽确认检查。

## 操作与读数

- 短按电源键切换亮灭屏；无操作 20 秒自动熄屏。
- 长按电源键两秒，经正常启动链重启到 systemd-boot。
- 确认外部供电连续断开五秒后关机；恢复供电取消关机。独立监视进程处理界面卡顿。

1600×2560 竖屏 VT 界面显示电量、电池形进度条、充电状态和 USB 输入电压、电流、
功率。亮屏时每五秒更新读数，唤醒后立即刷新。熄屏时供电检测仍每秒查询并响应事件。
首次观察到在线供电前，初始零值视为未知；启动后 30 秒仍无有效状态则关机。

USB 输入功率是电压与电流的乘积，不是电池净充电功率或协商上限；不可用读数显示
占位符。程序不写入限流、限压、直通或输入暂停控制。满电时电池电流为零不能证明
原厂直通模式已生效。

## 调试与限制

`androidDevices.charger.diagnostics = true` 提供只读 USB ACM 内核及控制器日志，
不提供 shell，也不注册 USB 内核控制台，默认关闭。实现见
[充电控制器参考](../../pkgs/mobile-charger/README.md)。

已在连接 USB 主机时观察到插电进入、显示控制、断供处理及返回 NixOS 正常工作。
这不代表兼容所有充电器，也不代表已验证充电路径对未确认 B 槽的首次硬件确认。
充电由现有 ADSP 固件处理；Android 温控策略一致性、低电量快充和持续功耗尚未验证。
熄屏关闭背光及显示输出，未实现系统 suspend。正常 Linux 控制台接管时的短暂线条
花屏仍是已知问题，根因未确定。
