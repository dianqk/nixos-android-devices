# Dodge 音频

[English](audio.md)

已安装 Dodge 模块启用 AudioReach 和 WCD9395 codec，用于内置麦克风和 USB-C 模拟
耳机。两个 Awinic PID `0x2308` 放大器使用 Secondary MI2S data line 1 驱动扬声器。
临时驱动 compatible 为 `awinic,aw882308`；出厂 A1901 固件将它们标为 **AW88461**。

扬声器支持为实验性。驱动强制至少 30.1 dB 硬件衰减，并要求本板的 OEM Music 寄存器
表。未实现 OEM HAL/ADSP 扬声器校准和动态保护；音量上限不能替代该保护。不写 OTP
或持久校准。内置扬声器播放可用；麦克风和模拟耳机行为尚未验证。

`hardware.dodge.audio.enable` 对已安装系统默认 true，对 RAM recovery 默认 false。
默认[固件归档](firmware.zh.md)包含两张 OEM Music 寄存器表、AudioReach topology
和 UCM profile。自定义 `hardware.dodge.firmwareSource` 必须使用相同的 Linux
payload 布局，包括 `lib/firmware/qcom/sm8750/oneplus/dodge` 和 `share/alsa/ucm2`。
固件包的 `audio` 属性指向其单一共享输出。

正常启动运行 `dodge-audio.service`：通过 FastRPC 创建静态 audio PD，等待 listener
初始化，然后加载 AudioReach 服务。UCM 在用到时选择扬声器、耳机和麦克风路由；禁用
的扬声器路由会静音两个放大器。WirePlumber 以 30% 音量启动新播放路由；保存的用户
音量仍然有效，但受硬件上限约束。

不播放/录音，仅检查初始化：

```sh
systemctl status dodge-audio.service
journalctl -b -u dodge-audio.service
cat /proc/asound/cards
aplay -l
arecord -l
wpctl status
```

codec 连线和初始 AudioReach/UCM 数据来自
[Omarchy Mobile 的 Dodge 音频支持](https://github.com/derekross/omarchy-mobile/tree/10daa3dabd1cd7b629bed58c41f32b389efb6e1e/device/dodge/audio)
及其[内核支持](https://github.com/mrlund/linux-omarchy-mobile/tree/6cc4b65df980355e00417df3d4b7b8109e7d0d21)。
ACF 解析器检查 [OnePlus OEM 驱动](https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8750/tree/d50b305f7da9e14715a25120a4ac7b1a4b8b97c3/vendor/oplus/kernel/audio/codecs/aw882xx)
记录的格式。
