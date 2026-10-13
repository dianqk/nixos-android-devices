# Clover 内核

[English](PATCHES.md) · [Clover 指南](../../../../docs/clover/README.zh.md)

补丁集以 Linux 7.3-rc6 为目标。见[共享内核说明](../../README.zh.md)。

`devices.clover.kernel` 补丁集以 Linux 7.3-rc6 为目标，按顺序应用的
[补丁列表](series.nix)，从 x86_64 跨平台构建到 AArch64。正式系统和 RAM recovery
使用此内核；尚未在设备上启动验证。

在 x86_64 主机上通过仓库的跨平台包作用域构建：

```console
nix build .#devices.clover.kernel --out-link result-kernel
```

每条补丁保留原作者、日期、提交说明和 trailers；`Source-Commit` 与 `Scope`
标明来源和适用范围：

| 补丁 | 范围 | 用途 |
| --- | --- | --- |
| 0001–0004 | SDM630/660 或 PM660 通用 | PM660 燃料计节点及音频编解码器、时钟节点 |
| 0005–0006 | Clover LTE 专用 | 板级 binding 和设备树 |
| 0007–0009 | PMI8998 PMIC 通用 | 燃料计驱动与 binding |
| 0010–0011 | 面板通用 | Clover 使用的 NT51021 驱动与 binding |
| 0012–0013 | SDM660/SDM630 通用 | MSS、MDP5 SMMU identity domain |
| 0014–0017 | WLED/ath10k 共享驱动 | IRQ 平衡、密钥响应、WCN3990 VHT 位掩码及初始 IRQ 状态修正 |
| 0018–0025 | SDM630/660 GPU 通用 | GPU 时钟切换、OPP/速度分档、SDM660 标称频率上限及两条本地修正 |
| 0026 | SDM630/660 音频通用 | q6afe 时钟和 AFE 端口所需的 APR 音频 protection domain |
| 0027–0028 | ath10k 共享驱动 | WCN3990 分段 A-MSDU 接收状态及 RFC v3 修正 |

0016 使用 Polaris 7.3 的 WCN3990 修正。0017、0024、0025 是独立的本地修正。
0028 防止 0027 空列表解引用，并保留 7.3 的恢复行为。对 7.3 已有文件仅应用差异
片段；新增文件保留来源信息。Clover 充电上限保持基线值，更高上限尚无热控制验证。
Qualcomm Sensor Manager 尚不可用：固件包未提供 `qcom/sensors/sns.reg`，
传感器用户态路径也未验证。

PMI8998 燃料计源码仍有后备充电状态判断、notifier 错误分支和
卸载清理问题。GPU 时钟代码有一段不起作用的频率范围处理；固定 OPP 路径已
编译，实际调频仍需设备验证。ath10k 密钥响应修改需要通过断开、重连测试。
目前没有设备运行验证。

内核构建 `sdm660-xiaomi-clover.dtb`。配置保留 MSM DRM、NT51021、Qualcomm
固件辅助驱动、USB host/role switching、外接 USB 设备和内建 microSD 路径，
供正式系统及 RAM recovery 使用。

内核补丁遵循上游 Linux GPL-2.0 条款及被修改文件中的许可证声明。
