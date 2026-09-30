# mobile-device

[English](README.md)

`mobile-device` 是操作 Android fastboot、NixOS RAM recovery 和已安装
NixOS 移动系统的主机端 Python CLI。使用 `nix profile install .#mobile-device`
安装，或运行 `nix run .#mobile-device -- ...`。软件包提供 `fastboot`、`nix` 和 `ssh`。
Recovery 命令使用 SSH，通过 TOML `target` 或 `recovery --target HOST` 选择设备，
参见[连接设置](../../docs/recovery.md)。

提供已经构建好的镜像或系统。用 `--serial` 选择 fastboot 设备，`recovery --target HOST` 选择 SSH 设备。
安装、部署和重启命令默认只检查；添加 `--execute` 才会执行。显式 `mount`、
`unmount`、文件传输和 `rebuild boot` 立即执行；rebuild 要求目标已显式挂载为可写。

## 可选的设备默认参数

在工具源码之外保存本地 TOML 配置。命令行参数优先；不需要的值可以省略。

```toml
serial = "YOUR_FASTBOOT_SERIAL"
result_file = "/run/YOUR_INITIAL_INSTALL_RESULT"
boot_image = "YOUR_BOOT_IMAGE_NAME"
update_program = "YOUR_SYSTEM_UPDATER_NAME"
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
Asphalt/Sheng 要求当前 B 槽并明确使用 `boot_b`/`recovery_b`。Recovery 镜像只能
刷入 recovery 分区。DTBO、rootfs、缺少受支持 DTB 的原厂/vendor 镜像及未知 product
不在此命令的支持范围内。机型识别不依赖文件名或个人序列号白名单。
检查与执行都会重新校验，只有 `--execute` 才发送最终 boot/flash 命令。
打印的大小、SHA-256 和结构检查不构成发布者身份认证。


## RAM recovery

所有设备均提供 `/bin/recovery`，主机工具自动调用，无需命令选择参数或 TOML
命令配置。配置 SSH `target`。四台设备均提供[共享 `install-initial`](../../docs/initial-install.zh.md)，
默认结果文件为 `/run/mobile-initial-install.result`。空根分区和 FAT 必须单独准备，
安装命令不会重分区或格式化。所有 EFI 离线更新使用
`/run/mobile-offline-deploy.result`。格式化前请遵循对应的首次安装指南：
[Asphalt](../../docs/asphalt/first-install.zh.md)、
[Polaris](../../docs/polaris/first-install.zh.md)、
[Sheng](../../docs/sheng/first-install.zh.md)、
[Clover](../../docs/clover/first-install.zh.md)。
Polaris 使用 `format-userdata`，其他三台设备使用 `format-root`。

Polaris 还需要将物理 `system` 准备为 FAT32 `/boot`。准备 ext4 userdata 后，
先运行 `recovery prepare-boot` 检查，再执行 `recovery prepare-boot --execute`。
若已有系统，完整 Nix store 必须位于 userdata，才能将 system 用作 FAT；GPT 位置和大小不变。

```sh
mobile-device --config device.toml recovery status
mobile-device --config device.toml recovery reboot system
mobile-device --config device.toml recovery reboot system --execute

# 仅首次安装：明确格式化现有 userdata 为 ext4。
mobile-device --config device.toml recovery format-userdata
mobile-device --config device.toml recovery format-userdata --execute

# Y700 2023、Sheng 和 Clover LTE：请先核对对应设备指南。
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

# 可选：通过 Nix daemon socket 复制闭包，并在 recovery 屏幕上显示进度。
mobile-device --config device.toml recovery copy /nix/store/...-nixos-system-device-version
```

已安装系统需要运行设备专用的 recovery 请求脚本时：

```sh
mobile-device recovery --target HOST enter \
  --script ./request-recovery.sh \
  --support-script ./storage-roles.sh --support-env STORAGE_ROLES
mobile-device recovery --target HOST enter \
  --script ./request-recovery.sh \
  --support-script ./storage-roles.sh --support-env STORAGE_ROLES --execute
```

脚本需接受 `--check` 和 `--execute`。调用者指定支持文件的环境变量名；
Polaris 脚本使用 `POLARIS_STORAGE_ROLES`。

安装仓库提供的 recovery 镜像时，使用
`recovery install-image IMAGE --installer SCRIPT --partition DEVICE_PATH`，
也可传入 `--support-script` 和 `--support-env`。安装脚本需要接受
`MODE IMAGE IMAGE_SHA256 OLD_PARTITION_SHA256`，并支持 `--check` 和
`--execute` 模式。

## 更新已安装的系统

提供已构建的 NixOS 系统及其内部的更新器、boot 镜像名称。更新期间如果连接
中断，在设备上查看更新器的 systemd 日志。

```sh
mobile-device --config device.toml system update /nix/store/...-nixos-system-device-version
mobile-device --config device.toml system update /nix/store/...-nixos-system-device-version --execute
mobile-device --config device.toml system --via ssh update /nix/store/...-nixos-system-device-version --execute
```

不使用配置文件时，在系统路径后添加 `--boot-image NAME --update-program NAME`；
SSH 更新还需在 `update` 前添加 `--target HOST`。默认 systemd 单元名为
`mobile-device-update`，可用 `--unit NAME` 修改。

同一连接也能运行设备专用的清理或诊断脚本：

```sh
mobile-device --config device.toml system script ./prune-system.sh
mobile-device --config device.toml system script ./prune-system.sh --execute
mobile-device --config device.toml system --via ssh script ./prune-system.sh --execute
```

`system script` 默认传入 `--check`；使用 `--execute` 时不传该选项。
完整参数见 `mobile-device --help` 和各子命令的 `--help`。

## Recovery 接口
