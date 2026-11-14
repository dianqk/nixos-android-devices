# 小米 12S Pro 内核支持

[English](PATCHES.md) · [设备指南](../../../../docs/unicorn/README.zh.md)

队列对应仓库锁定的 Linux 7.3.4。[`series.nix`](series.nix) 导入
[SM8475 公共队列](../README.zh.md)、选定的子系统修复及 Unicorn 驱动。
[`config.nix`](config.nix) 在 `kernel.config`、公共策略及 SoC 配置之上设置板级覆盖。

| 范围 | 实现 |
| --- | --- |
| 平台 | 共用 TLMM、SoC 描述、UBWC 与 GCC 电源管理；板级时钟、PHY 及 GPU OPP |
| UFS | 共用父时钟、OPP、RCG、Hibern8 修复；SM8475 低 gear 初始化及控制器时序 |
| USB | PTN3222 eUSB2 repeater、PMIC GLINK/UCSI、DWC3 角色切换、xHCI 与 USB Audio |
| 显示/GPU | A730 匹配及共用 GMU 集成；L2S 1440×3200 DSC 面板，24/30/40/60/90/120 Hz 六档，默认 60 Hz |
| 触摸 | ST FingerTipS SPI 多点触摸 |
| DSP/电池 | ADSP/SLPI 服务及板级电池消息布局 |
| 无线 | WLAN/蓝牙外部电源时序、PCIe SID 映射及 UART 接入 |
| 音频 | WCD938x、AudioReach 共享内存端点、96 kHz TDM、CS35L41；SoundWire 端口/恢复及 400 kHz 功放 I2C |
| 相机 | CAMSS、独立 CSI2 PHY、CCI、PM8008；S5KJN1 超广角/长焦及 OV32B40 前摄原生 RAW10 链路 |
| 其他 | SN NCI 正常读卡、AW86927 力反馈、红外、板级供电及温控 |

`panel.patch` 包含最终面板与 DRM 运行时集成：固定每通道带宽、原厂命令流、
活动模式切换及面板空闲事务。后两项需显式开启，不宣称通用 VRR。
`dpu-disabled-commit.patch` 避免对关闭的编码器读取 CTL；
`dpu-debugfs-state-lock.patch` 为 CRTC debugfs 读取加锁。

相机包含 Linux 提交 `067c5c24cef23d913b67eaaf71ae67e7169a6620` 的独立
CSI PHY 接口及查找依赖，回调使用锁定内核的 API。Asphalt 保留集成 CSIPHY，
两套相机实现独立选择。传感器来源与采集限制见[相机指南](../../../../docs/unicorn/camera.zh.md)。

## 配置与固件

存储、USB 管理、显示和触摸内置，供无模块 RAM recovery 使用；音频、DSP、
无线、相机、NFC、振动及红外使用模块。已安装系统与 recovery 共用一个内核。

设备模块通过 `hardware.firmware` 提供 GPU、DSP 与无线固件，initrd 包含
GPU/PAS 文件。扬声器固件、系数、校准与 Music 参数为私有运行时输入，
缺失或无效时保留驱动保护检查。配置与当前实机支持见
[设备指南](../../../../docs/unicorn/README.zh.md)。IMX707 及完整模拟耳机路由尚未支持。

## 构建

```sh
nix build .#devices.unicorn.kernel
nix build .#devices.unicorn.recovery
```

构建器在 `olddefconfig` 后核验覆盖项。通过 `tools/kernel-queue.py --help`
查看队列导入及独立核验方法。修改 SM8475 平台补丁后应检查 Unicorn、Asphalt
两套队列及构建。构建成功不代表已通过实机验收。内核文件保留版权和 SPDX 声明。
