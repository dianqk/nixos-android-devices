# Sheng 音频数据

[English](README.md)

Sheng 模块安装自己的 ALSA UCM 配置和选定设备固件，消费者不需要在单个应用中
设置 PulseAudio source 或 ALSA 设备号。

两个 Sheng UCM 文件保留 map220v 的作者头，并从
[ianchb/debian-sheng da1d2761](https://github.com/ianchb/debian-sheng/tree/da1d2761dbc1ccaea0122f8b0c2dce2d52edaeb2/alsa-xiaomi-sheng/usr/share/alsa/ucm2/Xiaomi/sheng)
原样复制。相对链接 `conf.d/sm8550/xiaomi-XiaomiPad6SPro12.4.conf` 匹配 ALSA
声卡长名称；原有 `Xiaomi-Pad6SPro.conf` 仍可用。社区配置保留六路 CS35L43 DSP
保护路径和 DisplayPort 路由，替代旧的本地路由补丁。

仅音频 topology 和六对 CS35L43 保护固件/系数来自
[ianchb/sheng-firmware 053da477](https://github.com/ianchb/sheng-firmware/tree/053da477a5c338ac28d7c1c869e8c3ff7ca24d11)；
每个文件有固定哈希。Wi-Fi、蓝牙、ADSP 和其他设备固件来自
`firmware-source.nix` 引用的每设备归档。打包文件不写入每机校准分区。

修改 topology 后重启到更新后的已安装系统。诊断应用麦克风前，先用 `wpctl status`
确认真实音频源和 HiFi profile。有界采集到 discard sink 只能证明流可用；扬声器
播放、声学质量和 DisplayPort 需要单独验证。

Linux 固件加载器会在所有搜索路径中先尝试未压缩文件，再尝试压缩文件。因此
`/lib/firmware` 下的旧未压缩 topology 可能遮蔽 Nix 固件目录中较新的 `.bin.zst`。
删除该遮蔽文件前先检查实际哈希并保留旧文件；本包不删除用户管理的固件。
