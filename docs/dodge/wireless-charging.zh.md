# Dodge 无线充电

[English](wireless-charging.md)

Dodge 模块包含自动、受限的普通 Qi/BPP 后端和可选用户空间电压养护服务。安装并
启动匹配的新代际后，放上充电板即可，不需要诊断命令或 Android 预热初始化。
已在 OAWV09 上观察到启动后自动充电和干净移除；冷替换和新的自动上限/降温保持
仍需硬件验证。

## 自动充电与养护策略

板级启用 `qcom,automatic-bpp-charging` 和接收器的 40 字节
`nuvolta,bpp-fod-parameters`。Linux 在校验板级校准前请求关闭普通输入，然后请求
固定 750mA 输入；不发送发射器查询、认证、FCC、FV 或电压命令。固件 ACK 确认
请求，原始无线 GET8 响应不是已应用限制的回显。

内核约每秒监控新的 source、receiver 和 battery 数据。要求普通 BPP、直通关闭、
接收器输出 4.5–6 V、无 USB/CID/OTG、电池健康、16–35 °C、合理的 3.0–4.4 V
配对样本且不平衡不超过 50 mV。否决后重启需要 17–33 °C。接收器输出超过 900mA、
实测电池充电超过 1.2A、电源故障或无效遥测会移除输入。这些是该支持的保守限制，
不是完整原厂 JEITA。软件轮询和传输超时不能保证瞬时硬件切断。

4.35 V 时内核保持电池但保留无线输入；至少 30 秒和三个分离的新样本后低于
4.30 V 释放。4.40 V 时即使有自有电池保持也会移除输入。5 秒保持稳定宽限期后
实测充电超过 50mA 也会移除输入。电压保持不报告 `Full`。自动上限下的降温行为
需单独观察；接收器输入可用不代表降温有效。

可选的 `dodge-wireless-care.service` 默认关闭，可在不重建内核的情况下配置较低的
养护上限：

```nix
hardware.dodge.wirelessCharging = {
  enable = true;
  ceilingMicrovolts = 4350000;
  restartMicrovolts = 4300000;
};
```

更低阈值可作为普通用户空间服务变更部署。养护保持至少 30 秒，包括服务重启后
继承的保持。读数不可读会断言保持；停止/崩溃服务会保留保持。`enable = true`
启用该用户空间服务；DT 后端和内核安全不受影响。未实现 SOC 策略和充到 100%。

`/sys/class/power_supply/qcom-battmgr-bat/` 下的稳定文件：

- `wireless_care_hold`：root 0600，严格的 0/1 请求养护票。
- `wireless_voltage_max`：新的合格最大样本（µV）；错误时不返回缓存。
- `wireless_charge_state`：输入阶段、三张票、所有权、pending/frozen 状态和错误阶段。

`error` 字段可能保留较早的拒绝资格，而 `phase` 已回到 `ACTIVE`。请同时检查当前
阶段/所有权和实测电池流，不要把历史值当作实时故障。

手动 INHIBIT、CARE 和内核 SAFETY 是独立票，共享只从确认的 1 获取的物理电池许可。
手动 `auto` 只清除 MANUAL；CARE/SAFETY 仍阻止使能。外来的 0 永远不会被使能。
临时输入否决保留请求的手动/养护意图。干净移除/替换会自动重新取得资格。Suspend
先移除输入；resume 重新取得资格，而不是盲目使能。

请求不明确或部分校准会隔离操作，而不是通过逻辑代际/reprobe 重试。新快照会再次
检查校准以发现无 GPIO 边沿的丢失。未解决的请求可能阻止 suspend。UNKNOWN 不是
已验证的关闭状态；再次试验前先调查。自动配置下开发输入触发器和 GET05 查询被禁用。

## 已验证行为

2026-11-13 使用 OPPO OAWV09 AIRVOOC 50W 磁吸充电器、磁吸壳/环和充电板安静/慢速
模式。最初的低输入问题在该模式改变前也出现在快速/默认模式。

| 能力 | 结果 |
| --- | --- |
| 放上充电板自动启动 | 启动后无需诊断触发器开始充电；约 60 秒内 31 个样本保持 3.90–3.93W、电池 +218–289mA。 |
| 移除充电板 | 输入所有权清除，无 unknown/frozen/pending 电池状态；设备访问结束前未观察替换。 |
| 用户空间养护服务 | 构建的正常策略脚本可在实时后端运行；自然上限/重启跨越未测试。 |
| 接收器检测与遥测 | 可读附着、输出可用性、电压和电流。 |
| 基础 Qi/BPP 电池充电 | 固定 750mA 输入请求产生约 3.9W 接收器输出和正电池电流。 |
| 附着时手动暂停/恢复 | `charge_behaviour` 将电池电流抑制到接近零；Auto 在不移除手机的情况下恢复。 |
| 电池状态报告 | Charging → Not charging → Charging 跟随实测流；报告试验的 56 个样本全部与电流一致。 |
| 早期有界请求清理 | 早期手动实验中 45 秒截止将输入降回约 0.18W 并恢复 Auto；自动输入没有 45 秒截止。 |

早期 750mA 周期在接收器测得 3.86–3.93W、电池 +179–266mA。随后暂停稳定在
−11 到 +9mA。接收器功率不是电池功率：部分用于运行手机。这些是设备遥测，不是
外部功率计测量。权限回读、ONLINE 和充电标签本身不能证明实际充电。

## 未完成支持

| 能力 | 剩余工作 |
| --- | --- |
| 冷/重复附着 | 已附着 OAWV09 的自动启动和移除已验证；替换/冷接收器验证仍开放。 |
| 持续充电 | 持久输入已验证超过旧 45 秒限制；长会话、实际保护跨越和更广充电板覆盖仍开放。 |
| 自动 80% 停止 / 70% 恢复 | 在已验证手动控制上增加策略并测量实际截止/恢复。 |
| AIRVOOC/SVOOC 或更高功率 Qi | 未实现/验证 Linux 认证和保护快充。 |
| 远程快速/安静/仅降温板模式 | 没有已验证的软件选择器；电池暂停与板模式不同。 |
| 其他 Qi 板和完整充电周期 | 这些 OAWV09 试验尚未验证。 |

更高功率、SOC 和完整原厂充电策略仍推迟。观察到的 3.9W 基础路径不声称 50W
AIRVOOC、10W Qi、完整满充周期或可日常使用的修复。现有正常启动代际在部署匹配
系统前也不会获得开发驱动。

## 安装后首次检查

启动匹配的新代际，拔掉 USB，将 Dodge 放到充电板上。初始养护协调可能保持电池约
30 秒。

```sh
systemctl status dodge-wireless-care.service --no-pager
bat=/sys/class/power_supply/qcom-battmgr-bat
cat "$bat/wireless_charge_state"
cat "$bat/status" "$bat/current_now"
```

`ACTIVE`、`input_owned=1` 和正电池电流确认充电。手动、养护或安全票抑制电池时
预期 `BATTERY_HELD`；无线输入仍可用。离开充电板或连接 USB 时
`INPUT_OFF_VETO` 是预期的。电压/温度限制也可能否决输入。检查移除和替换，然后
确认自动恢复充电。

## 手动电池暂停

Dodge 通过 `/sys/class/power_supply/qcom-battmgr-bat/charge_behaviour` 暴露受保护
的手动权限暂停：

```sh
# 暂停受支持的普通无线充电会话。
echo inhibit-charge | sudo tee /sys/class/power_supply/qcom-battmgr-bat/charge_behaviour

# 结束暂停并恢复本次会话改变的权限。
echo auto | sudo tee /sys/class/power_supply/qcom-battmgr-bat/charge_behaviour
```

自动模式下适用上面的更严格保护。手动获取需要新附着的 BPP 接收器、直通关闭、
接收器输出 4.5–6.0 V、无 USB 线或 OTG 源、电池健康且 0–43 °C。驱动先要求普通
路径固件权限已启用，然后禁用并验证结果。重复确认的暂停会重新验证，但不重复
禁用命令。该接口不控制 SVOOC 或其他直充路径、发射器模式、认证、异物检测或热
保护设置。

没有驱动自有暂停时 `auto` 是空操作。获取前已被禁用的权限属于其他控制器：获取
失败，驱动永远不会使能它。自动模式下，读取 `charge_behaviour` 会报告来自
MANUAL、CARE 或 SAFETY 的有效自有电池保持；`wireless_charge_state` 标识原因。
非自动模式下它报告手动会话。外来禁用权限仍报告 `auto`，因为 Linux 不拥有它。
电池状态和电流仍是独立测量。

非自动模式下，手动会话在来源变化、报告 USB、接收器不可读、设备 suspend 或驱动
移除时结束。清理可在移除后恢复自有权限，不需要接收器 I2C 回复。Resume 不会自动
开始另一次暂停。没有 SOC 阈值自动化。自动模式在临时否决和 suspend 期间保留请求
票。

每次恢复使能都需要新的健康电池和温度测量及验证的固件回读。不安全的运行时恢复
保持 pending，直到条件安全。恢复未解决时读取模式会失败，而不是报告成功。无法
验证恢复的自有暂停会阻止 suspend。

不明确的请求超时会让该固件服务代际的控制通道退役。所有权不会跨服务重启转移，
未解决会话不会通过新通道自动恢复。驱动移除和关机会在安全条件或丢失服务上等待
有限时间：如果原权限**未**恢复会明确报告。Teardown 时失去所有权；之后 probe
把残留禁用权限视为外来，永远不会静默使能。重复 `auto` 写入不能覆盖此限制。

可选 root 可读 debugfs 诊断
`/sys/kernel/debug/qcom-battmgr-dodge/normal_charge_enable` 报告实时原始普通路径
门（`0` 或 `1`）。它只读，不是聚合充电状态，也不是抑制属于该驱动的证据。

同一 debugfs 目录可选提供 root 可读 `normal_input_suspend`。每次读取请求新的 OEM
gauge 缓冲，并独立于电池健康和普通充电权限报告普通输入 suspend 标志 `0`/`1`。
固件只回复原来九个 gauge 字段时仍支持；可选第十字段缺失时返回 `ENODATA`。畸形
值和传输错误返回错误，不复用旧标志。该诊断没有 setter，不能说明输入为何 suspend
或收到多少功率。

该 debugfs 目录中的 `wireless_input_current_limit` 是 root 可读、只读的 OEM 无线
输入限制属性原始固件响应，标称单位微安。它未被验证为有效或已应用限制：固件可能
返回零而不反映请求值。它与 USB 输入限制分离，不测量接收器功率，也不能确定低输入
原因。该原始诊断没有 setter。

root 可读、只读的 `normal_charge_limits` 请求一对新的 OEM 电池属性，报告
`current_max_ua`（标称 FCC）和 `voltage_max_raw`（电压限制属性），保留完整无符号
固件值。电压响应故意保持原始：OEM setter 使用毫伏乘以电池节数，因此该诊断不把
它标为微伏。固件聚合和有效限制语义未验证。错误会失败读取，不发布部分对或缓存值。
该接口没有 setter。

## 显式发射器识别诊断

自动接收器操作保持被动。可选 root-only debugfs 接口可在附着的普通 BPP 会话中发送
一次范围很窄的 vendor `GET_TX_ID` 查询。它不改变板模式、风扇、认证、充电权限、
输出电压、保护或功率传输策略。没有通用寄存器/消息写入器，也没有启动或周期查询。

目录为 `/sys/kernel/debug/<i2c-device>/`，其中 `<i2c-device>` 是接收器父设备名，
例如 `8-0036`。`query_tx_id` 只写、模式 `0200`，只接受 `1` 和可选换行。
`last_tx_id` 只读、模式 `0400`；读取不发命令。触发同步，受两秒事务截止和固定
mailbox 轮询限制。忙 Linux mutex 会拒绝触发，不消耗尝试也不写入。一旦开始，成功
或失败会消耗该附着的尝试；不会自动重试相同查询。

触发需要新的 NU1669 身份、附着 GPIO、BPP 协议 `04`、4.5–6.0 V 输出和两个直通
指示都关闭。它只发送五个字节 `18 05 00 00 00`。它清空陈旧接收事件，在 execute
前观察 receive flag BIT10 清零，然后要求新的 BIT10 事件和两个一致的六字节回复
（以 `5f 05` 开头）。仅 packet-send-success 不够。只通过固件对象 `28`、掩码字节
`00 04 00 00` 确认 BIT10；无关 sticky 位保留。新故障位、丢失无关证据、畸形帧和
不明确的 I2C/超时结果会使尝试失败。Busy 永不强制释放。

窄 ACK 解释遵循 OEM 掩码接口，仍需硬件验证。固件不提供事务 ID，因此已附着的首次
查询可能保留与早期固件请求的歧义。物理观察到的 detach 和之后 reattach 提供更强
新鲜度证据；仅 boot、reprobe、suspend 或逻辑代际变化不能证明接收器复位。失败
尝试保持隔离，直到物理转换和成功的新保护/事件清空。驱动未观察到的缺失不能重新
武装查询。

结果报告 `sequence`、捕获的 `generation`、数字 `status`、
`physical_attach_verified`、`quarantined` 和初始/最后原始事件标志。`reply` 只在
成功回复确认且附着/代际仍当前时包含六个原始字节；否则为 `unavailable`。这些是
vendor 发现字节，不是 OAWV09 型号验证、认证身份、请求板模式或充电效果。任何失败
后先检查诊断并保留证据；不要重复查询以试图消费迟到的回复。

同一接收器 debugfs 目录提供 root 可读 `fod_shadow`（模式 `0400`）。每次读取采样
现有 INFO 加精确 `21a0..21ca`：三个命令 shadow 字节后跟四十个参数 shadow 字节。
它报告 INFO 偏移 `18` 的 `magcvr_shadow`、`write_mode_shadow`、`length_shadow`、
`read_mode_shadow` 和 `parameters_shadow`。这些是原始 mailbox shadow，不是确认
活动或已应用的 FOD 校准、实时磁吸壳传感器读数，也不是保护启用/禁用的证明。即使
表匹配、零填充块或不寻常长度也不能建立这些语义。

该诊断用新的身份、存在和代际检查夹住两次匹配块读取，拒绝撕裂、变化、suspend、
停止或失败读取，不返回缓存/部分输出。它不发送 FOD 读/写命令、校准、确认或发射器
查询，也不读额外 RAM。读取它不会清除查询隔离，也不替代另一次 GET05 尝试所需的
物理 detach/reattach。

## 检查电池和接收器状态

```sh
bat=/sys/class/power_supply/qcom-battmgr-bat
for name in status current_now capacity temp charge_behaviour; do
  printf '%s=' "$name"; cat "$bat/$name"
done
rx=/sys/class/power_supply/nu1669-receiver
for name in present online voltage_now current_now; do
  printf 'receiver_%s=' "$name"; cat "$rx/$name"
done
```

Linux 电池 `current_now` 单位为微安：正流入电池，负流出。温度单位十分之一摄氏
（`330` 为 33°C），容量为百分比。接收器电压/电流单位微伏/微安。接收器
PRESENT/ONLINE 表示附着/输出可用，不证明电池充电。`charge_behaviour` 描述 Linux
手动权限所有权，与实际状态和电流分开。

## 有界普通输入请求实验

受监督开发时，`/sys/kernel/debug/qcom-battmgr-dodge/normal_input_probe` 为 root
只写（`0200`）。精确 `1` 启动一次固定 750000µA 无线输入请求；精确 `0` 请求清理，
都可选换行。没有可配置电流/时长、启动获取或 resume 获取。这是普通 BPP 输入和
手动电池暂停/恢复的开发测试，不是日常初始化或充电修复。750mA 上限和组合试验
需要独立净充电和暂停/恢复测量。它不改变 BATT 权限、FCC/FV、接收器、FOD、认证
或电压设置。原始 `wireless_input_current_limit` 文件仍只读。

启动需要 AUTO 且无电池暂停所有者、新的 BATT permission1、健康温度、稳定普通
BPP/直通关闭接收器身份、无 USB/CID/OTG 输入且 AP OTG 关闭。有效启动在 preflight
I/O 前消耗驱动内置的 boot-lifetime 尝试；之后保护拒绝仍消耗。本地启动忙锁、无效
输入和模块化构建不发请求。模块化启动被禁用。服务重启、suspend 和驱动 reprobe
不能重置消耗。Reprobe 还保留 boot-global possible-owner 标志：实例上下文丢失
不表示未知固件请求消失。

请求在 SET750000 前拥有 possible 状态，只接受匹配的 opcode/property/result ACK。
**GET8 不是请求限制回读：** 原始诊断可能保持零，而输入请求改变接收器功率。零
响应或与任何请求一致都不能证明原始或有效应用限制。Android 同名输入限制字段来自
GKI/MMS 接收器电流遥测，不能验证固件 GET8。实验中和清理后必须独立测量接收器
功率和电池电流。

固定绝对 45 秒软件截止在 SET 前武装。周期和事件驱动检查在源不健康/变化时结束
请求；通用 WLS 通知触发新验证，而不是称为 detach。显式 `0`、截止、suspend 和
teardown 请求 SET0 清理，不依赖健康或可读接收器。成功清理只报告匹配 ACK，不
声称原始/有效恢复或硬件功率回到基线。标准手动 INHIBIT API 只在同一实例拥有
确认、健康、未过期且 start ACK 匹配服务/接收器的输入请求时允许。UNKNOWN 或
孤立输入所有权仍阻止。没有确认匹配手动暂停而门已为零属于外来，会结束输入请求；
永远不会静默使能。

确认的手动暂停可在输入请求仍活动时保持电池 permission0。AUTO 只恢复自有电池
permission1，并保留有效输入请求。输入过期/清理仍只请求 SET0，与电池暂停独立。
受监督试验必须在输入截止前安排单独的 AUTO 清理，并检查两个所有权状态。现有
电池会话 epoch 失效不变：通知可能结束暂停，而不是为让实验成功而过滤。

不明确交付、丢失/畸形 ACK 或服务代际丢失变为 UNKNOWN。不尝试相同重试或转移到
新服务：迟到的 SET750000 ACK 不能安全用作 SET0 清理证据。清理未解决时拒绝
suspend；teardown 明确报告 UNKNOWN。看门狗是串行软件工作，调度延迟或固件传输
不可用可能阻止及时清理请求；它不是保证的物理切断。不要重复失败触发，也不要把
新启动当作接收器复位或有效恢复的证明。

root 可读 `normal_input_probe_status`（`0400`）报告 phase、boot 消耗、
possible/instance 所有权、frozen 状态、stage、failure stage、reason、error、
start/cleanup ACK 结果、捕获/当前服务代际、接收器代际、截止和剩余毫秒。它还报告
`charge_owned`、`charge_pending`、`charge_frozen`、`charge_epoch` 和
`charge_session_epoch`，用于诊断独立手动电池会话。ACK result0 表示匹配成功 ACK；
负值表示错误或不可用 ACK，不是有效限制测量。`UNKNOWN_OWNER_UNAVAILABLE` 在实例
丢失后保留未解决的 boot-global 请求。保留该证据，不要再发请求。

对于新取得资格且无有线输入的 NU1669 BPP/直通关闭 4.5–6V 路径，Dodge 电池
`status` 使用新 gauge 电流：高于 +50000µA 为 `Charging`，低于 −50000µA 为
`Discharging`，±50000µA 闭区间为 `Not charging`。只有明确、新获取的固件 `Full`
保留在该区间；SOC 本身永不产生 `Full`。有线、缺失或未取得资格的接收器路径保留
固件状态。附着 provider、gauge 和变化 source/service 错误会使读取失败，而不是
显示缓存状态。验证的 gauge 还会刷新 `current_now` 的短缓存，使同一 uevent 中
STATUS/current 可比。这是报告，不是充电 setter；策略抑制和电流稳定不必瞬时。

电池管理器 debugfs 目录中 root 可读 `normal_voltage_samples`（`0400`）请求一次
新的现有 OEM gauge 回复，只报告 `word2_raw`、`word13_raw`、`declared_words` 和
`generation`。该诊断至少需要十四个声明字；九字 current/SOC/temp 响应仍支持，
仅为可选对返回 `ENODATA`。畸形、缺失、超时或代际变化的回复不发布缓存或部分对。
没有 setter、BCC 请求或整缓冲 dump。

固定的 normal-ADSP 源码暗示 word2 是微伏缩放的最大电压候选，word13 是毫伏缩放
的最小电压候选。文件故意打印原始值：电芯/极值身份和缩放在运行时未验证，它们不是
标准 `voltage_now` 或已建立的满充/保护限制。
