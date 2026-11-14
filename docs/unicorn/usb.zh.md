# Unicorn USB2

[English](usb.md) · [设备指南](README.zh.md)

默认模式为 NCM，可选 ACM 登录控制台。MTP 和网络共享需要显式启用；
MTP 仅导出配置中列出的目录。选项与切换命令见[USB 模式配置](../usb-signaller.zh.md)，
HIDRAW、原生多点触摸、镜像 U 盘和 UVC 见[USB 扩展模式](usb-gadgets.zh.md)。

## 可追溯的硬件通路

来源：

- [OEM 公共设备树](https://github.com/LineageOS/android_kernel_xiaomi_sm8450-devicetrees/blob/2e649a7f3e762903eedad43d8256b91e28b512d8/qcom/xiaomi-sm8475-common.dtsi)，尤其 `&usb0`、`&ucsi`、`&nxp_eusb2_repeater`。
- [公开 Unicorn 原厂展开树](https://github.com/sm8450-mainline/fdt/blob/3e347601d9e91dd2f1f48e51499823225f7bc0bc/unicorn.dts)，尤其 `ssusb@a600000`、`hsphy@88e3000`、`i2c@994000` 和 `ssphy@88e8000`。该展开树有重复标签，适合核对属性，不能直接作为可编译主线 DTS。
- 仓库的 `platform.patch`、`board.patch`、`eusb2.patch`、`usb-role-switch.patch` 是主线格式的实现。连接器图经Linux 7.3-rc6 schema 和 DTB 检查。

| 部件/功能 | 原厂证据 | 当前实现与验证状态 |
| --- | --- | --- |
| DWC3 | `0x0a600000`，`dr_mode=otg`，`maximum-speed=high-speed` | 双角色、USB2；端点双向连接 PMIC GLINK connector@0。驱动对象和 DTB 通过，新的实机 OTG 验收待做 |
| eUSB2 PHY | `0x088e3000`，L5B 0.88V、L10C 1.2V | 主线 Synopsys eUSB2，保留对应供电，不从其他板推导供电 |
| PHY 时钟/复位 | XO 参考源、GCC EUSB3_0_CLKREF_EN 门、QUSB2PHY_PRIM_BCR | 两路时钟和复位已配置，schema/对象通过 |
| 外部中继 | I²C `0x00994000`、地址 `0x4f`，S10B 1.8V、L2B 约 3V，PM8350C GPIO7 reset | PTN3222 兼容驱动；compatible 是迁移匹配，尚未确认芯片丝印。主线 reset active-low 与逻辑 assert/deassert 配套 |
| 中继信号参数 | Unicorn 覆盖 device: `0x62→0x08, 0x00→0x07`；host: `0x63→0x08, 0x22→0x07` | 保持原厂写入顺序；I²C 读写失败回滚寄存器，失败不提交新模式；断电重初始化重放模式。故障注入通过 |
| CC/PD/数据角色 | OEM USB ↔ UCSI connector 图 | UCSI/ADSP 协商，DWC3 跟随；启动和热插拔不请求角色交换。显式请求写 Type-C data_role 并确认 Type-C 和 DWC3 一致 |
| VBUS/充电 | 由原厂 PMIC GLINK/充电固件处理 | 没有新增猜测的 VBUS regulator 或直接供电命令。power_role 单独报告；`vbus_verified=false`，实测电压、电流及带载能力仍待验收 |
| USB HID/Storage/UAS/网卡/数字音频 | 标准 USB2 外设协议 | 实际 Kconfig 和对象检查通过；键鼠、U 盘、网卡、音频、带电 Hub 的实物测试待做 |
| USB3 | 原厂 maximum-speed 为 high-speed；QMP USB/DP PHY disabled | 当前仅提供 USB2；没有足够板级证据启用 USB3 通路 |
| 原生 DP | 公共 SoC 树包含 DP/QMP/FSA 描述，不等于板上完整链路 | 未验证；不添加虚构的 PHY、mux 或供电，不把 USB2 当成视频输出 |
| 模拟 Type-C 音频 | 原厂 `qcom,fsa4480-i2c` @ `0x42` 和相关引用 | 只有器件/引用证据；板级路由、供电、切换协议尚未完整核实，不启用 |

## 生命周期和接口

所有启动、模式请求、Type-C 事件、固件代次变化和退出操作由一个有界队列、单线程
状态机串行处理。重复进程被运行目录的文件锁拒绝。D-Bus 查询读取缓存状态，不等
sysfs 或外部服务；`set_mode` 返回的是**请求已接受**，应继续检查 `get_status` 中的
`busy`、`desired_mode`、`actual_mode` 和 `last_error`。队列已满会立即返回错误。

切换顺序为停止后端/console → 解绑 → 卸载 FunctionFS → 删除本控制器拥有的 gadget →
请求必要的数据角色 → 创建/准备后端 → 确认连接未变 → 绑定。创建、端点就绪、服务
启动或绑定失败时清理半成品；同一连接、同一固件代次仍允许 device 时重建前一模式。
断线或固件离线不强行回滚角色，最近错误保持可查询；仅新请求或连接/固件变化重试，
不会无限重启。切换期间发生的新连接事件保留到下一轮处理。

只管理六个精确名称：`usb-signaller-developer`、`usb-signaller-mtp`、
`usb-signaller-tethering`、`usb-signaller-touch`、`usb-signaller-storage` 和
`usb-signaller-uvc`。不删除 initrd/recovery 或其他服务的 gadget，不抢占其 UDC。
正常 initrd 在 switch-root 前解绑。Unicorn 的 initrd 不覆盖已连接 partner 的角色。
守护进程即使异常退出，systemd 的 ExecStopPost 也会执行同一清理入口。

`bound=true` 只表示 gadget 已绑定；`enumerated=true` 必须观察到 UDC configured。
无插线时绑定是有效状态，不等待电脑枚举，不阻塞事件处理。

`host_mode` 仅请求数据角色，不改变供电角色；host/sink 是合法组合，不能宣称能给
无源外设供电。拔线后退出显式 host 策略，恢复默认策略。`charging_only` 解绑 gadget，
保留 Type-C/充电协商，不切换 power_role。小米认证默认不改角色，可选发现也只通过
D-Bus 提交给这个状态机；认证标志不代替充电功率测量。

MTP 使用仓库打包的 uMTP-Responder，仅在 MTP 模式挂载 FunctionFS、运行 responder，
等 `functions/ffs.mtp/ready=1` 后绑定。systemd 隐藏 home，只绑定明确列出的共享目录。
MTP 不发布系统磁盘；其他可选设备模式各自独立，见上述扩展模式文档。

networkd 和 NetworkManager 通过本 gadget 的 MAC 身份区分 usb0，避免误接管主机模式下的 USB 网卡。
共享模式保留 networkd 对 gadget usb0 的所有权；先准备并加载 DHCP drop-in，再绑定 UDC，
确认 NCM 网卡的 MAC 后才启用接口转发和上游集合。临时 DHCP drop-in 发布路由和 DNS，专属
DNS 仅监听 usb0。上游按 main 表的 IPv4 默认路由和 metric 选取，排除 usb0/lo 和
不能安全确定的多路径。仅允许该上游、USB 子网源地址和公网目的地址，拒绝额外
内网转发、IPv6 转发及未建立的反向连接。使用接口级 forwarding，保存并恢复原值，
不写全局 ip_forward。退出和异常终止会清空上游集合、删除 DHCP drop-in、恢复接口
转发值；即使其他服务开启全局转发，空集合也会阻止 USB 转发。切换后电脑需重新
获取 DHCP 租约。复杂策略路由和代理需要另行配置。

## 检查与硬件限制

`usb-modes` 检查配置约束，`usb-manager` 检查状态机与失败恢复，
`usb-tethering` 检查共享策略，`unicorn-usb-kernel` 检查内核配置、驱动对象和 DTB。
这些检查不能代替实际外设测试。

主机数据角色不代表已提供 VBUS。无源外设供电、USB3、原生 DP 和模拟 Type-C 音频
尚未验证；供电能力需要实测电压、电流及带载情况。充电认证和功率采样见
[充电说明](charging.zh.md)。
