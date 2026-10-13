# Polaris Linux 内核

[English](PATCHES.md) · [Polaris 设备索引](../../../../docs/polaris/README.zh.md)

补丁集以 Linux 7.3-rc6 为目标；本设备的硬件结果基于此前的 7.x 内核取得。
见[共享内核说明](../../README.zh.md)。

内核包使用已锁定 Nixpkgs 输入中的 `linuxPackages_testing.kernel`，目标版本为
Linux 7.3-rc6。[`series.nix`](series.nix)按应用顺序列出启用的补丁。
构建结果包含 `qcom/sdm845-xiaomi-polaris.dtb` 和使用 LLVM 23 构建的
Android 兼容 `Image.gz`。

PCM v2 使用 S16_LE，或以 S32_LE 容器存放高位对齐的 24 位采样。
q6asm 对齐补丁正确声明该格式及 24 位有效数据。

相机使用 SDM845 社区提交
[`dbc31cca7`](https://gitlab.com/sdm845-mainline/linux/-/commit/dbc31cca7cadbb97c2bee0ff7c8a3f86a7b25273)
的 IMX363 驱动与上游 OV5675 驱动。IMX363 导入补丁仅为 Linux 7.3
刷新 Kconfig 和 Makefile 上下文，新增代码保持不变。本地补丁在探测时保持 IMX363 复位，
控制 Polaris 模组使能 GPIO，传递时钟启动错误，并将前置与后置主摄接入 CAMSS。
供电和 GPIO 对应小米的
[量产板覆盖配置](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/blob/polaris-o-oss/arch/arm64/boot/dts/qcom/polaris-p1-camera-sensor-mtp.dtsi)
与[基础相机描述](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/blob/polaris-o-oss/arch/arm64/boot/dts/qcom/polaris-camera-sensor-mtp.dtsi)。

MDSS 启动电源域补丁来自 Dmitry Baryshkov 的
[上游提交](https://lore.kernel.org/r/20260217-sdm845-hdk-v1-1-866f1965fef7@oss.qualcomm.com)。
保留原作者、日期、说明及签署／审阅信息，代码未修改，仅补充来源 `Link`。
该补丁允许 bootloader 开启的显示电源域在 Linux 初始化前正常断电。

本地 clock orphan 补丁在仅补齐时钟树关系时不强制开启空闲父时钟，保留
prepared/critical 引用迁移及运行时实际切换行为。依据
[Stephen Boyd 的注册阶段修复讨论](https://www.mail-archive.com/linux-kernel@vger.kernel.org/msg1630217.html)
和 [Jerome Brunet 的引用迁移补充](https://lkml.rescloud.iu.edu/1802.0/03657.html)，
当前实现为本地修改，并非直接收录这两份原补丁。

QRTR nameserver 补丁保留了 [Takashi Iwai 的 HELLO 提案](https://lore.kernel.org/all/878q55sfxo.wl-tiwai@suse.de/)
中的 `ns.c` 部分，保留原作者和提交说明，并明确记录部分导入的差异。
另一份本地补丁在端点锁内合并重复 HELLO，保留主动握手，并确保先发 HELLO 再公告服务。两份补丁现位于共享目录 `pkgs/linux-kernel/patches/qrtr-hello/`，Aurora 也使用它们。
这两项修改针对 Polaris 的 SMD 初次启动；MHI 挂起恢复及任意传输错误恢复不在已验证范围内。

## 导入的社区补丁

这些补丁保留原始邮件头和提交说明。

| 补丁 | 原作者 | 来源提交 |
| --- | --- | --- |
| `0001-nt35596s-panel.patch` | Arnaud Ferraris | [`3b0c2c8d57`](https://gitlab.com/sdm845-mainline/linux/-/commit/3b0c2c8d5707d5fb41fbfe1cb17ec09c87fe35a5) |
| `0002-pmi8998-fuel-gauge.patch` | Joel Selvaraj | [`dad5ba4bf9`](https://gitlab.com/sdm845-mainline/linux/-/commit/dad5ba4bf9651fbab6b4e69b51f0fd85808d4dcd) |
| `0003-tas2559-codec.patch` | Joel Selvaraj | [`15a2625230`](https://gitlab.com/sdm845-mainline/linux/-/commit/15a2625230216f9911fa29837620d87a8ede7532) |
| `0004-pmi8998-fg-binding.patch` | Yassine Oudjana | [`b2ac93767d`](https://gitlab.com/sdm845-mainline/linux/-/commit/b2ac93767db99546c1a82a2da1876c69e0e3b351) |
| `0005-pmi8998-fg-node.patch` | dianqk | [`8189a12c5e`](https://gitlab.com/sdm845-mainline/linux/-/commit/8189a12c5e03972ff5b5f194d332d42c31affc06) |
| `0006-ath10k-split-amsdu.patch` | Richard Acayan | [`2fc5766fb5`](https://gitlab.com/sdm845-mainline/linux/-/commit/2fc5766fb5a281b61d03ae5786b23c7795af87b0) |
| `0016-imx363-sensor.patch` | Joel Selvaraj | [`dbc31cca7c`](https://gitlab.com/sdm845-mainline/linux/-/commit/dbc31cca7cadbb97c2bee0ff7c8a3f86a7b25273) |

- `0023-polaris-ramoops.patch` 将保留原作者信息的小米 SDM845 下游 ramoops
  保留区（`0xb0000000`，4 MiB）移植到 Polaris，保留记录布局并包含正常关机
  转储。实机已在单独停止 modem 引发复位后读回 pmsg 标记及复位前控制台日志；
  该补丁补齐取证能力，尚未修复关机故障。

- `0024-polaris-rmtfs-guards.patch` 使用当前 `qcom,use-guard-pages` 绑定移植
  Caleb Connolly 的 [SDM845 RMTFS 保护页修复](https://github.com/torvalds/linux/commit/e60fd5ac1f6851be5b2c042b39584bfcf8a66f57)。
  扩大的保留区仍提供 `0xf6301000`／`0x200000` 的有效载荷；Polaris 下游也要求
  此保护。单独加入保护页未解决停止 modem 导致的整机复位。
- `0025-polaris-ipa.patch` 恢复上游 IPA 节点，配合内建驱动与早期 IPA 固件。
  未初始化 IPA 时，modem 接受关闭请求后等待确认超时，随后手机复位；初始化
  IPA 后，modem 返回关闭确认并完成资源回收，多次单独停止／启动测试通过。
  尚不能确定具体依赖 IPA 的哪项硬件或握手功能，也不代表完整手机断电已验证。

## 同步状态

[共享 GMU 补丁组](../../patches/gmu-sync-state/README.md) 为 GMU 绑定驱动；`unused-crypto` 补丁禁用未使用的 QCE 节点（Linux 7.3 将该驱动标记为 BROKEN），使供应方 `sync_state()` 不再一直等待。
