# Aurora 触摸运行时

[English](README.md)

默认由 S3910P 控制器固件计算触点（TouchCom touch report 0x11），`aurora-tcm`
内核驱动将其报告为 `Xiaomi 14 Ultra Touchscreen` 多点触控设备：10 个触点的
type-B slot，轴 0..1439 和 0..3199，touch major/minor 来自报告宽度，压力来自
报告 Z。不需要 OEM 库、固件归档输入或用户空间服务；任何具有预期 TouchCom 协议、
型号和几何的控制器固件都可接受，驱动会记录构建和配置 ID。报告选择是运行时状态，
在每次 reset、power-on 和面板唤醒后重新应用；驱动从不写控制器 flash 或配置。
Recovery 不加载该驱动。禁用触摸：`hardware.aurora.touch.enable = false`。

```sh
sudo evtest /dev/input/aurora-touch
sudo libinput debug-events --device /dev/input/aurora-touch
```

## 用户空间主机处理器（实验性）

设置 `hardware.aurora.touch.hostProcessor.enable = true` 改为在用户空间从原始帧
计算触点。可单独构建：`nix build .#devices.aurora.touch`。内核随后启用 vendor
raw frame（0xc0，模块参数 `primary_report=0xc0 disable_report=0`），通过
`/dev/aurora-touch-raw` 暴露，而不注册自己的输入设备；这个单线程适配器只执行
OEM 库的核心计算路径，然后通过 uinput 创建 `Xiaomi 14 Ultra Touchscreen`。
输入轴为 0..143999 和 0..319999，匹配 Android 的 100 倍坐标精度。桌面 libinput
会归一化这些坐标；它们不是屏幕分辨率。

这是实验性兼容适配器，不是专有算法或完整 Android 运行时的重新实现。它需要
ARM64、4 KiB 页和精确的中国版 OS1.0.3.0.UNACNXM Android 14 控制器固件
（packrat 4337601，config N1CTE022）和库。所需 Android 16 基础使用控制器构建
4360960（config N1CTE034）和不同库，因此适配器在那里不工作；它只为旧基础保留，
需要来自该 release 的 `firmwareSource`。它不刷写控制器。OEM 输入来自
[Aurora 固件 release 归档](../../../docs/aurora/firmware.zh.md#固件来源)的
`touch/`，原样安装：

| 文件 | Android 路径 | SHA-256 |
| --- | --- | --- |
| libtouchreport.so | /odm/lib64/libtouchreport.so | 25354d7b53285a086e94d32543848f22e472cae958c65bdad0f5545e0a37947f |
| aurora_syna_thp_config.ini | /odm/firmware/aurora_syna_thp_config.ini | 125577bcf8e8816e7f425264a222a4488a5497ff7f1bd7fe200169908cfe20fd |

执行前检查两个哈希。OEM 文件为专有资产，权利归其所有者，不受源码许可证覆盖。
不捆绑手机校准或身份数据。源码来源见 [ORIGINS](ORIGINS.zh.md)。

## 熄屏触摸

Niri 等合成器会在任意触摸时唤醒 DPMS 关闭的显示。要让屏幕保持关闭直到其他输入
（电源、音量或键盘）唤醒：

```nix
hardware.aurora.touch.wakeDisplay = false;
# hardware.aurora.touch.displayConnector = "DSI-1"; # 默认面板连接器
```

内核驱动随后在面板关闭时关闭控制器（`aurora-tcm` 跟随 DRM 面板；`wakeDisplay = true`
时模块参数 `follow_panel=0` 保持其运行，使触摸能唤醒显示）并抬起所有触点。本节
其余部分适用于主机处理器。原始流在 panel-off 时带有 pause 记录；适配器释放触点，
不受 2 秒 stall 限制地等待，唤醒后再次跳过 OEM core 启动帧再报告。服务还把
`--display-dpms DSI-1` 作为后备门。适配器约每 100 ms 轮询
`/sys/class/drm/card*-DSI-1/dpms`，继续解码帧，但非 `On` 时不报告触点。转换前
报告的触点会释放；关闭期间存在的触点保持隐藏直到抬起，因此唤醒时按住的手指不会
点击。属性缺失、不明确或不可读时报告触摸并记录一次警告。

## 主机处理器诊断

```sh
systemctl status aurora-touch
journalctl -b -u aurora-touch
sudo evtest /dev/input/aurora-touch
sudo libinput debug-events --device /dev/input/aurora-touch
sudo libinput record /dev/input/aurora-touch > touch.yml
```

在消费配置中安装上游 `evtest` 和 `libinput`。使用主机处理器时，输入符号链接只在
服务运行时存在。验证移动、多触点、单独释放、边缘、旋转、熄屏唤醒和无自发触点。
仅成功空闲重放不能验证物理触摸精度、手势、掌拒、suspend 或触控笔。

传输只允许一个读取者。溢出、畸形帧、缺失序列和两秒 stall 会终止解码会话并销毁
虚拟输入设备，释放触点。systemd 以新状态重启处理器。间隙诊断包含传输和控制器
计数器以及内核采集间隔：传输计数器连续但控制器跳变说明丢失发生在用户空间队列
之前。专用触摸 IRQ 运行在 FIFO51，略高于 Linux 默认 IRQ FIFO50，防止饱和的
USB3 NCM 中断线程延迟控制器读取。SPI pump 和解码器保持普通调度。这不关闭帧
完整性检查。SPI 错误会有界退避地 reset/re-identify 控制器；共享 GENI 控制器
永不 unbind。前 100 帧初始化 OEM 算法后才报告触点。Suspend 会使流会话失效；完整
系统 suspend 仍未验证。

有界原始采集时，运行前停止服务，之后重新启动。采集可能包含触摸活动，只在有意时
分享。输出文件必须不存在。重放不会创建 uinput 设备。

```sh
p=$(readlink -f /run/current-system/sw/bin/aurora-touch)
d=${p%/bin/aurora-touch}/share/aurora-touch
sudo systemctl stop aurora-touch
sudo "$p" "$d/libtouchreport.so" "$d/aurora_syna_thp_config.ini" \
  --live /dev/aurora-touch-raw 10 /tmp/touch.htrf
sudo systemctl start aurora-touch
"$p" "$d/libtouchreport.so" "$d/aurora_syna_thp_config.ini" /tmp/touch.htrf
```

HTRF 记录包含 24 字节头（magic、LE32 sequence、LE64 monotonic 纳秒、LE16 payload
长度、六个保留零）和 1722 字节 payload。采集上限 4096 条记录；处理继续请求的
时间。调用库前验证原始帧 checksum、几何和扩展边界。只允许显式建模的 libc/math
导入。固定函数/数据地址特定于该固定二进制；只替换哈希不是库升级。
