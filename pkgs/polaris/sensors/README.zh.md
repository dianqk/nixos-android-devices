# Mi MIX 2S SLPI 传感器数据

[English](README.md)

通用 JSON 来自
[TheMuppets/proprietary_vendor_xiaomi_polaris](https://github.com/TheMuppets/proprietary_vendor_xiaomi_polaris/tree/9e9707959acceea4b990cba733d259aab64c183e/proprietary/vendor/etc/sensors)
的 `9e9707959acceea4b990cba733d259aab64c183e`（LineageOS 22.2）。`POLARIS`/`321`
选择包含 33 个文件。仅规范化行尾和行尾空白；原始哈希在 `SOURCE-SHA256SUMS`。
构建器生成带版本 2 标记的 125 个组，ICM206xx 方向为 (-x,-y,+z)。保留 BH1745、
AK991x、气压/距离默认值和算法。不包含每机校准。

SLPI 固件和 PD 描述来自每设备固件归档（源仓库 MollySophia/firmware-xiaomi-polaris 的 `d88ffb2`）。这些 OEM 资产没有附带开源
许可证。离线选择不能证明与某台手机的固件或物理屏幕坐标兼容。

配置和验证限制见[传感器文档](../../../docs/sensors.zh.md)。
