# T880 内核补丁

[English](PATCHES.md) · [T880 指南](../../../../docs/t880/README.zh.md)

此目录是锁定 Linux 7.3.1 的设备补丁队列。顺序见 [`series.nix`](series.nix)，
配置见 [`kernel.config`](kernel.config) 与 [`trim.nix`](trim.nix)。构建、安装和功能状态
见上方 T880 指南。共享 `usb-ncm-retry-busy-timer.patch` 最先应用，随后是本目录的
244 个补丁，共 245 个；不应用高通共享补丁。

导入的前置系列保持原顺序，保留邮件作者、日期、消息、trailer 和来源链接。
本地后续修复按子系统合并：绑定与接口先于实现，构建启用晚于对应源码，设备树在最后。
厂商原始导入与 MT6897 适配分开，具体来源及本地选取范围见各补丁消息。

## 导入来源

| 补丁 | 来源 | 选取范围与作者 |
| --- | --- | --- |
| [0001](patches/tb375fc-linux/0001-mt6897-source-dtsi.patch) | [tb375fc-linux aef99312](https://github.com/u0n0u/tb375fc-linux/commit/aef99312cbe5619b83857e71efe6f0afe7d2c39b) | 仅选取 SoC DTS |
| [0002](patches/local/0002-i2c-mediatek-support-the-mt6983-generation-controller-mt6895.patch) | [MT6895-Mainline abb5229e](https://github.com/MT6895-Mainline/linux/commit/abb5229ecbe3145a19fb1f8b905fc0e99e3f6b9a) | 仅选取 I²C 控制器改动 |
| [0003](patches/mt6895-mainline/0003-spmi-mtk-pmif-clear-observed-slave-eint-status-bits.patch)–[0004](patches/mt6895-mainline/0004-spmi-mtk-pmif-fix-slave-irq-bank-calculation.patch) | [MT6895-Mainline](https://github.com/MT6895-Mainline/linux) | PMIF 从设备中断修复 |
| [0005](patches/lore/0005-spmi-print-error-status-with-pe-format.patch)–[0008](patches/lore/0008-spmi-implement-spmi-subdevice-alloc-and-add-and-devm-variant.patch) | [SPMI subdevices v7](https://lore.kernel.org/all/20251021083219.17382-1-angelogioacchino.delregno@collabora.com/) | 前置整理与子设备 API |
| [0009](patches/lore/0009-clk-mediatek-split-out-registration-from-mtk-clk-register-gates.patch)–[0015](patches/lore/0015-clk-mediatek-add-support-for-mt6685-pm-clock-ic-clock-controller.patch) | [SPMI clocks v2](https://lore.kernel.org/all/20251027111343.21723-1-angelogioacchino.delregno@collabora.com/) | 时钟辅助代码与 MT6685 |
| [0016](patches/lore/0016-dt-bindings-rtc-add-mediatek-mt6685-pm-clock-ic-real-time-clock.patch)–[0017](patches/lore/0017-rtc-add-support-for-mt6685-clock-ic-s-rtc-over-spmi.patch) | [MT6685 RTC](https://lore.kernel.org/all/20251024083318.25890-1-angelogioacchino.delregno@collabora.com/) | AngeloGioacchino Del Regno; RTC |
| [0018](patches/lore/0018-dt-bindings-mfd-add-binding-for-mediatek-mt6363-series-spmi-pmic.patch)–[0019](patches/lore/0019-mfd-add-support-for-mediatek-spmi-pmics-and-mt6363-73.patch) | [SPMI PMIC MFD v12](https://lore.kernel.org/all/20260511101355.122478-1-angelogioacchino.delregno@collabora.com/) | 选取的 MFD 与绑定 |
| [0020](patches/lore/0020-dt-bindings-display-mediatek-dsc-add-mt8196-compatible.patch)–[0078](patches/lore/0078-drm-mediatek-mtk-drm-drv-fail-init-only-if-all-paths-are-invalid.patch) | [DSC/DSI/WDMA v9](https://patchwork.kernel.org/project/linux-mediatek/list/?series=1166385), [display restructuring v2](https://patchwork.kernel.org/project/linux-mediatek/list/?series=1127365) | 保留原作者、trailer 与版本适配 |
| [0079](patches/local/0079-soc-regulator-mfd-power-add-mt6895-pmic-and-power-domain-support.patch)–[0080](patches/local/0080-usb-typec-xaga-add-mt6375-tcpc-dual-role-type-c-support.patch) | [tb375fc-linux](https://github.com/u0n0u/tb375fc-linux) | 选取的 MT6375 MFD 与 TCPC |
| [0081](patches/lore/0081-memory-mtk-smi-fail-larb-runtime-resume-until-component-bind.patch) | [mtk-smi fix](https://lore.kernel.org/all/20260926192417.1448813-1-valentin.haudiquet@canonical.com/) | 组件绑定前延迟运行时恢复 |
| [0082](patches/local/0082-misc-mediatek-import-the-vendor-ccci-util-for-mt6897.patch)–[0083](patches/local/0083-misc-mediatek-import-the-vendor-eccci-and-ccmni-for-mt6897.patch) | [MiCode 3c4ccd07](https://github.com/MiCode/MTK_kernel_device_modules/tree/3c4ccd07d5624879555ec710c11bb8818e5cb5c6/drivers/misc/mediatek) | 未修改的厂商源码 |
| [0084](patches/local/0084-eccci-write-the-ccif-sram-info-tail-to-the-md-window-as-well.patch)–[0086](patches/local/0086-misc-mediatek-eccci-expose-the-at-port-as-a-standard-tty-ttyccci0.patch) | [MT6895-Mainline qqcandy](https://github.com/MT6895-Mainline/linux) | CCIF SRAM 尾部与 ttyCCCI0，0085 为独立本地构建适配 |
| [0087](patches/local/0087-arm64-mediatek-xaga-add-the-mt6895-vcp-multimedia-platform.patch) | [VCP source 591943ef](https://github.com/MT6895-Mainline/linux/commit/591943ef425cd42eca7583f4a56be73fc3aef596), [snapshot f1c0c824](https://github.com/MT6895-Mainline/linux/tree/f1c0c8245d163fece46699612b8322d11e26348d) | 仅选取解码器，保留完整更新来源记录 |

VCP 导入仅含有状态解码器前后端、码流辅助代码与传输 API 声明；不导入 xaga 的
设备树、编码器、regulator、remoteproc 实现或 DVFS 策略。MT6897 编码器和平台集成
属于后续本地补丁。

## 本地集成

| 补丁 | 内容 |
| --- | --- |
| [0088](patches/local/0088-dt-bindings-mediatek-describe-mt6897-clock-resources.patch)–[0107](patches/local/0107-dt-bindings-mediatek-describe-mt6897-usb-phy-resources.patch) | 绑定与硬件 ID |
| [0108](patches/local/0108-drm-mediatek-declare-mt6897-display-controller-interfaces.patch)–[0118](patches/local/0118-mailbox-mediatek-support-mt6897-gce-firmware-contexts.patch) | 显示接口；SPMI、输入、温控与 mailbox 提供者 |
| [0119](patches/local/0119-workaround-clk-mediatek-retain-firmware-owned-mt6897-mux-state.patch)–[0138](patches/local/0138-power-supply-mt6375-implement-reporting-and-battery-care.patch) | 时钟、电源、固件、内存与充电支持 |
| [0139](patches/local/0139-phy-mediatek-support-mt6897-usb-phy-initialization.patch)–[0144](patches/local/0144-phy-mediatek-support-mt6897-c-phy-lanes.patch) | USB、Type-C、方向切换与 C-PHY |
| [0145](patches/local/0145-soc-mediatek-describe-mt6897-mmsys-and-mutex-routing.patch)–[0156](patches/local/0156-bluetooth-tolerate-unsupported-sync-train-parameters.patch) | 显示路由、OVL/DSI/DSC/DP、面板、DMA 所有权与蓝牙 |
| [0157](patches/local/0157-misc-mediatek-update-shared-ccci-declarations.patch)–[0167](patches/local/0167-misc-mediatek-integrate-mt6897-modem-module-builds.patch) | 厂商调制解调器适配、SCP 传感器与构建集成 |
| [0168](patches/local/0168-media-mediatek-adapt-the-vcp-decoder-backend-to-mt6897.patch)–[0171](patches/local/0171-media-mediatek-enable-mt6897-vcp-codec-builds.patch) | VCP 解码器、异步队列、有状态编码器与构建集成 |
| [0172](patches/local/0172-arm64-dts-mediatek-describe-mt6897-soc-resources.patch)–[0177](patches/local/0177-workaround-arm64-dts-apply-t880-dram-proxy-floors.patch) | SoC、显示与板级设备树，以及显式标记的临时策略 |

追加的 [0178](patches/local/0178-dt-bindings-display-boot-ownership.patch)–[0180](patches/local/0180-arm64-dts-t880-display-boot-owners.patch) 引入独立的继承显示 DMA 所有者、物理 SMI 依赖与 IOMMU 初始引用的显式转交。该替代方案已验证物理与转换显示路径的双 M4U 空闲挂起、DMA 前重新获取、显示电源切换与光标采集；物理路径 H264 硬件编解码及转换路径 H264 硬件解码亦通过。

## 保留的 workaround

以下补丁的提交主题均以 `workaround: ` 开头。这些补丁记录当前硬件与固件集成所需的限制。USB force-VBUS 的实际板级接线、PHY/角色生命周期修复
以及 OVL shadow 锁存修复不归入 workaround。

| 补丁 | 保留原因 |
| --- | --- |
| [0119](patches/local/0119-workaround-clk-mediatek-retain-firmware-owned-mt6897-mux-state.patch) | 0184–0187 部分替代：八个 mux 已实现 AP 投票；固件父时钟、VCP 控制和继承启动投票限制仍保留。 |
| [0120](patches/local/0120-workaround-clk-mediatek-preserve-unmanaged-mt6897-pll-rates.patch) | 未接管的 PLL 频率仍由固件管理；TVDPLL 支持调频。 |
| [0132](patches/local/0132-workaround-soc-mediatek-proxy-mt6897-dram-bandwidth-votes.patch) | 以 CPU/devfreq 负载代理和固定下限替代尚未接管的多媒体带宽策略。 |
| [0137](patches/local/0137-workaround-mfd-mt6375-preserve-firmware-protection-settings.patch) | 限制固件保护配置的写入，仅保留有界充电控制例外，并禁止 TCPC 软件复位。 |
| [0166](patches/local/0166-workaround-misc-mediatek-keep-modem-modules-permanent.patch) | 调制解调器清理流程不完整，因此禁止模块卸载与手动解绑。 |
| [0173](patches/local/0173-workaround-arm64-dts-avoid-duplicate-mt6897-cpu-throttling.patch) | Linux CPU 温控阈值保持高于固件目标，避免重复限频。 |
| [0177](patches/local/0177-workaround-arm64-dts-apply-t880-dram-proxy-floors.patch) | 板级配置启用 DRAM 代理投票及保留的多媒体/vcore 下限。 |

历史补丁 [0135](patches/local/0135-workaround-iommu-mediatek-hold-mt6897-mm-banks-active.patch) 的永久 probe 引用已由 0178–0180 取代。初始保护引用现显式转交给独立启动所有者与正常 DMA 消费者，不再是持续生效的永久供电 workaround。

[0181](patches/local/0181-ccci-validate-runtime-LK-metadata.patch)–[0183](patches/local/0183-selftests-mediatek-LK-metadata-boundaries.patch) 为 LK 元数据解析增加边界校验并删除板级记录描述符。需要匹配的 U-Boot 运行时转交支持，见[升级顺序](../../../../docs/t880/README.zh.md#调制解调器元数据升级顺序)。T880 已验证运行时转交、正常调制解调器启动以及经更新后 U-Boot 启动 RAM recovery。历史 [0176](patches/local/0176-workaround-arm64-dts-retain-the-t880-lk-modem-tag-fallback.patch) 的记录描述符 workaround 已被取代。

0184–0187 增加有界 AP mux 投票、PLL 直接查询的实时频率及故障注入测试。仅部分替代 0119/0120：固件父时钟、VCP 所有权、启动继承投票交接及非 TVDPLL 控制仍未接管，见时钟所有权。

0188 将八个 mux AP 投票改为原子 CCF enable/disable，并保留 AP 位为零时未知的启动直接使能。0189 在任何电源域初始化前准备两个 OVL 域的明确根时钟引用，HWV-on 前使能，状态不确定时保留并隔离控制器。尚未解除启动投票，也不据此认定物理断电，见时钟所有权。

0190–0192 增加可选的常开 SPM 状态源及明确的 OVL 启动所有权交接。仅严格物理断电历元可在普通根时钟引用仍有效时转交记账，由后续普通最后一次 disable 解除 AP 投票。缺失、读取失败或不完整的状态保留 BOOT；其他根时钟继承、父时钟一致性及 VCP 控制限制仍在，硬件行为尚未验证。见时钟所有权。

0193 将普通根时钟所有权扩展至 MM_INFRA、DIS0/1 和 VEN0/1，增加分阶段确认的 VENC 电源请求、所选拓扑校验及共享祖先故障隔离。MM_INFRA 在直接 VEN 域完成接纳前保留启动所有权。物理断电历元交接仍仅限 OVL；原有 VENC 叶门控顺序及其他时钟所有权限制仍在。见时钟所有权。

0194 将 DirectLink 配置时钟引用限定在各组件的活动期，按端口、配置顺序释放并在失败时局部回滚。共享及影子组件各自持有普通引用，已绑定但不活动的链路不再持续保持配置提供者活动。OVL 启动投票交接仍需实际物理断电观测。

0195 仅为 MT6897 启用 MMSYS/mutex 运行时电源管理，平衡 mutex 消费者引用及 CRTC 准备失败回滚，并保护可选 MMSYS 时钟子设备清理。这消除一个普通域断电阻碍；CMDQ 停止确认与实际物理断电行为仍需单独验证。

0196 为 MT6897 DP_INTF 提供串行化的完整运行时电源/时钟引用，分别记录成功启用的桥接器和组件所有者；调试寄存器访问仅借用已活动输出。调试文件保持桥接器分配有效，解绑时禁止新访问，不强制清空保留电源引用。其他 DPI/DVO 时钟行为不变。

0197 在终止任务前验证 MT6897 CMDQ 通道确已停止，传播 PM、暂停、复位及禁用回读错误；故障锁存并仅保留一个电源引用。拒绝故障通道的新提交，中断确认状态但不回收保留任务。这不修复故障后的帧缓冲区生命周期。

0198 还要求 MT6897 停止确认边界上的邮箱框架 TX 队列为空，防止任务分配失败后保留的排队令牌在断电后延迟提交，并用实际邮箱核心重试函数验证该边界。

0199 在 CRTC 包复用及目标断电前检查 MT6897 停止状态，不确定时保留组件、mutex 和 PM 所有权，阻止故障后的 CRTC 工作及新提交，并平衡已持有、当前及排队状态的事件引用。独立桥接器回调、故障后帧缓冲区及手动解绑安全不属于该电源保留保证。

0200–0201 为 MT6897 C-PHY 添加配置时钟、每链路 MMSYS 路由恢复与成对电源引用；物理断电后的显示恢复仍失败：DSI 命令超时，vblank 计数未前进。

0202–0204 让每个 MT6897 C-PHY 链路在链路电源周期内持有 DIS 公共 26M 门控，并加入
受限的只读路由、门控与合并中断阶段证据。厂商显示控制器在
[顶层时钟组](https://github.com/MiCode/MTK_kernel_device_modules/blob/3c4ccd07d5624879555ec710c11bb8818e5cb5c6/arch/arm64/boot/dts/mediatek/mt6897.dts)
中同时占用两个 26M 门控；该门控在 DSI 中的确切作用仍是假设。物理断电后的功能
恢复仍待验证。

0205 在 MMSYS 运行时恢复时清除 MT6897 DIS/OVL 合并中断路由。厂商显示驱动在每次
顶层时钟上电时将 INTMERGE +0x008 清零；26M 试验在物理域断电后测得该寄存器为 1，
待处理的 DSI 读中断未送达处理程序。现有只读阶段诊断仍读取同一寄存器。

0206 使 MT6897 DSI 命令完成方式与厂商一致：不启用 CMD_DONE，启动命令后轮询
DSI_BUSY 直至清零。读取仍等待 LPRX，视频仍使用 VM_DONE；其他 SoC 保持中断等待。
受限的前 8 条命令/中断跟踪与扩展超时转储均为只读，并在每次上电时重置。

0207 将每条命令成功路径上的 dev_info 跟踪替换为每个 DSI 实例的 16 项内存环形缓冲，
因此不改变命令节奏。轮询或中断超时时，每次上电仅一次转储失败消息、从旧到新的环形
内容以及引擎/PHY 寄存器；另记录一次路由恢复后的时钟频率。所有读取均为只读。

0208 为 MT6897 设置 cmdq_long_packet_ctl，使每条命令都写入 CMDQ_SIZE_SEL，与厂商
一致。启动时固件设置了该位，但物理域复位会清除。确认试验在设置该位后仍观察到相同的
长包后停顿，因此仅此对齐不能恢复唤醒。

0209 在上电 DSI 引擎复位前选择 MT6897 的 MM 复位源。厂商 C-PHY 路径设置
DSI_DEBUG_SEL 第 10 位 MM_RST_SEL；主线只在稍后的 TX 缓冲配置中写入同一位，晚于
mtk_dsi_reset_engine()。启动状态由固件初始化，而域复位后第一条命令读到空的 CMDQ
SRAM，随后长包序列停顿。只读的首命令、超时与环形转储现在包含 DSI_DEBUG_SEL。

0210 在引擎复位后、上电时清除 MT6897 的两个命令队列字，并将 MT6897 v1 布局的
逐字节读改写路径替换为软件拼装、零填充的整字写入。这针对域复位后未初始化的 CMDQ
状态以及长包中只写入部分字节的填充字；CMDQ_SIZE 与 SIZE_SEL 的编程及其他 SoC
保持不变。超时环形转储还记录 CMDQ+4 字。

0211 为 MT6897 HWV 根投票与关断路径增加只读诊断。投票失败时记录步骤（done 等待、
set/clr 写入、AP set/clear 等待、done 状态等待）、返回码、六个 HWV 寄存器以及根/
故障/子域状态；HWV 根关断每次记录投票前与投票后状态各一次。投票行为、超时、写入
和隔离策略均不变。

0212 为诊断唤醒硬挂起而临时回退 0210。显示关断路径完成并记录了 HWV 投票状态，但
随后的唤醒在内核与用户空间均无输出的情况下挂起；0210 是产生显式 DSI 命令超时的
候选之后仅存的新变量。该回退恢复原有的逐字节 CMDQ 编程，并移除上电队列清零与
CMDQ+4 环形读取；其他时钟、所有权、轮询完成、环形、CMDQ_SIZE_SEL、MM_RST_SEL
与 HWV 变更均保留。此为等待挂起结果的诊断步骤。

移除 0210 后，唤醒返回显式的 DSI 轮询超时且系统保持存活，因此 0210 导致了硬挂起。

0213 将上电队列清零与原子整字编程分离：仅重新应用引擎复位后对两个 MT6897 CMDQ
字的清零，保留逐字节读改写路径与不含 CMDQ+4 字段的环形转储。若显式超时返回，则
原子写入导致硬挂起；若硬挂起返回，则清零导致。此为二分步骤，不对底层唤醒失败
作结论。

0214 增加只读的 MT6897 CMDQ 写入跟踪。每条命令队列的数据、配置、长度与
SIZE_SEL 写入均记录到 64 项内存环形缓冲，包含命令序号、消息类型与长度、目标
偏移、掩码、值和写入类别；命令环形缓冲重新记录 CMDQ 字 1。现有的每次上电一次
的超时转储会从旧到新打印写入环形缓冲，以及含字 1 的命令环形缓冲。写入、掩码、
顺序与时序均不变。用于区分长包后配置写入是已发出但丢失，还是从未发出。


0230 在每次启用 MT6897 OVL 前恢复直连取数控制，包括双管线的另一半。
仅设置 BURST16 与输出钳位位，保留同寄存器的其他位；为两个物理层完整初始化
请求控制字，并恢复缓冲区低/高阈值。其他 OVL 型号保持原启动路径。
生产函数测试覆盖寄存器丢失、双管线、掩码和完整字写入、启用顺序及旧型号轨迹。


0231 将 MT6897 的 DSC VERSION 字段（0x200）与影子控制（0x228）分开。
启动时按厂商掩码恢复 VERSION 并保留其他字段，现有 FORCE_COMMIT/BYPASS 控制和
顺序不变。其他 DSC 型号继续使用合并寄存器路径。生产核心/包装函数测试覆盖
版本、寄存器初值、启用/禁用配置、双核心及重复上电周期，旧型号 MMIO 轨迹一致。


0232 在平台断电前停止 CCIF IRQ、轮询、SRAM/状态工作及进行中的 TX 临界区，
停止失败时保留 AP 资源。平台 runtime-PM 错误及未完成的逻辑挂起会传递到终止性
FSM 失败状态；GET_MD_STATE 报告 STOP 尚未完成及锁存的错误码。复位和时钟关闭
仍仅在成功的 GATED 完成路径中执行。这未实现完整 DMA/传输清理，也未解除模块
卸载和手动解绑限制。


0233 导入联发科未使用电源域消费者，0234 将其接入托管运行时电源管理，
并为 T880 的 PCIe PHY0 添加唯一消费者。现有 MAC0 父域遵循 genpd 的
父子域顺序；驱动为可选项，仅在 T880 启用，其他未使用电源域及其时钟策略保持不变。


0235 将 UART0/1 的总线输入连接到现有 PERAO 门控，保留 26 MHz 波特率参考。
0236 添加 C/N/S IMP I2C 门控提供者，并将 I2C0/5/6 的主时钟与 DMA 时钟连接到
实际门控，保留各组的其他时钟编号。0237 按原厂连接分开显示 PWM 的时钟源和
外设门控输入。消费者驱动管理准备、传输及电源管理生命周期；其余全局时钟保留
和 DRAM 策略保持不变。


0238 将 MT6897 LVTS 描述为无需 AP 门控时钟的型号，保留固件配置和硬件保护。
0239 添加 MT6897 SPMI 2.0 无 AP 时钟型号，其他控制器的时钟与中断行为不变。
0240 为 MT6897 第一版 UFS PHY 添加独立兼容项，不再执行旧 MT8183 的电源和时钟
操作；保留主机连接及参考时钟协议。对应设备树输入和绑定反映各型号约定，
其他型号仍要求原有时钟并使用原有操作。

0241 提供持有设备引用的运行时 PM 供应者快照。0242 让活动的 MT6897 CRTC 按顺序
持有路径所需的 MMSYS 控制器以及 DRM 设备的 MMSYS 父设备。确认停止后，先按依赖
顺序释放组件、互斥器和供应者引用，再按相反顺序释放控制器。其他变体保持原有设备
链接。0243 在断电失败而电源域逻辑上仍为开启时，拒绝已隔离的 MT6897 根域重新恢复。
0244 验证引用所有权、释放顺序和故障后的恢复限制。
