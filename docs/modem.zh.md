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
| Aurora | `hardware.aurora.modem.enable = true;` | 实验性。支持注册网络、移动数据和短信；需要 Android 14 底包和许可服务。见 [Aurora 蜂窝基带](aurora/connectivity.zh.md#cellular-modem-experimental)。 |
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
| `timeSyncTimeout` | `120` | 启动 MPSS 前等待 NTP 同步的秒数；`0` 关闭等待。 |
| `simProvisioning` | `true` | 若基带未自行激活，为第一张 USIM 激活主 GW provisioning 会话。 |
| `modemManager` | `true` | 启用 ModemManager（附带 netlink 修复）并随 MPSS 启动。 |
| `firmware` | `[ ]` | 基带固件包，只安装在根文件系统中。 |
| `rmtfsPackage`、`tqftpservPackage` | 打包的默认值 | 替换 rmtfs 或 tqftpserv。 |
| `rmtfsVerbose`、`rmtfsMemoryDevice` | `true`、`/dev/qcom_rmtfs_mem1` | rmtfs 日志与共享内存设备。 |

相关单元为 `modem-tqftpserv`、`modem-rmtfs`、`modem-mpss`（`remoteproc-unit`
方式）和 `modem-sim-provision`（启用 `simProvisioning` 时）。rmtfs 和 tqftpserv
不会自行重启，`nixos-rebuild switch` 也不会重启基带服务；需重启系统使改动生效。
崩溃的 MPSS 保持原状，不会被停止。

设置 `allowNvWrites = true` 前先备份 NV 分区，切勿恢复其他手机的 NV 数据。

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
