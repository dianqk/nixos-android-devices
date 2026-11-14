# SM8475 内核支持

[English](README.md)

Unicorn 通过 [`series.nix`](series.nix) 选择 TLMM、SoC 设备树、
UBWC、PLL 交接、UFS 父时钟/状态保持修复及 GCC CX 电源管理。
`config.nix` 选择 SM8450 系列共用驱动，其他补丁由板级队列显式选择。

共用 SoC 补充 UFS PHY 的 `UFS_PHY_GDSC` 依赖。TLMM 将 EGPIO 标记为 GPIO
功能，显式中断偏移与核心回退路径一致。Asphalt 保留 `asphalt/` 下独立的上游队列，
此处队列仅由 Unicorn 导入，Asphalt 显式选择 UFS 后续补丁。Lucid OLE PLL 修复保留引导程序已启用的 PLL；GCC binding、
runtime PM 驱动及 CX 域引用成组应用。

## UFS 时钟与电源

UFS AXI、ICE 在 850 MHz 档选择 GPLL3。SM8450/SM8475 控制器在挂起时关闭
设备和 PHY，因为 PHY 状态不能跨 CX collapse 保留。SM8475 三个根时钟使用
`clk_rcg2_shared_ops`，运行中更新时强制开启、关闭时缓存配置，并在父时钟关闭
前切换到安全源。Hibern8 回调向上传递退出错误，testbus 写入保留实时分频位。

Unicorn 通过此队列选择 `ufs-performance-opps.patch` 和 `ufs-opp-init-order.patch`，
新增 ICE 联动及协调的 CX/MX 性能请求。Asphalt 在上游已有 OPP 上显式选择
`asphalt/patches/local/0036-sm8475-ufs-ice-mx-opps.patch` 及相同的初始化顺序修复，
保留上游 SM8475 turbo compatible、完整 UFS PHY 序列和媒体集成。后续补丁移除
主机永久 NOM 请求，使 75 MHz 档可由联动 OPP 请求 LOW_SVS。它改变 Asphalt 的
时钟与电源管理，不提高最高频率，也不代表吞吐量提升。此 OPP 实现提供两个状态：

| AXI / UniPro / ICE | CX / MX 所需性能档 |
| --- | --- |
| 75 MHz | 64（`LOW_SVS`） |
| 850 MHz | 416（`TURBO_L1`） |

九项 OPP 时钟数组的第 0、3、8 项分别为 AXI、UniPro、ICE。性能请求经
`UFS_PHY_GDSC` 传到 GCC 的 CX、MX 父域；runtime PM 只负责域的开关。
ICE 在驱动开启时钟前以 75 MHz/LOW_SVS 启动。初始化修复先取得全部时钟句柄，
再应用初始 OPP，并记录成功切换后的频率；升频前提高性能请求，降频后降低请求。
两板保留各自的 timing compatible；SM8450 保留单一 CX 父域及控制器行为。

性能档来自锁定的 [OEM GCC 驱动](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/blob/fa4513e61931e11a59e3f177ae590d4e090d7229/drivers/clk/qcom/gcc-waipio.c)
及[数值映射](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/blob/fa4513e61931e11a59e3f177ae590d4e090d7229/include/dt-bindings/regulator/qcom,rpmh-regulator-levels.h)。
[clock supply](https://github.com/MiCode/kernel_devicetree/blob/c79d5587e59766264e81ca8a82e1525009699356/qcom/waipio-clock.dtsi)
与 [regulator 定义](https://github.com/MiCode/kernel_devicetree/blob/c79d5587e59766264e81ca8a82e1525009699356/qcom/cape-regulators.dtsi)
将 `vdd_mxa` 映射到 `mx.lvl`，active-only supply 是另一项。Unicorn 已观察到的
CMD DB 将低档请求映射为 CX 64 / MX 192；其他消费者可以提高聚合请求。

从 RAM recovery 验证双向切频、闲忙/Hibern8 切换及 UIC/SCSI 错误时，根文件
系统保持未挂载或只读。软件票和时钟读回不能测量物理电压；补丁重放及构建通过
不能证明任一设备的 UFS 稳定性或挂起恢复成功。

## 板级队列

USB repeater、UFS 时序、显示 PHY 和外设接线分别保留。Unicorn 单独选择 A730、
UFS 低 gear 修复及独立 CSI2 PHY；Asphalt 使用集成 CSIPHY，须保持驱动和设备树
配套。共用修改后检查两套队列，配置及构建要求见 [Unicorn](unicorn/PATCHES.zh.md)
和 [Asphalt](asphalt/PATCHES.zh.md)。
