# Aurora 内核

[English](PATCHES.md) · [Aurora 指南](../../../../docs/aurora/README.zh.md)

`devices.aurora.kernel` 在 Linux 7.3 上按顺序应用补丁集。完整列表与顺序以
[`default.nix`](default.nix) 为准；共享补丁位于 [`../../patches`](../../patches)，
板级补丁位于本目录。基础配置为 Sheng 的 `config.aarch64`，再叠加通用裁剪、SM8650
要求以及 `default.nix` 中的 Aurora 覆盖。每个补丁保留原作者、提交说明及可用的上游
链接；本地适配在补丁中说明。另见[共享内核说明](../../README.zh.md)和
[硬件支持](../../../../docs/aurora/hardware.zh.md)。

| 领域 | 补丁 | 用途 |
| --- | --- | --- |
| 共享显示 | [DSC full ICH precision](../../patches/dpu-sm8650-dsc-full-ich-precision.patch), [DSC 1.2 RC model](../../patches/dsi-dsc-12-rc-model.patch), [first-line BPG offset](../../patches/dsi-dsc-12-first-line.patch), [DSI PHY interface clock runtime PM](../../patches/dsi-phy-iface-clk-runtime-pm.patch) | N1 面板所需的 DSC 参数；屏幕关闭时释放显示时钟控制器 |
| 共享 USB 与电源 | [NCM TX timer](../../patches/usb-ncm-retry-busy-timer.patch), [battmgr charge units](../../patches/qcom-battmgr-default-charge-unit.patch), [battmgr notification](../../patches/qcom-battmgr-serialize-notification-request.patch), [power-supply readiness](../../patches/power-supply-firmware-readiness.patch) | NCM 吞吐、ADSP 电池信息 |
| 板级 | `board.patch`, `n1-board.patch`, `keys.patch`, `power.patch`, `unused-crypto.patch`, `ufs-mcq.patch`, `ramoops.patch` | 板级 DT、DSI 面板连线、按键、ADSP 电池与 USB2 角色、禁用 QCE、UFS MCQ、带 oops 记录的 ramoops |
| 触控 | `touch.patch`, `touch-panel-follower.patch` | S3910P 原始 SPI 传输与连线；屏幕关闭时关闭触控控制器电源 |
| GPU | `gpu.patch`, [GMU sync_state series](../../patches/gmu-sync-state/README.md) | Adreno 750 与原厂 ZAP 固件；GMU component 绑定 |
| 电池 | `battmgr-property-ids.patch`, `battmgr-reporting.patch`, `battmgr-charge-control.patch`, `battmgr-adsp-log.patch`, `battmgr-usb-icl.patch`, `usb-psy-name.patch` | Aurora 原厂 battmgr 属性 ID 与电流符号；USB 充电器类型，不把 ID 电阻当作内阻；带固件使能的充电阈值和可写的充电电流上限；通过 dynamic debug 输出 ADSP 充电日志；USB 输入电流上限取自 gadget 电流 |
| 音频 | [q6apm readiness](../../patches/q6apm-probe-readiness.patch), [CS35L43 codec](../../patches/cs35l43-codec.patch), [CS35L43 DAI clock](../../patches/cs35l43-dai-clock.patch), [legacy TDM endpoint](../../patches/audioreach-legacy-tdm.patch), `audio.patch`, `audio-codec-clock.patch` | WCD9395 与双 CS35L43 扬声器；见[音频](../../../../docs/aurora/audio.zh.md) |
| 视频 | `video.patch`, [HFI gen2 decode order](../../patches/iris-hfi-gen2-decode-order.patch), [HFI gen2 capture pool](../../patches/iris-hfi-gen2-capture-pool.patch) | Iris 与原厂 VPU33 固件、VA-API 所需支持 |
| Wi-Fi 与蓝牙 | `radio.patch`, `wifi-qmi-mlo.patch`, [ath12k single-pdev regulatory](../../patches/ath12k-single-pdev-reg.patch), [PCIe IOMMU cells](../../patches/pcie-qcom-iommu-cells.patch), `pcie-suspend-opp-floor.patch`, `pcie-suspend-opp.patch`, `pcie-suspend-floor-modes.patch`, `pci-host-common-endpoint-d3cold.patch` | WCN7850 连线、原厂 Kiwi-v2 QMI 资源、5 GHz 范围、PCIe SID 解析；只由端点否决 D3cold，s2idle 时拆除链路（armada；`pci_host_common.endpoint_d3cold`）；可选的仅挂起 PCIe OPP 内存投票作为后备（armada；`pcie_qcom.suspend_opp_floor` = off（默认）、full、cx，或 bw 配合 `suspend_floor_kbps`） |
| 供电 | `optional-supplies.patch` | 显式获取可选的旧式供电（DRM、PCIe） |
| USB3 与 DP | `usb-dp.patch` | SuperSpeed、combo PHY、WCD9395 开关与 DP |
| N1 面板与扫描输出 | `n1-panel.patch`, `n1-transfer.patch`, `n1-120hz.patch`, `n1-30hz.patch`, `n1-boot-power-cycle.patch`, `cmd-disabled-flush.patch`, `cmd-multirect.patch`, `cmd-tearcheck.patch`, `sm8650-mdss-identity.patch`, `lucid-ole-preserve-enabled-pll.patch` | N1 DSC command 模式面板 30/60/120 Hz（接管后先断电再冷启动）、SM8650 command 扫描输出、显示接管 |
| 时钟 | `gcc-cx-binding.patch`, `gcc-cx-runtime-pm.patch`, `gcc-cx-domain.patch`, `pcie-gdsc-off.patch` | GCC GDSC 绑定到 RPMh CX 电源域（linux-next）；挂起时关闭 PCIe 控制器与 PHY 的 GDSC（armada） |
| 基带 | `modem.patch`, [IPA v5.5 configuration](../../patches/ipa-v5.5-config.patch), [QRTR HELLO and announcement fixes](../../patches/qrtr-hello), [PAS exclusive-region reassignment](../../patches/pas-reassign-exclusive-regions.patch) | MPSS、IPA 与 rmtfs 内存；基带下行；服务通告；MPSS 重启不再导致手机复位。见[基带服务](../../../../docs/modem.zh.md) |
| 相机 | `imx858.patch`, `camera-ultra.patch`, `ov32b40.patch`, `camera-tele-front.patch`, `lyt900.patch`, `camera-wide-tele5x.patch`, [CAMSS stream unwind](../../patches/camss-stream-unwind.patch), [CAMSS C-PHY series](../../patches/camss-cphy/README.md), [SM8650 C-PHY lane settings](../../patches/camss-sm8650-cphy.patch), [gen3 CSID C-PHY select](../../patches/camss-csid-gen3-cphy.patch), [C-PHY CSIPHY clock](../../patches/camss-csiphy-cphy-clock.patch) | Sony IMX858（超广角、3.2 倍长焦、5 倍长焦）与 LYT-900（广角）驱动，固定 4096x3072 RAW10 模式；OmniVision OV32B40 驱动（前置，尚未启用）；CCI、CSIPHY 与供电接线；SM8650 C-PHY 接收；广角与 3.2 倍长焦的 MIPI 通路选择 |

在 x86_64 或 AArch64 Linux 主机上构建：

```sh
nix build .#devices.aurora.kernel --out-link result-kernel
```

x86_64 构建使用 `buildPackages` 中的 Clang/LLD 生成 AArch64 内核。Linux 内核补丁遵循上游
GPL-2.0 条款及所修改文件的 SPDX 声明。
