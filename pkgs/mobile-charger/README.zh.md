# 移动充电显示

[English](README.md)

`mobile-charger` 在专用的 RAM-only 充电 initramfs 中运行，使用 Linux VT/fbcon
控制台、evdev 以及板级配置提供的显式 power-supply provider。

居中界面根据可见 framebuffer 像素和面板物理尺寸计算位图控制台字体，至少容纳
40×32 字符单元。物理元数据无效时回退到像素几何。板级配置可覆盖物理尺寸或字体
宽度（高度为宽度两倍）。Polaris 在 1080×2160、68×136 mm 面板上使用 24×48 像素
（45×45 单元）；Asphalt 在 1600×2560 面板上保留显式 32×64 字体（50×40 单元）。
它复用并缩放内核字体，不需要字体文件或渲染库；只写入变化的字符区间。界面显示
大号电池百分比、状态和 USB 输入电压/电流/功率。功率由输入侧电压和电流计算；
不把电池 `power_now`、PD 合同上限或充电器标称功率当作输入功率。未知读数使用
占位符。输入电流和计算功率需要有效输入电压；特别是驱动在 Full 时返回零电压/
电流并不表示零消耗。充电状态/健康可来自与电池容量不同的 provider。程序从不写
充电上限、充电使能或电池旁路设置。

- 短按电源键切换 framebuffer 控制台输出和背光。
- 按住两秒请求普通重启到固件启动路径。
- 20 秒无交互后自动熄屏。
- 独立进程即使在显示卡住时也监控外部电源。确认移除五秒后关机；恢复供电会取消
  待关机。启动时的零读数在任一监控进程观察到在线供电前保持未知；该就绪锁在
  进程间共享。
- 电源状态或必要的显示/输入硬件缺失 30 秒会关机。启动时已按住的按键在释放前
  被忽略。

运行控制器需要精确的内核参数 `android_charger=1`；它不是桌面应用。它假设充电
initramfs 不挂载持久文件系统，并有 PID1 supervisor 在控制器失败时关机。

在发起主机上构建并生成预览：

```sh
nix build .#mobile-charger-host
mkdir -p tmp/preview
result/bin/mobile-charger --preview tmp/preview/charger.txt charging
```

可在末尾追加 `COLUMNS ROWS` 预览不同网格，例如
`--preview tmp/preview/polaris.txt charging 45 45`。

预览场景为 `charging`、`full` 和 `unknown`；数字仅作示意。文本输出使用与设备
相同的单元布局；物理屏幕上 `#` 单元为白色实心块。

原生构建运行控制器/遥测测试，以及延迟短按、长按和 evdev 同步丢失的真实事件队列
测试。实际 framebuffer 面板电源、固件遥测、重启和拔电行为仍需板级硬件验证。
熄屏不表示系统 suspend 或 Android 等效充电策略已启用。
