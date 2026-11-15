# Dodge 传感器

[English](sensors.md)

`hardware.dodge.sensors.enable` 对已安装系统默认 true，对 RAM recovery 默认
false。它通过安全 ADSP FastRPC 设备启动 SSC sensor listener，并通过 IIO Sensor
Proxy 暴露传感器。加速度计样本可用；物理方向尚未验证。桌面 shell 自行配置旋转
策略。

Dodge [固件包](firmware.zh.md)在其单一输出中包含选定的 OEM registry 默认值和
DSP shim；`sensors` 别名指向该输出。自定义 `hardware.dodge.firmwareSource` 必须
包含 `etc/sensors`、`dsp` 和 `seed/registry`。

可写 registry 状态位于 `/var/lib/ssc-sensors`，可通过
`androidDevices.sensors.stateDirectory` 配置。目录不存在时用默认值播种；已有校准
保留。若有每机 OEM 校准，应在首次启动前私下提供，保留 `registry/registry` 组
布局、`registry/parsed_file_list.csv` 和 `registry/sns_reg_version`。不要把它放进
固件归档或 Nix store 输入。

检查启动并请求短加速度计流：

```sh
systemctl status android-ssc-sensors.service iio-sensor-proxy.service
journalctl -b -u android-ssc-sensors.service -u iio-sensor-proxy.service
ssccli --sensor accelerometer --timeout 3
monitor-sensor --accel
```

用 Ctrl+C 停止 `monitor-sensor` 以释放传感器占用。SSC 设备轴归一化后，提供的
传感器 mount matrix 是单位矩阵；不要再次应用 OEM BMI26x 轴映射。
