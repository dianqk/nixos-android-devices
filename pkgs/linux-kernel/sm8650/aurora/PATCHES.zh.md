# Aurora 内核

[English](PATCHES.md) · [Aurora 指南](../../../../docs/aurora/README.zh.md)

`devices.aurora.kernel` 在 Linux 7.3-rc6 上按顺序应用补丁集。完整列表与顺序以
[`default.nix`](default.nix) 为准；共享补丁位于 [`../../patches`](../../patches)，
板级补丁位于本目录。基础配置为 Sheng 的 `config.aarch64`，再叠加通用裁剪、SM8650
要求以及 `default.nix` 中的 Aurora 覆盖。每个补丁保留原作者、提交说明及可用的上游
链接；本地适配在补丁中说明。另见[共享内核说明](../../README.zh.md)和
[硬件支持](../../../../docs/aurora/hardware.zh.md)。

| 领域 | 补丁 | 用途 |
| --- | --- | --- |
| 共享显示 | [DSC full ICH precision](../../patches/dpu-sm8650-dsc-full-ich-precision.patch), [DSC 1.2 RC model](../../patches/dsi-dsc-12-rc-model.patch), [first-line BPG offset](../../patches/dsi-dsc-12-first-line.patch) | N1 面板所需的 DSC 参数 |
| 共享 USB 与电源 | [NCM TX timer](../../patches/usb-ncm-retry-busy-timer.patch), [battmgr charge units](../../patches/qcom-battmgr-default-charge-unit.patch), [battmgr notification](../../patches/qcom-battmgr-serialize-notification-request.patch), [power-supply readiness](../../patches/power-supply-firmware-readiness.patch) | NCM 吞吐、ADSP 电池信息 |
| 板级 | `board.patch`, `n1-board.patch`, `keys.patch`, `power.patch`, `unused-crypto.patch`, `ufs-mcq.patch` | 板级 DT、DSI 面板连线、按键、ADSP 电池与 USB2 角色、禁用 QCE、UFS MCQ |
| 触控 | `touch.patch` | S3910P 原始 SPI 传输与连线 |
| GPU | `gpu.patch`, [GMU sync_state series](../../patches/gmu-sync-state/README.md) | Adreno 750 与原厂 ZAP 固件；GMU component 绑定 |
| 电池 | `battmgr-property-ids.patch` | Aurora 原厂 battmgr 属性 ID 与电流符号 |
| 音频 | [q6apm readiness](../../patches/q6apm-probe-readiness.patch), [CS35L43 codec](../../patches/cs35l43-codec.patch), [CS35L43 DAI clock](../../patches/cs35l43-dai-clock.patch), [legacy TDM endpoint](../../patches/audioreach-legacy-tdm.patch), `audio.patch`, `audio-codec-clock.patch` | WCD9395 与双 CS35L43 扬声器；见[音频](../../../../docs/aurora/audio.zh.md) |
| 视频 | `video.patch`, [HFI gen2 decode order](../../patches/iris-hfi-gen2-decode-order.patch), [HFI gen2 capture pool](../../patches/iris-hfi-gen2-capture-pool.patch) | Iris 与原厂 VPU33 固件、VA-API 所需支持 |
| Wi-Fi 与蓝牙 | `radio.patch`, `wifi-qmi-mlo.patch`, [ath12k single-pdev regulatory](../../patches/ath12k-single-pdev-reg.patch), [PCIe IOMMU cells](../../patches/pcie-qcom-iommu-cells.patch) | WCN7850 连线、原厂 Kiwi-v2 QMI 资源、5 GHz 范围、PCIe SID 解析 |
| 供电 | `optional-supplies.patch` | 显式获取可选的旧式供电（DRM、PCIe） |
| USB3 与 DP | `usb-dp.patch` | SuperSpeed、combo PHY、WCD9395 开关与 DP |
| N1 面板与扫描输出 | `n1-panel.patch`, `n1-transfer.patch`, `n1-120hz.patch`, `n1-30hz.patch`, `cmd-disabled-flush.patch`, `cmd-multirect.patch`, `cmd-tearcheck.patch`, `sm8650-mdss-identity.patch`, `lucid-ole-preserve-enabled-pll.patch` | N1 DSC command 模式面板 30/60/120 Hz、SM8650 command 扫描输出、显示接管 |
| 时钟 | `gcc-cx-binding.patch`, `gcc-cx-runtime-pm.patch`, `gcc-cx-domain.patch` | GCC GDSC 绑定到 RPMh CX 电源域（linux-next） |
| 基带 | `modem.patch`, [IPA v5.5 configuration](../../patches/ipa-v5.5-config.patch), [QRTR HELLO and announcement fixes](../../patches/qrtr-hello), [PAS exclusive-region reassignment](../../patches/pas-reassign-exclusive-regions.patch) | MPSS、IPA 与 rmtfs 内存；基带下行；服务通告；MPSS 重启不再导致手机复位。见[基带服务](../../../../docs/modem.zh.md) |

在 x86_64 或 AArch64 Linux 主机上构建：

```sh
nix build .#devices.aurora.kernel --out-link result-kernel
```

x86_64 构建使用 `buildPackages` 中的 Clang/LLD 生成 AArch64 内核。Linux 内核补丁遵循上游
GPL-2.0 条款及所修改文件的 SPDX 声明。
