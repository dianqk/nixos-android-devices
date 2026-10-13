# MIX 2S：关机充电

[设备指南](README.zh.md) · [English](charging.md)

Polaris 模块默认启用 `androidDevices.charger.enable`。构建
`nix build .#devices.polaris.charger`，或使用 `lib.mkArtifacts configuration`
的 `charger` 产物。先更新正常启动文件，将 `EFI/android-devices/charger.efi`
原子安装到物理 `system` 分区上的 FAT ESP；再按[检查式刷写流程](../../pkgs/mobile-device/README.zh.md)
更新非 A/B 的 `boot` 中的 U-Boot。保留独立 RAM recovery。日常系统更新不刷写 U-Boot。

启动分流精确匹配 ABL 的完整 `androidboot.mode=charger` 标记，不按 USB 在线状态判断。
普通启动仍进入 systemd-boot；充电镜像缺失或返回时请求关机，若关机失败则留在无倒计时菜单。
关闭镜像选项不会删除已安装文件或固件中的分流；删除镜像前应先调整固件策略。

专用内核/initramfs 全部运行于 RAM，不挂载持久分区。复用[通用 VT 控制器](../../pkgs/mobile-charger/README.md)，
设备模块提供 PMI8998 接口、按键、背光和物理尺寸。1080×2160、68×136 mm 内屏使用
24×48 字符，居中显示黑底白字的大号电量、电池进度条、状态和 USB 输入电压/电流/功率。
短按切换亮灭屏，20 秒自动熄屏；长按 2 秒重启至 systemd-boot。持续断电 5 秒关机，
期间恢复供电会取消关机。亮屏遥测每 5 秒更新，熄屏暂停；供电检测独立运行。

PMI8998 直接通过 SPMI 管理充电，不依赖 ADSP。充电专用 DT 禁用 ADSP、CDSP、SLPI、
MSS、WLAN、蓝牙和 IPA，正常系统保持自己的 DT 和服务。电量来自 `qcom-battery`，
状态/健康及输入测量来自 `pmi8998-charger`。驱动在 Full 等非 Charging 状态返回零电压、
零电流，界面显示未知，不解释成零功耗，也不以电池净电流或协商上限替代输入测量。

控制器不设置电流、电压、直通或输入暂停策略。主线 SMB2 驱动保留其原有默认值，包括
1 A 电池充电电流及按 USB 类型确定的输入上限；这不代表已经达到原厂 Android 的快充或热管理策略。
熄屏不等于系统休眠。调试时可设置 `androidDevices.charger.diagnostics = true`，
开启只读 USB ACM 日志，无 shell；默认关闭。

验证状态：本地控制器/UI 测试、两个构建平台的模块求值和共享 U-Boot 分流测试通过。
实机已确认文字清晰、短按亮灭屏、自动熄屏、短暂拔插不重启、持续断电关机、只插线进入
充电界面，以及长按经 systemd-boot 进入 Niri 示例系统。安装的正式镜像关闭 USB 调试。
接电关机后的 ABL 带有 charger 标记，普通软件重启时没有该标记。

较低电量时的输入电压、电流和功率仍需实机验证：此次电池接近满电，驱动报告 Full，
不提供这些测量值。显示初始化时已有的 WLED IRQ 警告尚未解决；亮灭屏测试通过不代表
已验证过压故障处理。独立的冷态电源键开机尚未测试，已验证的是充电环境长按重启路径。
