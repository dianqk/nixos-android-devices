# Aurora 连接功能准备

[设备指南](README.zh.md) · [ADSP 固件](firmware.zh.md) · [English](connectivity.md)

| 功能 | 状态 |
| --- | --- |
| USB2 ACM/NCM | recovery 和已安装系统中可用 |
| USB3 ACM/NCM（device 模式） | 已安装系统中以 5 Gbit/s 运行 |
| ADSP 电池信息上报、Type-C device/sink | 可用 |
| USB 主机模式、数据角色切换 | 尚不支持 |
| DisplayPort | 基本画面输出可用；DP 音频、其他模式、长时间运行及与 USB3 共存未验证 |
| Wi-Fi | 2.4/5 GHz 扫描、5 GHz 关联及双向传输可用 |
| 蓝牙 | BR/EDR 和 LE 配对、加密 L2CAP 数据及 GATT 读取可用；音频 profile、HID/PAN 及与 Wi-Fi 共存未验证 |
| 蜂窝基带 | 实验性；见[蜂窝基带](#cellular-modem-experimental) |

以上结果均以要求的原厂底包 OS1.0.3.0.UNACNXM（Android 14）为前提。

## ADSP 与 Type-C

`devices.aurora.firmware` 产物包含原厂拆分的 ADSP 镜像和服务描述文件。全部 61 个
文件都按 SHA-256 清单校验；主机端 MDT 检查确认所需加载段存在、大小与声明一致，
并且位于 Aurora 的保留内存区域内。板级配置启用 ADSP，并把主固件和 DTB 固件都放入
initrd，供内建 PAS 驱动使用。

连接器图使用 OTG，默认 peripheral。固定 peripheral 模式不会注册 DWC3 角色开关，
UCSI 会因此耗尽延迟探测重试次数。device/sink 角色、ACM/NCM 和电池读取可以同时
工作；USB 主机模式尚不支持。电池上报会转换 Aurora 原厂的属性 ID 和电流符号。
固件给出的 `power_now` 是常量，因此标记为不可用，而不是当作实测功率。USB 输入
受限时，状态显示 `Charging` 的同时电池可能仍在净放电；应检查 `current_now`、
`charge_counter`、温度和协商得到的输入上限。不要把输入上限提高到超出所连电源的
能力。

主线 [SM8650 HDK 描述](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/arch/arm64/boot/dts/qcom/sm8650-hdk.dts?id=72d3fcf802c45d00b300f25b848a93c3a2bd7c7e)
是最接近的 Type-C 图参考。原厂 Aurora 数据表明 WCD9395 位于 I2C 地址 0x0e，
复位为 GPIO152，供电为 L15B 1.8 V。I2C3 属于 QUPv3 ID0，使用 GPI DMA1。该图需要
GLINK HS/SS/SBU 端点、控制器角色开关、combo PHY 方向和 DP 控制器。QRD 额外的
NB7VPQ904、Sheng 的 PS5169 和 Asphalt 的 FSA4480 属于不同的板级连线。

combo PHY 供电为 `vdda-phy` = L3G（0.88–0.912 V）和 `vdda-pll` = L3I（1.2 V）。
连接器具有独立的 HS、SS 和 SBU 端点；DP0 已启用。原厂 Aurora 的
`usb3phy_portselect_default` 表明 GPIO29 是线缆方向信号。`orientation-gpios`
将其连接到 UCSI，使 combo PHY 选择正确的通道；缺少它时，反插线缆会保持 PHY 的
默认方向，USB 回落到 480 Mbit/s。
WCD9395 开关驱动内建在内核中，因为共享的 recovery initrd 有意不包含任何内核模块。

### USB3 运行

USB3 device 模式（ACM/NCM）在已安装系统中以 5 Gbit/s 运行。检查链路时，主机的
`lsusb -t` 必须显示 `cdc_ncm`/`cdc_acm` 为 `5000M`，手机的 UDC 必须报告
`super-speed`；仅配置 SuperSpeed 上限并不能建立该链路。集线器、主机外设及与 DP
共存未验证。

如果内核报告 UCSI PPM 复位超时，请保留日志，不要屏蔽该错误。USB2 链路正常不代表
Type-C 角色管理已经完成初始化。

### USB 角色

板级配置使用 `dr_mode = "otg"`、默认 peripheral、DWC3 角色开关和双角色 Type-C
连接器。UCSI、combo PHY、WCD9395 和 xHCI 主机支持均已保留，recovery 内核中也是
如此。用以下命令读取协商状态：

```sh
cat /sys/class/typec/port0/data_role
cat /sys/class/typec/port0/power_role
cat /sys/class/typec/port0/orientation
cat /sys/class/usb_role/a600000.usb-role-switch/role
```

向 Type-C `data_role` 属性写入 `host` 或 `device` 会与支持数据角色交换的对端发起
PD 协商。数据角色切换尚不支持：请求在手机端超时（或被对端拒绝），端口保持
device/sink。此类测试请使用本地控制台或 Wi-Fi，因为主机模式下 NCM 会消失。不要为
绕过被拒绝的协商而在另一台活动主机存在时强制 DWC3 进入主机模式。现有用户态接口
及其供电/角色限制见 [USB 模式](../usb-signaller.zh.md)。

### USB 负载下的触控响应

触控驱动为其专用的线程化 IRQ 设置 FIFO 优先级 51，比默认 USB IRQ 优先级 50 高
一级，使饱和的 NCM 传输不会把触控读取推迟到控制器丢帧的程度。持续 USB 饱和期间
的触控精度尚未经过交互检查。

这不会改变 SPI worker 或共享 workqueue 的优先级。格式错误、溢出或不连续的帧仍会
触发安全的输入释放/恢复；诊断信息会报告两个序列计数器和读取间隔。

### 解读剩余的 Type-C 日志

PMIC-GLINK 的 `Failed to create device link (0x180)` 消息可能描述的是在 UCSI 注册
连接器设备之前创建的父级代理。在正常工作的系统上，最终的 Type-C 端口具有指向
WCD9395、QMP 和 DWC3 的 supplier 链接：

```sh
ls -l /sys/class/typec/port0/supplier:*
```

该警告仍未解决；它本身不能证明缺少运行时依赖，也不能说明 DP 故障的原因。应检查
端口注册、实际的 supplier 链接和协商状态。不要以删除 firmware-node 链接或全局屏蔽
driver-core 警告作为绕行方案。

被拒绝的数据角色请求会向固件发送 SET_UOR，固件持续报告 BUSY 直到命令超时；随后
UCSI 错误处理路径会复位 PPM 和连接器。这并不是角色切换缓慢，因此延长角色切换等待
时间无济于事。

<a id="displayport"></a>
### DisplayPort

原生 MSM DP 控制器、combo PHY 和 GLINK HPD 桥会注册 `DP-1` 连接器；未接显示器时
显示 `disconnected` 属于正常。WCD9395 提供 SBU/AUX 通路；不得把 Sheng 的 PS5169
redriver 照搬到 Aurora。

外接 DP 显示器的基本画面输出可用。DP 音频、其他模式、长时间运行及 DP/USB3 共存
未验证。扩展坞上的主机 USB 设备依赖 USB 主机模式，目前尚不支持。检查已连接的
显示器：

```sh
niri msg outputs
for connector in /sys/class/drm/card*-DP-*; do
  cat "$connector/status"
  cat "$connector/modes"
done
journalctl -k -b | grep -Ei 'displayport|dp_aux|link.train|ucsi|glink|usbss'
```

仅有连接器节点或 EDID 不能证明显示输出正常；应确认链路训练完成并有稳定可见的
画面。

## WLAN 与蓝牙

原厂日志表明 WCN7850 PCI 17cb:1107，并成功加载 `kiwi/amss20.bin` 和
`kiwi/bd_n1.elf`。后者是来自 ROM 的板级数据，而不是逐机 NV 回读。CNSS2 源码确认
`phy_ucode20.elf` 是 M3 载荷。[无线固件包](firmware.zh.md)保留匹配的原厂四件套，
并按实测的 PCI/QMI 键打包 BDF/REGDB。PCIe Gen2×2、MHI、QMI、BDF/REGDB/M3 下载及
WMI service-ready 均已通过。仅用于 Aurora 的 QMI 资源声明避免了此原厂固件在 WMI
初始化时进入 RDDM。它参照
[Houji 实现](https://github.com/yoni13/armada-houji/blob/f5c689be6e603b259a5a85774d78c9cbd7cfefa4/ports/houji/patches/0013-ath12k-houji-stock-qmi-mlo.patch)
和厂商 CNSS2 Kiwi 拓扑（一颗芯片、两条链路、32 个 peer），不启用主机 MLO，也不
修改 RX 环。5 GHz 80 MHz EHT/NSS2 连接和双向传输可用；吞吐量和 Wi-Fi 一致性未
测量。WMI 初始化失败后，避免卸载/解绑 ath12k：其清理路径可能解引用未分配的
radio。保留日志并通过独立的管理通道重启；此故障与固件断言是不同的问题。蓝牙的
GENI UART 还需要显式的 `serial1` 别名。

WLAN_EN/BT_EN 为 GPIO16/17；PCIe0 使用 PERST94/CLKREQ95/WAKE96。共享 WCN PMU
供电依次为 S4I、L15B、L3C、S2C、S3C、S1C 和 S6C。转换原厂连线时保留额外的 L6K
1.8 V 天线共享供电。上游
[SM8650 QRD 描述](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/arch/arm64/boot/dts/qcom/sm8650-qrd.dts?id=72d3fcf802c45d00b300f25b848a93c3a2bd7c7e)
是拓扑参考，不能替代 Aurora 的电压约束。复用的 QRD 拓扑采用 BSD-3-Clause 许可，
Copyright (c) 2023, Linaro Limited。

蓝牙使用位于 0x898000 的 UART14。BTFM 中有 Hamilton 固件/NVM 文件，原厂日志表明
ROM2.0、board ID0，并回退到 `hmtnv20.b2e`。DT 显式选择该限定范围的 NVM 和 patch
文件名。L6K 是 PMR735D 天线共享供电；在共享使用方的生命周期尚未确定期间，它保持
在原厂 1.8V 开启。PCIe 使用共享的上游可变 IOMMU-cell SID 解析修复。不要复用其他
设备的 MAC 地址或其休眠/ath12k 绕行方案。PCIe SID 映射、QMI/固件启动、关联、
重连、配对/音频及 Wi-Fi/BT 共存属于不同的验证阶段。

### WCN7850 法规频段范围

Aurora 使用已为 Sheng 引入的共享
[单 pdev 法规修正](../../pkgs/linux-kernel/patches/ath12k-single-pdev-reg.patch)。
当所选国家没有 6 GHz 规则时，5/6 GHz 合一的 radio 必须保留其允许的 5 GHz 范围。
该补丁还使用 nl80211 频段索引查找各频段能力。它不会启用固件法规数据禁止的信道，
也不修复跨 pdev 共享状态的竞争。

### 蓝牙状态与配对

从任一端发起的 BR/EDR 配对（数字比较）、双向加密 L2CAP 数据（安全级别 4，
AES-CCM），以及 central 和 peripheral 两种角色的 LE 连接（含 GATT 服务发现和
读取）均可用。独立的仅 LE 配对、GATT 通知和批量写入、音频 profile、
HID/PAN/OBEX、通信距离、休眠/恢复及持续的 Wi-Fi 共存未验证。

请求配对前先开启电源和可配对状态，并核对两端的数字比较提示。可发现或可配对窗口
可能过期；在把认证被拒诊断为固件故障之前，先确认其当前状态。对于已建立的 BlueZ
GATT 连接，使用其 GATT D-Bus 客户端，不要在同一链路上再打开第二个原始 ATT 客户端。

### 逐机蓝牙身份

在 `&uart14` 的 `bluetooth` 子节点上，以 `local-bd-address` 提供本机自己的
Android 蓝牙地址，编码为六个小端字节。Nixpkgs 设备树 overlay 的 `filter` 是字面
子串：使用 `qcom/sm8650-xiaomi-aurora.dtb`，不要使用通配符。先在最终构建的 DTB 中
核对地址，重启后再用 `bluetoothctl show` 确认。通用的出厂 NVM 不包含本机身份；
缺少该配置时，即使固件下载成功，HCI 仍处于未配置状态。请把个人地址和校准数据放在
这个公开软件包之外；其固件 override 支持经过验证的私有 NVM。

<a id="cellular-modem-experimental"></a>
## 蜂窝基带（实验性）

板级 DT 启用 MPSS remoteproc、IPA v5.5 和静态 rmtfs 共享内存。原厂 Android 14 的
基带保留区域与 `sm8650.dtsi` 一致。在实机上，MPSS 能够启动，QRTR 服务集合与
Android 一致，ModemManager 能检测到 SIM 并注册到 LTE/5G NR，IPv4 和 IPv6 移动数据
可用，短信可以收发。这需要下文的许可服务，包括 `license.qwesd`：缺少它们时，基带
会在首次（约 3 分钟）或周期性（约 15 分钟）Smart Transmit 许可证检查后停止。语音
通话不在支持范围内。内核带有
[QRTR HELLO 与服务通告修复](../../pkgs/linux-kernel/patches/qrtr-hello)，使基带在
启动期间能找到 rmtfs 和 TFTP。

在使用 Android 14 底包的已安装系统（而非 RAM recovery）中启用。共享选项见
[基带与 QTEE 服务](../modem.zh.md)。`hardware.aurora.modem` 向共享的
`androidDevices.modem` 模块提供 Aurora 的 remoteproc、NV 分区、固件和许可服务，
通用设置由后者负责：

```nix
hardware.aurora.modem.enable = true;
androidDevices.modem = {
  startAtBoot = true; # false: start modem-mpss.service manually
  allowNvWrites = false; # default: modem NV writes stay in RAM
};
```

短信无需额外模块：ModemManager 负责收发（`mmcli
--messaging-create-sms`）；短信或拨号应用属于桌面环境的选择。

| 组件 | 行为 |
| --- | --- |
| 固件 | 固件包中独立的 `modem` 输出：modem、modem DTB 和 IPA 拆分 MDT，以及基带的只读 TFTP 目录树。仅安装在根文件系统中，从不放入 recovery。 |
| `modem-tqftpserv.service` | 从包含 `modem.mdt` 的目录提供 `/readonly/firmware/image/`；可写请求转到 `/var/lib/tqftpserv`。 |
| `modem-rmtfs.service` | `rmtfs -P -v [-r]`：按分区标签提供 `modemst1`、`modemst2`、`fsg` 和 `fsc`。它不负责启动或停止 MPSS。 |
| `modem-mpss.service` | 最多等待 `timeSyncTimeout`（120 s）直到系统时钟同步，然后在上述服务之后通过 remoteproc sysfs 启动 MPSS，并拉起 SIM 激活和 ModemManager。停止该服务时（包括关机时），仅当 MPSS 处于 `running` 状态才写入 `stop`；崩溃的 MPSS 保持原状。 |
| `modem-sim-provision.service` | （`simProvisioning`，默认开启）检测到 USIM 10 s 后，若基带仍未激活主 GW provisioning 会话，则用 `qmicli` 为第一张 USIM 激活该会话；随后启动 ModemManager。 |
| Smart Transmit 许可证（`license.enable`，默认开启） | `qtee-supplicant.service`（minkipc），写权限仅限 `/persist/data/pfm`；以及 `mink-modem-opener.service`，为基带的 QTEE 会话发布 QRTR 服务 5013。见 [QTEE](#qtee-与基带许可证)。 |
| QRTR 名称服务与 PD mapper | 位于内核中（`net/qrtr/ns.c`、`QCOM_PD_MAPPER`）；无用户态守护进程。 |
| ModemManager | 默认启用，通过 QRTR 使用 libqmi；随 MPSS 启动。 |
| IPA | 未启用基带支持时，`ipa` 模块被列入黑名单。内核带有 [IPA v5.5 配置修复](../../pkgs/linux-kernel/patches/ipa-v5.5-config.patch)（上游 RFC）：主线的 v5.5 端点表对应的是 IPA 5.0/5.1，导致基带下行数据被送到 AP 从不读取的端点。 |

SM8650 PAS 驱动保持 `auto_boot` 关闭，因此 `modem-mpss.service` 会在 QTEE
supplicant、modem opener、tqftpserv（基带通过 TFTP 读取运营商配置）和 rmtfs 就绪
后启动 MPSS。rmtfs 和 tqftpserv 使用 `Restart=no`，且除非设置
`androidDevices.modem.crashRecovery = true`，MPSS 崩溃恢复处于关闭状态，因此出错
的基带会保持离线，而不是循环重启。

停止并重新启动正常运行的基带（`systemctl restart modem-mpss`）可用：内核带有一项
[PAS 修改](../../pkgs/linux-kernel/patches/pas-reassign-exclusive-regions.patch)，
与 Android 驱动一样，在每次停止后把基带独占的 DSM 内存交还给 Linux，并在下次启动
时重新分配；在此之前，重启基带会使手机在基带恢复几秒后硬复位。设置
`crashRecovery = true` 时，内核在崩溃后以同样方式重启基带。从真实基带崩溃中恢复的
情况尚未观察到。

`allowNvWrites = false` 时，rmtfs（`-r`）只读取每个 NV 分区一次，并把基带的写入
保留在内存中；rmtfs 停止后这些写入会丢失。服务的设备 cgroup 也只允许对这些分区
进行读访问。允许写入前先备份 `modemst1`、`modemst2`、`fsg` 和 `fsc`；切勿恢复
其他手机的 NV 数据。

检查一次测试启动：

```sh
systemctl start modem-mpss.service
cat /sys/class/remoteproc/remoteproc*/name /sys/class/remoteproc/remoteproc*/state
journalctl -b -u modem-mpss -u modem-rmtfs -u modem-tqftpserv \
  -u qtee-supplicant -u mink-modem-opener
qrtr-lookup
mmcli -L
```

已知缺口：原厂内核会响应基带的 `qcom,memshare` 请求；主线没有 memshare 服务，
对该基带的影响未知。内核内的 PD mapper 列出了原厂基带的 `root_pd`
（`gps/gps_service`），但没有其 `oem_pd`（`oempd/srv1`）描述符。

### QTEE 与基带许可证

基带固件在启动约 190 s 后检查 QTEE 所保存的 Smart Transmit 许可证，无法检查时以
`Smart Transmit License Check Failure` 停止。在 Android 上，`ssgtzd` 发布 QRTR
服务 5013（`IMinkModemOpener`）；基带通过它在 QTEE 中打开 `CTunnelInvokeMgr`
（UID 124），QTEE 则通过 supplicant 的文件系统监听器读取和更新位于
`/persist/data/pfm` 的许可证存储。

`androidDevices.qtee` 基于上游 QCOMTEE 驱动，用
[minkipc](https://github.com/qualcomm/minkipc) 提供开源的等效实现：

- `supplicant`：`qtee_supplicant`，包含文件系统、时间、RPMB 和 TA 自动加载
  监听器。由需要它的服务拉起。
- `persist`：把 persist 分区挂载到 `/persist`（`nodev,nosuid,noexec,
  noatime`，不自动 fsck）。所请求路径的目录存在时，监听器按原样使用该路径。
  Aurora 的 QTEE 请求 Android 的 `/mnt/vendor/persist/data/...`，因此
  `persist.androidDataPath` 把 `/persist/data` 绑定到该处；只绑定这一个目录，
  根文件系统上 `/mnt/vendor/persist` 的其余部分（传感器 registry 数据）仍然可见。
  supplicant 只能写入 `persist.writablePaths`（Aurora：`/persist/data/pfm`，同样
  经由该绑定），分区的其余部分（校准数据和其他安全文件）对其保持只读。
- `modemOpener`：`mink-modem-opener`，即运行在 MinkSocket QRTR 传输上的 minkipc
  `MinkModemOpener`，不包含 HLOS Mink 守护进程中仅限 Android 的部分。与厂商
  `ssgtzd` 一样，它会保留每个基带客户端注册的对象（最多 10 个），直到该客户端将其
  注销。若 QTEE 拒绝默认值，`clientUid` 可在 QTEE 客户端凭据中使用其他 UID
  （Android 的 `ssgtzd` 以 1000 运行）。

基带运行期间会保持在桥接程序中注册的对象和 QTEE 会话处于打开状态。因此
`nixos-rebuild switch` 不会重启 modem、rmtfs、tqftpserv、supplicant 或桥接单元；
需重启系统使其改动生效。MPSS 运行期间不要手动重启 `qtee-supplicant` 或
`mink-modem-opener`；重启 supplicant 不会重启桥接程序。

在 MPSS 启动前设置好时钟。RTC 不可用，因此时间来自 NTP；在时钟未设置时启动的
MPSS 会在初始化中停滞（约 40 s 后出现 `DOG detects stalled initialization`）。
没有网络时，启动会在超时后继续，因此离线手机应先设置时钟（`timedatectl set-time`）。

诊断时，`modemOpener.trace` 记录经过桥接程序的基带与 QTEE 之间的每次调用（方法
编号、参数数量和大小、结果、耗时及对象释放），`modemOpener.transportTrace` 增加
MinkSocket 自身的跟踪，`supplicant.debug` 记录每个文件系统和时间监听请求及其解析
后的路径：

```nix
androidDevices.qtee = {
  supplicant.debug = true;
  modemOpener.trace = true;
};
```

```sh
journalctl -b -u qtee-supplicant -u mink-modem-opener
```

- `qwesd`（需显式启用，非自由）：高通为 Qualcomm Linux 预编译的 QWES 守护进程，
  构建时从高通下载。它提供 QMI QTEE 许可服务。在 Aurora 上，基带会在启动约 15 分钟
  后重复 Smart Transmit 检查，检查失败即停止；设置
  `hardware.aurora.modem.license.qwesd = true` 可在 MPSS 之前运行该守护进程。
  它只能使用 QRTR 和 Unix 套接字（无 IP 网络），只写入 `/var/cache/qwes`，并且
  不会自行重启，也不会因 switch 而重启。需显式允许该软件包：

  ```nix
  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) [ "qwesd" ];
  ```

  其许可证（`LICENSE.qcom-2`，随软件包安装）仅允许针对高通芯片组再分发二进制文件，
  并禁止逆向工程。高通可能撤下该下载（meta-qcom 已不再获取它）；如果保存了
  `qwes_1.0_armv8a.tar.gz`（SHA256
  `7bb20daa916e4b13e54948ab90af92e9c2e6129cc22da1a23b924adb3f0610d4`），先将其加入
  store：`nix-store --add-fixed sha256 qwes_1.0_armv8a.tar.gz`。

桥接程序根据厂商的 `libminksocket_vendor.so` 重建了 minkipc 未公开的少数定义
（`IPrimordial`、primordial 和通用对象句柄、`Object_OP_unwrapFd`），并省略了
QRTR 无法承载的关闭通知器和共享内存传输。
