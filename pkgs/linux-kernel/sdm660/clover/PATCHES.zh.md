# Clover 内核

[English](PATCHES.md) · [Clover 指南](../../../../docs/clover/README.zh.md)

补丁集以 Linux 7.3 为目标。见[共享内核说明](../../README.zh.md)。

`devices.clover.kernel` 补丁集以 Linux 7.3 为目标，按顺序应用的
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
| 0030 | ath10k 共享驱动 | 断开关联时不重置 TxBF；重置会使 WCN3990 固件在每次断开时崩溃 |
| 0031–0032 | SDM630/660 通用 | CPU 空闲：移除每次请求都被 PSCI 拒绝的 cluster 空闲状态，并修正 CPU retention 参数，使空闲 CPU 进入睡眠而非反复重试 |
| 0033 | SDM630/660 通用 | 不在这些 SoC 上启用通用 cpufreq-dt 驱动 |
| 0034–0045 | SDM630/660 通用 | CPR3/CPRh 电压驱动及 SDM660 支持：按厂商方式计算开环 corner 电压，关闭闭环，仅支持速度分档 1、CPR 熔丝版本 2，另含四条本地修正 |
| 0046–0047 | OPP 共享核心 | 允许 CPU OPP 表的 debugfs 链接已存在，并释放已有链接的引用 |
| 0048–0052 | SDM630/660 通用 | 根据 CPRh corner 电压编程 OSM；SDM660 按厂商流程编程，并在域数量、OSM 已运行及错误路径上做本地修正 |
| 0053–0054 | SDM630/660 通用 | L2 SAW：silver 簇使用厂商 AVS 值，并保留引导固件设置的 SAW 控制寄存器 |
| 0055–0057 | SDM660 通用与 Clover | CPRh、OSM、L2 SAW、熔丝及 CPU 散热节点；Clover 的 corner 方案，先带频率上限，再启用完整频率表 |
| 0058–0060 | SDM630/660 通用 | CPRh 闭环：厂商方式的目标 quotient、debugfs 中只读的 CPRh 状态及闭环开关 |

0016 使用 Polaris 7.3 的 WCN3990 修正。0017、0024、0025 是独立的本地修正。
0028 防止 0027 空列表解引用，并保留 7.3 的恢复行为。对 7.3 已有文件仅应用差异
片段；新增文件保留来源信息。Clover 充电上限保持基线值，更高上限尚无热控制验证。
Qualcomm Sensor Manager 尚不可用：固件包未提供 `qcom/sensors/sns.reg`，
传感器用户态路径也未验证。

CPU 调频（0033–0060）按厂商内核的方式编程 CPRh 和 OSM。silver 簇在 300 MHz 至
1843.2 MHz 之间调频，gold 簇在 300 MHz 至 2208 MHz 之间调频；高于 872 mV APM
阈值（silver 1747.2 MHz、gold 1958.4 MHz 及以上）时存储阵列从 VDD_MX 切换到
APC 供电。开环模式（0033–0057）下每个频率使用熔丝给出的开环电压，所有频率的
时钟、供电电压和 APM 切换已在设备上核对。闭环模式（0058–0060）下 CPRh 按厂商
目标 quotient 将各 corner 电压从开环值向下限下调，尚未在设备上验证；单独回退
0060 即恢复开环。速度分档 1、CPR 熔丝版本 2 以外的
芯片保持引导程序设置的 CPU 时钟，CPR 驱动会记录原因。CPU 热区在 70 °C 被动
触发点限制所在簇的频率。

PMI8998 燃料计源码仍有后备充电状态判断、notifier 错误分支和
卸载清理问题。GPU 时钟代码有一段不起作用的频率范围处理；固定 OPP 路径已
编译，实际调频仍需设备验证。ath10k 密钥响应修改需要通过断开、重连测试。
目前没有设备运行验证。

内核构建 `sdm660-xiaomi-clover.dtb`。配置保留 MSM DRM、NT51021、Qualcomm
固件辅助驱动、USB host/role switching、外接 USB 设备和内建 microSD 路径，
供正式系统及 RAM recovery 使用。

内核补丁遵循上游 Linux GPL-2.0 条款及被修改文件中的许可证声明。
