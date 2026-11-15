# Aurora 传感器集成

[English](sensors.md)

Aurora 固件包的 `sensors` 输出使用
[固件发布归档](firmware.zh.md#固件来源)中 `sensors/` 的原厂数据。
它要求中国版 OS3.0.308.0.WNACNXM（Android 16），与 ADSP 固件的底包
相同。其中包含 67 个原厂配置文件和 10 个 Hexagon DSP 文件；不包含任何逐机校准数据
或 Android 守护进程。

`sensors/SHA256SUMS` 校验未经修改的文件。
配置的选择遵循 `/odm/etc/sensors/config/json.lst` 中 MTP / SoC 557 的条目。该原厂
列表还列出了三个并不存在的副 SAR 文件（`sm8650_sx937x_1.json`、`sx937x_1.json`、
`sx937x_reg_1.json`），这些文件已省略。vendor 与 ODM 中重复的 CHRE 配置仅在平台
选择器上不同；所选的传感器值一致，保留 ODM 副本。

通用 registry 生成器使用 `file-group` 布局：文件名包含来源 JSON 文件名，
`parsed_file_list.csv` 为这些记录建立索引，`config/json.lst` 列出所选的配置文件。
Aurora 固件通过 `/odm/etc/sensors` 打开后者；缺少该路径可能在
`sns_registry_sensor.c` 中触发断言并使 ADSP 崩溃。模块提供显式的绑定路径，而不是
创建全局的 Android 文件系统链接。

LSM6DSO 加速度计/陀螺仪在 SSC 内使用原厂方向（+Y, +X, -Z）。共享的
libssc/SensorProxy 集成使用由此得到的 Android 设备坐标；不额外应用 Sheng 的安装
矩阵。出厂偏置因机而异：应私下保留在可写的 Linux registry 中，切勿把某一台手机的
校准数据作为板级默认值分发。升级时不会重新填充已有的 Linux 状态；规范化会保留
JSON 值和固件的 `DIR` 标记。

`sensors` 输出与固件的 `out` 相互独立；RAM recovery 不会启动监听器，也不包含这些
传感器数据文件。
