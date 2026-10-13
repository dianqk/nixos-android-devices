# Sheng 内核

[English](PATCHES.md) · [Sheng 指南](../../../../docs/sheng/README.zh.md)

补丁集以 Linux 7.3-rc6 为目标；下文硬件结果基于此前的 7.3 内核取得。
见[共享内核说明](../../README.zh.md)。

`devices.sheng.kernel` 按顺序应用[补丁集](series.nix)；安装系统与 RAM recovery
使用同一个内核包。
该包使用 `config.aarch64`，构建 `sm8550-xiaomi-sheng.dtb`。

每个补丁标明来源提交及本地 7.3 适配；[ORIGINS.md](patches/ORIGINS.md)
保留原作者、日期、完整提交说明和 trailer。显示及 WCN7850 Wi-Fi 在安装系统中可用，其余外设限制见[硬件参考](../../../../docs/sheng/hardware.zh.md)。

[Lucid OLE 补丁](patches/upstream/0001-lucid-ole-preserve-enabled-pll.patch)
在显示时钟 RCG 切换到安全时钟源前，保留引导程序已启用的 PLL。
SM8550 使用同一 PLL 配置路径；关闭继承的时钟可能导致显示接管期间 MDP RCG 更新超时。
补丁原样保留作者及上游来源链接，不改变面板、DSI PLL 频率计算、DTB 或内核配置。
没有该补丁时，显示启动黑屏并出现 MDP RCG 更新超时。见[硬件状态](../../../../docs/sheng/hardware.zh.md)。

7.3-rc6 补丁集同样包含 Lucid OLE 保护及上游
[Qualcomm PCIe IOMMU 字段解析修复](../../patches/pcie-qcom-iommu-cells.patch)。
后者让 BDF-to-SID 表按提供方声明的字段数读取映射，避免以四字段步长错误解析
SM8550 正确的五字段映射。原补丁、作者、日期及 trailer 保持不变，仅补充来源 Link。
省略设备分支中恢复不规范映射的 revert。有了该修复，WCN7850 固件加载不再出现 BHI 超时。

上游提交 `58aeb412495a` 增大的 MAC 缓冲环会使 Sheng 固件出现 WMI 超时。
本地 [Sheng 固件兼容补丁](patches/7.3/0025-ath12k-sheng-mac-buffer-ring.patch)
仅让 Sheng 的 WCN7850（HMT.1.1.c2-00259 固件）保留 2048 个条目，
其他设备仍用上游 4096 默认值；较大的 RX release 环保持不变。
其余外设仍待验证，应保留可用的回退代。

在 x86_64 主机上，此输出使用 x86_64 构建平台、AArch64 目标平台。构建内核：

```sh
nix build .#devices.sheng.kernel --out-link result-kernel
```

7.3 补丁集包括当前配置需要的设备树、显示、输入、电池、音频、相机、Type-C、DP 和
WCN7850 及 FPC1553 指纹改动。指纹用户态需要 FPC1553 驱动和设备树节点。
其余外设仍需实机验证。

FPC1553 驱动有两处已知限制：prepare 先禁用再启用时不会重新启用已申请的 IRQ；
移除驱动时先释放资源、后移除 sysfs。两条路径尚未经 Sheng 实机验证。

内核补丁遵循上游 Linux GPL-2.0 条款及所改文件的许可证声明。

7.3 补丁集还与 Asphalt 共用 [Iris 解码顺序控制](../../patches/iris-hfi-gen2-decode-order.patch)
和[捕获缓冲池扩展](../../patches/iris-hfi-gen2-capture-pool.patch)：为同步 VA-API 客户端
提供 HFI gen2 零显示延迟控制及最多 64 个解码捕获缓冲。内容、作者及 trailer
原样保留自 Xilin Wu 在 [libva-v4l2 v1.0.0](https://github.com/radxa-pkg/libva-v4l2/tree/0e4ce1e05da1d0a92b342efc2090b9e4987035e1/patches)
中的补丁。这两项补丁不增加 10-bit 编码输入格式。

单 pdev 的频段范围修复与 Aurora 共享：
[ath12k-single-pdev-reg.patch](../../patches/ath12k-single-pdev-reg.patch)。
原 Sheng 补丁的代码改动保持不变，仅调整路径并补全来源信息。
它修正频段索引，并保留同时支持 6 GHz 的组合 radio 的 5 GHz 范围；
多 pdev 共享状态的竞争问题不在此补丁的解决范围。

## 同步状态

[共享 GMU 补丁组](../../patches/gmu-sync-state/README.md) 为 GMU 绑定驱动；`unused-crypto` 补丁禁用未使用的 QCE 节点（Linux 7.3 将该驱动标记为 BROKEN），使供应方 `sync_state()` 不再一直等待。
