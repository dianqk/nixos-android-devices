# Polaris 基带校准快照

[English](radio-snapshot.md) · [Polaris](README.zh.md) · [基带服务](../modem.zh.md)

`hardware.polaris.radio.snapshotDirectory` 必须指向本机基带校准数据的只读快照。
`modem-rmtfs.service` 用 `rmtfs -s -r -o` 提供该快照，并由同一个单元启动 MPSS。
未配置快照目录时基带服务完全不会安装，Wi-Fi 也就没有可用的固件服务
（原因见[为什么 Wi-Fi 依赖快照](#为什么-wi-fi-依赖快照)）。

## 必需的文件

MPSS 按绝对路径向 RMTFS 请求自己的 EFS 分区，`rmtfs -o` 用快照目录里同名文件的
basename 回应。因此要把 GPT 分区拷成这些**文件名**，它们不是分区标签：

| 分区标签 | 快照文件 | polaris 上的大小 |
| --- | --- | --- |
| `modemst1` | `modem_fs1` | 8 MiB |
| `modemst2` | `modem_fs2` | 8 MiB |
| `fsg` | `modem_fsg` | 8 MiB |
| `fsc` | `modem_fsc` | 256 KiB |

在手机上以 root 身份，从出厂分区生成快照：

```sh
d=/var/lib/polaris-radio-snapshot
mkdir -p "$d"
for pair in "modemst1 modem_fs1" "modemst2 modem_fs2" "fsg modem_fsg" "fsc modem_fsc"; do
  set -- $pair
  dd if="/dev/disk/by-partlabel/$1" of="$d/$2" bs=1M status=none
done
cd "$d" && sha256sum modem_fs1 modem_fs2 modem_fsg modem_fsc > SHA256SUMS
```

`modem-rmtfs.service` 只要求 `SHA256SUMS` 存在，不会校验文件内容。请把校验值和
文件在手机之外另存一份，重装后可还原同一份快照。

在已安装系统配置里指定目录：

```nix
hardware.polaris.radio = {
  identityFile = "/var/lib/polaris-radio-identity/wifi-address";
  snapshotDirectory = "/var/lib/polaris-radio-snapshot";
};
```

RMTFS 以只读方式打开快照（`rmtfs -r`）；MPSS 的校准写入只留在内存中并被丢弃，
文件与分区内容保持逐字节一致。

## 为什么 Wi-Fi 依赖快照

`ath10k_snoc` 并不只和 WCN3990 通信。它的 QMI 句柄使用 `AF_QIPCRTR`，所查找的
WLFW 服务由 MPSS 发布，而不是 Wi-Fi 芯片：

```
ath10k_snoc_probe() → ath10k_qmi_init() → qmi_add_lookup(WLFW)
                     … 等待 QRTR 服务，而它只在 MPSS 运行后存在
                     → ath10k_qmi_event_server_arrive() → wlan0
```

`rmtfs -s` 只在自己的 QRTR 服务注册后才启动 MPSS，而 MPSS 没有上表中的 EFS 文件
就无法完成初始化。因此缺文件表现为 **Wi-Fi 故障而不是基带故障**：
`18800000.wifi` 的 probe 全部成功、`wlan0` 始终不出现、ath10k 一行日志都不打印
——即使加了 `ath10k_core.debug_mask=0xffff` 也一样。

## 排障

`rmtfs` 会记录每个打不开的路径，同时给出它查找的文件和 MPSS 请求的路径：

```
[storage] failed to open '.../modem_fs1' (requested '/boot/modem_fs1'): No such file or directory
[storage] failed to open '.../modem_fsg' (requested '/boot/modem_fsg'): No such file or directory
```

这行日志是唯一的直接线索：polaris 上 `rmtfsVerbose` 默认为 `false`，成功的请求不会记录。
文件缺失或名字不对时，MPSS 仍会启动，然后约 40 秒后崩溃并自行重启：

```
qcom-q6v5-mss 4080000.remoteproc: fatal error without message
remoteproc remoteproc0: crash detected in 4080000.remoteproc: type fatal error
```

按顺序检查这条链：

```sh
cat /sys/class/remoteproc/remoteproc0/state   # running，且能持续保持
qrtr-lookup | grep -i wlfw                    # WLFW 服务已发布
ls /sys/class/net/wlan0                       # 接口已创建
```

`wlan0` 在 `modem-rmtfs` 启动约十秒后出现。`polaris-wifi-address` 写入
systemd-networkd 的 `.link` 规则，接口创建时由 udev 套用出厂地址；若基带始终起不来，
该规则没有机会生效，接口会使用随机地址。
