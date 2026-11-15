# Dodge 触摸与显示唤醒

[English](touch.md)

让触摸不唤醒熄屏：

```nix
hardware.dodge.touch.wakeDisplay = false;
```

默认为 `true`。设为 `false` 时，触摸屏跟随其 DRM 面板，释放活动触点，并在面板
关闭时屏蔽中断、进入控制器 deep sleep。面板唤醒会在恢复上报前恢复正常感应。
键盘、鼠标和电源键处理不变。

读取 `/sys/bus/platform/devices/synaptics_tcm_hbp.0/panel_state` 可检查面板跟随、
控制器睡眠、中断状态、转换计数和最后一条命令错误。该设置控制显示唤醒；它不启用
系统 suspend，也不启用 suspend 期间的手势。
