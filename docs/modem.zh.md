# 高通基带与 QTEE 服务

[English](modem.md) · [模块边界](modules.zh.md)

两个共享模块在已安装系统中通过主线 remoteproc 驱动运行高通基带（MPSS），
RAM recovery 不使用它们。

- `androidDevices.modem`：为基带提供 NV 存储的 rmtfs、tqftpserv、启动和停止
  MPSS 的单元、SIM 激活，以及基于 QRTR 的 ModemManager。
- `androidDevices.qtee`：基于上游 QCOMTEE 驱动的 QTEE 用户态，供固件需要检查
  QTEE 所保存许可证的基带使用。

remoteproc、NV 存储和固件由设备模块提供；通常只需启用设备选项，无需直接配置
这两个模块：

| 设备 | 启用方式 | 说明 |
| --- | --- | --- |
| Aurora | `hardware.aurora.modem.enable = true;` | 实验性。支持注册网络、移动数据和短信；需要 Android 16 底包 OS3.0.308.0.WNACNXM 和许可服务。见 [Aurora 蜂窝基带](aurora/connectivity.zh.md#cellular-modem-experimental)。 |
| Marble | `hardware.marble.modem.enable = true;` | 实验性，尚未在实机验证。rmtfs 读取 `modemst1`、`modemst2`、`fsg` 与 `fsc`（默认只读）、tqftpserv、内核 pd-mapper 与 ModemManager；不需要 QTEE 许可服务。 |
| Polaris | `hardware.polaris.radio.snapshotDirectory = "/path";` | 由 `rmtfs -s` 从已核验的只读校准快照启动 MPSS；不等待时钟同步，不做 SIM 激活，不集成 ModemManager。见 [Polaris](polaris/README.zh.md)。 |

## `androidDevices.modem`

| 选项 | 默认值 | 含义 |
| --- | --- | --- |
| `enable` | `false` | 启用基带服务。 |
| `remoteproc` | `null` | 基带 remoteproc 的设备名（例如 `4080000.remoteproc`）；`remoteproc-unit` 方式必填。 |
| `startMethod` | `"remoteproc-unit"` | `remoteproc-unit`：`modem-mpss.service` 通过 remoteproc sysfs 写入 `start`/`stop`。`rmtfs`：由 rmtfs 自行启动 MPSS，`modem-rmtfs.service` 为启动单元。 |
| `nvPartitions` | `[ ]` | rmtfs 提供的 NV 存储的 GPT 标签。 |
| `nvDirectory` | `null` | 改为从该目录中的文件提供 NV 存储（`rmtfs -o`）。与 `nvPartitions` 二选一。 |
| `allowNvWrites` | `false` | 允许 rmtfs 写回 NV 数据。为 false 时基带写入只保留在内存中，服务只能读取块设备。 |
| `startAtBoot` | `false` | 开机时启动 MPSS；否则手动启动 `modem-mpss.service`。 |
| `crashRecovery` | `false` | 基带崩溃后由内核自动重启 MPSS。 |
| `timeSyncTimeout` | `120` | 启动 MPSS 前等待 NTP 同步（启用 [`androidDevices.clock.rtcOffset`](configuration.zh.md#只读-rtc-的系统时钟) 时也接受已恢复的时钟）的秒数；`0` 关闭等待。 |
| `simProvisioning` | `true` | 若基带未自行激活，为第一张 USIM 激活主 GW provisioning 会话。 |
| `modemManager` | `true` | 启用 ModemManager 并随 MPSS 启动。打包的守护进程带三个本地修复：netlink 事务 use-after-free（第一次 QMAP 数据连接会崩）、IPA 基带上的 multiplexed-bearer 清理断言，以及 SDM845 及之后固件在 `Start Network` 之前必须的 `WDS Bind Subscription`（否则每次数据呼叫都以 `cm error: no-service` 结束）。 |
| `ims.enable`、`ims.package` | `false`、`pkgs._81voltd` | 通过 81voltd 和 ModemManager 提供基带请求的 IMS 数据连接，不修改 IMS 注册设置。 |
| `firmware` | `[ ]` | 基带固件包，只安装在根文件系统中。 |
| `rmtfsPackage`、`tqftpservPackage` | 打包的默认值 | 替换 rmtfs 或 tqftpserv。 |
| `rmtfsVerbose`、`rmtfsMemoryDevice` | `true`、`/dev/qcom_rmtfs_mem1` | rmtfs 日志与共享内存设备。 |

相关单元为 `modem-tqftpserv`、`modem-rmtfs`、`modem-mpss`（`remoteproc-unit`
方式）和 `modem-sim-provision`（启用 `simProvisioning` 时）。rmtfs 和 tqftpserv
不会自行重启，`nixos-rebuild switch` 也不会重启基带服务；需重启系统使改动生效。
崩溃的 MPSS 保持原状，不会被停止。

对于需要由 AP 提供 IMS 数据服务的基带固件，设置
`androidDevices.modem.ims.enable = true`。`modem-ims.service` 随 MPSS 启动，
排在 ModemManager 之后，提供 QRTR 服务 770。基带请求 IMS APN 和 IP 协议族；
普通数据连接保持独立。此服务提供 IMS 数据连接，注册和短信可用性仍取决于
基带固件和运营商。

停止 81voltd 不会断开已创建的 ModemManager bearer。手动重启前，记录其 IMS
bearer 路径，停止 `modem-ims`，再用 `mmcli` 仅断开、删除这些 bearer，保留普通
数据连接。重启系统可在应用配置改动时重新建立 bearer。

设置 `allowNvWrites = true` 前先备份 NV 分区，切勿恢复其他手机的 NV 数据。

### SIM 会话需要能写 NV

激活 primary GW provisioning 会话会写基带 NV（会话索引与卡状态）。NV 只读时固件回
`QMI error (3): Internal`，看起来像供电或 SIM 故障，其实不是：卡照样读得到
（ICCID、应用列表），供电也能用 `--uim-sim-power-on/off` 切换。
当基带自己不会建会话时，`simProvisioning = true` 要配 `allowNvWrites = true`。

蜂窝数据还需要让 NetworkManager 接管连接：ModemManager 直接起的承载能连上但没有流量；
用 NM 的 `gsm` profile（填运营商 APN）才会配置 QMAP 接口与路由。

## `androidDevices.qtee`

| 选项 | 含义 |
| --- | --- |
| `supplicant.enable`、`supplicant.package`、`supplicant.debug` | minkipc `qtee_supplicant`，包含文件系统、时间、RPMB 和 TA 自动加载监听器。由需要它的服务拉起。`debug` 记录每个监听请求及其解析后的路径。 |
| `persist.device`、`persist.mountPoint` | 挂载 ext4 persist 分区（默认 `/persist`；`nodev,nosuid,noexec,noatime`，不自动 fsck）。 |
| `persist.androidDataPath` | 另将 `<mountPoint>/data` 绑定到 Android 路径（例如 `/mnt/vendor/persist/data`），供请求该路径的 QTEE 固件使用。 |
| `persist.writablePaths` | supplicant 可写的 persist 子目录；其余部分对其只读。 |
| `modemOpener.enable`、`modemOpener.package` | `mink-modem-opener`，发布 QRTR 服务 5013（`IMinkModemOpener`），基带通过它打开 QTEE 服务。需要 supplicant。 |
| `modemOpener.clientUid` | 在 QTEE 客户端凭据中使用的 UID（Android 的 `ssgtzd` 为 1000）。 |
| `modemOpener.trace`、`modemOpener.transportTrace` | 记录基带与 QTEE 之间的每次调用，以及 MinkSocket 自身的传输跟踪。 |
| `qwesd.enable`、`qwesd.package` | 高通预编译、非自由的 QWES 守护进程，提供 QMI QTEE 许可服务；只能使用 QRTR 和 Unix 套接字。需显式允许 `qwesd` 包。 |

已启用的 QTEE 许可服务会在 MPSS 之前启动。MPSS 运行期间不要手动重启
`qtee-supplicant` 或 `mink-modem-opener`。

## 检查基带启动

```sh
systemctl start modem-mpss.service
cat /sys/class/remoteproc/remoteproc*/name /sys/class/remoteproc/remoteproc*/state
journalctl -b -u modem-mpss -u modem-rmtfs -u modem-tqftpserv \
  -u qtee-supplicant -u mink-modem-opener
qrtr-lookup
mmcli -L
```

使用 `startMethod = "rmtfs"` 时，改为启动 `modem-rmtfs.service`。
