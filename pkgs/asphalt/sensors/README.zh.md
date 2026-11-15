# TB320FC SLPI 传感器数据

[English](README.md)

来自 Lenovo ZUI 17.0.339（TB320FC，SM8475）的 OEM 固件和通用 vendor 默认值。
SLPI 使用 `slpi.mdt` 和实际 ELF 段；本安装没有 `slpi.b22`。Hexagon 库和
`fastrpc_shell_2` 位于 `dsp/`。不包含 Android ARM64 daemon/属性库和每机校准。
二进制来自每设备 `firmware` release 归档，不在本 Git 树中。这些 OEM 资产没有
附带开源许可证。

子集匹配 `hw_platform=MTP`、`soc_id=531`：50 个 JSON 文件。仅规范化行尾和行尾
空白；原始 SHA256 记录在 `SOURCE-SHA256SUMS`。二进制未修改。共享构建器合并
相同默认值，生成带版本 7 标记的 329 个组。BMI3x0 方向为 (-x,+y,-z)。默认值
还覆盖 MMC56x3x 磁力计、STK3A5x 光线/距离和 SSC 算法。不导出每机校准。

配置和验证限制见[传感器文档](../../../docs/sensors.zh.md)。
