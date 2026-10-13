# mobile-device

[English](README.md)

`mobile-device` 是操作 Android fastboot、NixOS RAM recovery 和已安装
NixOS 移动系统的主机端 Python CLI。使用 `nix profile install .#mobile-device`
安装，或运行 `nix run .#mobile-device -- ...`。软件包提供 `fastboot`、`nix` 和 `ssh`。
Recovery 命令使用 SSH，通过 TOML `target` 或 `recovery --target HOST` 选择设备，
参见[连接设置](../../docs/recovery.zh.md)。

提供已经构建好的镜像或系统。用 `--serial` 选择 fastboot 设备，`recovery --target HOST` 选择 SSH 设备。
安装、部署和重启命令默认只检查；添加 `--execute` 才会执行。显式 `mount`、
`unmount`、文件传输和 `rebuild boot` 立即执行；rebuild 要求目标已显式挂载为可写。

## 可选的设备默认参数

在工具源码之外保存本地 TOML 配置。命令行参数优先；不需要的值可以省略。

```toml
serial = "YOUR_FASTBOOT_SERIAL"
target = "YOUR_SSH_HOST"
```

使用 `mobile-device --config device.toml ...`。只连接一台 fastboot
设备且不传序列号时，工具会自动选中它。`--config` 和 `--serial` 放在命令组之前。

## Fastboot

```sh
mobile-device --serial SERIAL fastboot boot ./recovery.img
mobile-device --serial SERIAL fastboot boot ./recovery.img --execute
mobile-device --serial SERIAL fastboot flash ./recovery.img --partition recovery
mobile-device --serial SERIAL fastboot flash ./recovery.img --partition recovery --execute
```

检查步骤会显示命令、镜像大小和 SHA-256。刷写时明确指定分区，并添加
`--execute`。

## Fastboot 校验范围

检查会解析 Android v0–v2 ARM64 镜像和实际 DTB 根节点 compatible，核对连接的
fastboot product，并在刷写前检查分区容量。Clover/Polaris 仅允许 `boot`/`recovery`；
Asphalt/Sheng/Aurora 要求当前 B 槽并明确使用 `boot_b`/`recovery_b`。Recovery 镜像只能
刷入 recovery 分区。任意 DTBO、rootfs、缺少受支持 DTB 的原厂/vendor 镜像及未知 product
不在此命令的支持范围内。机型识别不依赖文件名或个人序列号白名单。
检查与执行都会重新校验，只有 `--execute` 才发送最终 boot/flash 命令。
打印的大小、SHA-256 和结构检查不构成发布者身份认证。


部分 Asphalt 原厂 bootloader 的 product 仅为 SoC 名称 `taro`，单凭它无法识别机型。
此组合只接受准确的 fastboot `modelname: TB320FC`，并要求显式 `--serial` 与
fastboot `serialno` 一致；每次检查和执行均重新核对型号、序列号、B 槽、镜像和容量。
其他非空型号即使提供 recovery 身份记录也会拒绝。型号变量确实缺失或不受支持时，
可使用下方实际 NixOS RAM recovery 的身份观察记录；格式错误、
重复响应和传输故障不能降级为缺失。无效记录始终拒绝，不采用通用 taro 白名单。

已在独立 NixOS RAM recovery 中确认的平板，可通过 `--device-identity FILE`
并显式指定 `--serial` 提供可信身份 JSON 记录：

```json
{
  "version": 1,
  "serial": "YOUR_DEVICE_SERIAL",
  "product": "taro",
  "compatible": ["lenovo,asphalt", "qcom,sm8475"],
  "source": "nixos-ram-recovery",
  "collected_at": "2026-10-02T08:00:00+00:00",
  "boot_id": "12345678-1234-1234-1234-123456789abc"
}
```

确认平板与 RAM recovery 匹配后，记录实际完整的 `/proc/device-tree/compatible`
列表、`/proc/cmdline` 中的序列号、`/proc/sys/kernel/random/boot_id`、采集时间及
观察到的原厂 product，并替换全部示例值。该记录是可信观察，不是硬件密码学认证；
DT compatible 来自启动镜像。此补充仅适用于 product 为 `taro` 的 Asphalt。
检查与执行都会核对显式序列号、记录及当前 fastboot `serialno`，并保留镜像、B 槽、
分区和容量检查。无效记录始终拒绝。

```sh
mobile-device --serial YOUR_DEVICE_SERIAL fastboot flash ./u-boot.img \
  --partition boot_b --device-identity ./device-identity.json
# 核对检查结果后，以相同命令加 --execute 执行。
```


### Asphalt DTBO 擦除

Asphalt 的 U-Boot/mainline B 启动路径要求禁用原厂 `dtbo_b` overlay；安装
Android/LineageOS 可能恢复不兼容的 overlay。仅在恢复该 B 启动路径时显式执行
这个独立操作，保留 Android A 和 recovery，无需全零镜像。

必须明确 `--device asphalt`，实时 OEM product/modelname 为 `taro`/`TB320FC`，
显式 serial 匹配、当前 B 槽且 `dtbo_b` 容量准确为 24 MiB；recovery 身份记录
不能代替此操作的实时型号。

```sh
mobile-device --serial SERIAL fastboot erase --device asphalt --partition dtbo_b
# 核对检查结果后，添加 --execute 再执行。
```

擦除不接受镜像参数，不支持其他机型、槽位或分区。擦除失败会直接报告错误，
不会自动改为刷入替代镜像。

## RAM recovery

所有设备的 recovery 都运行 Rust recovery 守护进程，并提供 `/bin/recovery` 客户端；
主机工具自动调用它，不支持守护进程协议的 recovery 会被拒绝。配置 SSH `target`。
五台设备均提供[共享 `install-initial`](../../docs/initial-install.zh.md)。
空根分区和 FAT 必须单独准备，安装命令不会重分区或格式化。格式化前请遵循对应的
首次安装指南：
[Asphalt](../../docs/asphalt/first-install.zh.md)、
[Polaris](../../docs/polaris/first-install.zh.md)、
[Sheng](../../docs/sheng/first-install.zh.md)、
[Aurora](../../docs/aurora/README.zh.md)、
[Clover](../../docs/clover/first-install.zh.md)。

单槽设备 Polaris 和 Clover 将物理 `system` 用作 FAT32 `/boot`。执行 `format-root`
后，先运行 `recovery prepare-boot` 检查，再执行 `recovery prepare-boot --execute`。
GPT 位置和大小不变。

```sh
mobile-device --config device.toml recovery status
mobile-device --config device.toml recovery reboot system
mobile-device --config device.toml recovery reboot system --execute

# 仅首次安装：请先核对对应设备指南。
mobile-device --config device.toml recovery format-root
mobile-device --config device.toml recovery format-root --execute

# 与系统匹配的 bootstrap-info 输出包含 registration 和 store-paths。
mobile-device --config device.toml recovery install-initial /nix/store/...-nixos-system-polaris-version \
  --bootstrap-info ./result-polaris-bootstrap
mobile-device --config device.toml recovery install-initial /nix/store/...-nixos-system-polaris-version \
  --bootstrap-info ./result-polaris-bootstrap --execute

# 更新已安装的系统。
mobile-device --config device.toml recovery deploy /nix/store/...-nixos-system-device-version
mobile-device --config device.toml recovery deploy /nix/store/...-nixos-system-device-version --execute
```

从已安装系统进入 recovery 时，在 systemd-boot 菜单中选择 **Reboot to recovery**。

使用受检查的守护进程操作更新固件或 recovery 镜像：

```sh
mobile-device recovery --target HOST install-image ./recovery.img \
  --partition /dev/disk/by-partlabel/recovery_b
mobile-device recovery --target HOST install-image ./recovery.img \
  --partition /dev/disk/by-partlabel/recovery_b --execute
```

`--partition` 是 `boot` 或 `recovery` 的 `/dev/disk/by-partlabel/` 路径（A/B 设备为
`boot_b`/`recovery_b`）。守护进程在写入前校验
镜像身份、大小和目标分区，写入后回读核对。

## 已安装系统中的脚本

同一连接也能运行设备专用的清理或诊断脚本：

```sh
mobile-device --config device.toml system script ./prune-system.sh
mobile-device --config device.toml system script ./prune-system.sh --execute
mobile-device --config device.toml system --via ssh script ./prune-system.sh --execute
```

`system script` 默认传入 `--check`；使用 `--execute` 时不传该选项。
完整参数见 `mobile-device --help` 和各子命令的 `--help`。
