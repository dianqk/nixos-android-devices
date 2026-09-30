# Y700 2023 内核补丁

[English](PATCHES.md) · [Y700 2023 指南](../../../../docs/asphalt/README.zh.md)

`asphalt` 内核使用锁定的 Nixpkgs 中的 Linux 7.3-rc5 源码。补丁顺序见
[`series.nix`](series.nix)，内核配置见 [`kernel.config`](kernel.config)。

| 补丁 | 适配领域 |
| --- | --- |
| 0001 | SM8475 基础支持 |
| 0002 | 显示、面板与背光 |
| 0003 | 触摸屏 |
| 0004 | PCIe 与 Wi-Fi |
| 0005 | UFS 时钟 |
| 0006 | Y700 2023 设备树 |
| 0007 | 视频编解码 |
| 0008 | USB 与音频连接 |
| 0009 | CS35L45 DSP 固件名称 |
| 0010 | QMP 硬件端口选择 |
| 0011 | 音频服务配置 |
| 0012 | SM8450 CAMSS |
| 0013 | 相机共享 RCG 时钟 |
| 0014 | WL2864C 稳压器 |
| 0015 | HI1339、S5K4H7 和 SC202CS 传感器 |
| 0016 | TB320FC 相机连接和微距 PHY lane 掩码 |
| 0017 | 相机 GDSC 寄存器保持 |
| 0018 | DisplayPort 连接、主 FSA4480 AUX 开关和 QMP DP 方向 |
| 0019 | DP debugfs connector 初始化 |
| 0020 | 保留引导程序已启用的 Lucid OLE PLL，修复显示交接 |

在 x86_64 或 AArch64 Linux 主机上运行 `nix build .#devices.asphalt.kernel`。在 x86_64
主机上，derivation 由 x86_64 运行并生成 AArch64 内核。Kbuild 使用
`ARCH=arm64`、AArch64 target prefix，以及来自 `buildPackages` 的 Clang/LLD；
不需要 AArch64 主机版 LLVM 工具。Linux 内核补丁遵循上游 GPL-2.0 条款及被修改文件中的 SPDX 声明。

## 相机来源

- 0012/0013 提取 Aaron Bockelie 的 SM8450 CAMSS 和 shared-RCG 内核补丁：
  [`d08afbea`](https://github.com/aaronsb/sm-x800-linux/commit/d08afbea7ba594092a104089aa5e124a91b06c7c)、
  [`04f99a72`](https://github.com/aaronsb/sm-x800-linux/commit/04f99a725bc63343683b54dea1aa8f698c4c3b13)。
  保留原作者、日期、提交说明及来源，仅提取打包提交中的相关内核差异。
- 0014 根据[厂商寄存器规格](https://www.ovt.com/wp-content/uploads/2022/09/OV-WL2864C-v2.pdf)
  实现 WL2864C 稳压器。
- 0015 提供 HI1339、S5K4H7、SC202CS 的全尺寸 RAW10 模式，使用 TB320FC
  的 24 MHz 配置。表中保留源文件哈希，补丁说明列出寄存器语义的 GPL 参考来源。
- 0016 配置实机供电、GPIO 和 CSI 连接，并保留单通道微距相机的 PHY 掩码；
  属于 0012 之后的本地适配。
- 0017 提取同作者 `04f99a72` 中的相机 GDSC 寄存器保留配置，与 TB320FC
  原厂设备树中全部九个 `qcom,retain-regs` 节点一致。

S5K4H7 控制寄存器语义也参考了 [MediaTek GPL 驱动（2019）](https://github.com/Samsung-MT6769-Devs/android_kernel_samsung_mt6768/blob/4e0fdc5e6f4c605813c569392f1c255ac4ef66ea/drivers/misc/mediatek/imgsensor/src/common/v1_1/s5k4h7_mipi_raw/s5k4h7mipiraw_Sensor.c)。
