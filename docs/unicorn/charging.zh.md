# Unicorn 有线快充

已实现可选的小米认证服务、独立的 Unicorn battmgr 属性表及输入功率采样。
主机测试和 ARM64 驱动编译已通过；尚未完成实机协议、充电泵、回退及
120W 峰值验收。认证成功并不代表实际输入达到 120W。

## 启用

在 Unicorn 的正常系统配置中加入：

```nix
services.xiaomi-mipps-auth.enable = true;
```

默认关闭，recovery 不运行服务。沿用现有 ADSP 固件和固件温控/保护。
服务启动时处理已经插入的充电器，持续观察 Type-C partner、USB online
和 ADSP 会话编号；插拔、固件重启或认证标志丢失后重新认证。
失败采用有上限的重试间隔，普通 PD/电脑 USB 不提交小米认证结果，
也不请求切换数据角色。

原装套装实测发现：设备初始为 device 数据角色时，小米 SVID 可能保持 0；
请求 host 数据角色后，出现 `SVID=2717`、适配器 ID `a565`，且有一次完整
摘要认证成功记录。若明确连接的是小米充电器，可显式启用发现：

```nix
services.xiaomi-mipps-auth.allowDataRoleSwap = true;
```

也可单次运行 `sudo unicorn-mipps-auth --allow-data-role-swap`（先停止后台服务，
避免认证锁冲突）。此选项可能影响 USB 数据连接，默认关闭；只改变数据角色，
不改变供电角色。未发现小米 SVID 时恢复原来的 device 数据角色。
服务保存本次连接经过摘要验证的结果；同一连接下重启服务不会重复挑战。
更换连接、ADSP 会话变化或固件清除认证标志后仍需重新认证。
实测中重复挑战曾返回挑战原文而非摘要，这种回复继续按失败处理，不冒充成功。

```sh
journalctl -u xiaomi-mipps-auth -b
sudo unicorn-mipps-auth --diagnose
sudo unicorn-mipps-auth --sample --duration 600 --interval 2 > unicorn-charging.csv
```

后两个命令只读，可以直接安装 `androidPackages.devices.unicorn.mipps-auth`
而不启用服务。采样记录认证、适配器能力、充电泵、电池电量和温度，
以及 USB `voltage_now`、`current_now` 和二者乘积 `usb_input_watts`。
读取失败保留 `error:<errno>`，不冒充零值。CSV 为固件遥测，必须再用
支持小米协议透传的外部功率计核验；电池侧功率不可代替适配器输入功率。

常规诊断跳过尚未验证的扩展固件属性，显示 `not-probed`。需要调查时使用
`--diagnose --extended`；实机上扩展属性曾超时，可能暂时阻塞共享的认证通道。
遇到超时后，本次采样不再读取后续 Xiaomi 属性，仍记录标准 USB 和电池数据。
电池节点优先使用本机实际的 `qcom-battmgr-bat`。满电时的低输入功率不能用于
验收峰值；应在低电量、相近温度条件下比较。

## 协议依据与限制

依据 Xiaomi 的 [原厂驱动](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/blob/fa4513e61931e11a59e3f177ae590d4e090d7229/drivers/power/supply/qti_battery_charger.c)
和 [Unicorn 配置](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/blob/fa4513e61931e11a59e3f177ae590d4e090d7229/arch/arm64/configs/vendor/unicorn_GKI.config)：

- USB 类型读取 `USB_ADAP_TYPE=7`。Xiaomi GET/SET opcode 为 `0x50/0x51`，
  使用 Unicorn 属性表，不使用 sheng 编号。
- 标量请求/回复各 24 字节，VDM 请求/回复 32 字节；电池摘要报文 52 字节，
  包含 32 字节摘要、主电量计标志 0 和三个清零的填充字节。
  摘要保持字节顺序，VDM 按原厂规则转换每个 32 位字。
- 原厂配置启用 `CONFIG_BQ_FUEL_GAUGE`，未启用 `CONFIG_BQ_FG_2S`，
  此配置采用单主电量计认证。复用
  [开源认证程序的固定版本](https://github.com/ianchb/xiaomi-mipps-auth/blob/9176efbdf276b874fc0a97912a914449a88155fb/xiaomi-mipps-auth)
  的密钥表、HMAC 和 VDM 实现。每个新连接重新挑战校验，只有匹配摘要后
  才提交正认证结果。实际电池/适配器不接受这些密钥时保持认证失败。
- 原厂灭屏属性为 `FB_BLANK_STATE=0x57`，亮屏 0、灭屏 1。
  服务读取内置 DSI 连接器的真实 DRM `dpms` 状态；未知、多连接器或
  非 Off 状态按亮屏处理。每两秒轮询，认证过程中同步检查显示状态。
  这不使用亮度值或锁屏状态推测灭屏。
- `SPORT_MODE=0x5a` 的原厂用户空间/温控配套策略尚未复现。
  服务写 0，内核接口拒绝写 1；不提供启用加速选项。
  不开放温控移除、伪造温度、电流上限等调试写入接口。
- 该固件协议没有事务编号。Xiaomi 请求超时后暂停此通道，直到迟到回复
  被消费或 ADSP/PDR 重建会话，防止旧回复错误完成下一次认证。
  若固件永不返回且未重启，仅拔插并不能解除此状态；诊断会显示 EAGAIN。
- 本实现要求一个可识别的 Type-C partner 和 Xiaomi SVID。若固件未公布
  SVID/PDO，默认保持等待；只有显式启用上述选项后，才对未知 SVID 的 PD
  连接尝试 host 数据角色发现。普通 USB 或已知其他厂商 SVID 不进行此操作。

## 硬件测试

以下项目目前均为**待实测**。使用原装 120W 适配器和原装线缆，以低电量、
相近温度、相同灭屏状态，在本系统和同机原厂系统分别记录。不要为追求峰值
关闭保护或人为设置温度。120W 按短时峰值验收，不要求持续维持。

| 场景 | 需要记录的证据 |
| --- | --- |
| 原装套装，开机已插电 | 日志、`authentic` / `pd_verifed`、适配器 ID/SVID/PDO/APDO |
| 原装套装，亮屏及灭屏 | DRM dpms、`fb_blank_state`、`sport_mode=0`、充电泵状态和两路输入电流、温度、CSV 曲线 |
| USB 拔插、ADSP 正常重启 | partner / 会话编号变化后重新认证；旧会话不提交正结果 |
| 普通 PD、电脑 USB | 正常充电/数据功能，未认证、不切数据角色 |
| 电池或适配器认证失败 | 正结果不提交，普通充电回退；不要在实机强写成功标志 |
| 120W 峰值 | 协议透传功率计的电压、电流、采样率、峰值持续时间及截图/原始记录 |
| 原厂系统对比 | 相同套装/功率计、相近 SOC/电池温度/环境温度/灭屏条件下的输入曲线 |

最终分别报告：电池摘要是否通过、适配器协议认证是否通过、充电泵是否运行、
固件输入遥测峰值、外部功率计峰值。适配器能力字段和快充图标均不能替代实测。

## 主机验证

`unicorn-charging` flake check 将完整 Unicorn 补丁队列应用到锁定的 Linux
源码，再运行真实 C 消息路径的 ASan/UBSan 测试和 Python 认证/重试测试。
`unicorn` 配置测试验证默认关闭、启用后的常驻服务和 recovery 不启动服务。
实机验收与主机检查分开进行。
