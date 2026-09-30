# U-Boot 安装

[English](u-boot-install.md)

四个型号的普通系统统一使用 U-Boot → systemd-boot → Linux。`devices.<device>.boot`
与 `devices.<device>.u-boot` 都是 U-Boot 固件；`boot-files` 是 FAT 上的 EFI 文件，
`recovery` 是独立 Android 格式 RAM 救援镜像。配置求值不会修改设备存储或刷写固件。

| 型号 | FAT `/boot` | ext4 `/` | 固件分区 |
| --- | --- | --- | --- |
| Asphalt | 独立 1 GiB `linux-boot` ESP | 独立 `linux` | 仅 `boot_b` |
| Polaris | 物理 `system` | `userdata` | `boot`，无 A/B |
| Sheng | 独立 1 GiB `linux-boot` ESP | 独立 `linux` | 仅 `boot_b` |
| Clover | 物理 `system` | `userdata` | `boot`，无 A/B |

Asphalt/Sheng 的两个 Linux 分区均来自原 userdata 分配范围，位于外层 GPT；
保留 Android A 和 super。不要将 rootfs 镜像写入 system 或将 EFI 文件目录当成分区镜像。

1. 按[配置指南](configuration.zh.md)设置本机身份、登录凭据与存储约定，构建同一锁定版本的
   system、bootstrap-info、boot-files、u-boot 和 recovery。先验证独立 RAM recovery 可进入。
2. 在 recovery 测量并核对实际 GPT、容量、分区身份和文件系统。
3. 按设备存储指南准备上表中的 FAT 与空 ext4 根。分区和格式化仍需显式、单独执行。
4. 四台设备均使用[共享首次安装器](initial-install.zh.md)。它导入并校验完整闭包和注册信息，
   安装 EFI 代际，最后写入匹配的 U-Boot。先检查再加 `--execute`；成功后无需另行刷写固件。
5. 验证启动、独立恢复、SSH、代际更新/回退。普通更新使用 `nixos-rebuild boot`，更新 FAT
   文件而不重写 Android boot 分区；固件更新是独立操作。

已有 EFI 系统可在 recovery 使用 `mount-target --rw`、`rebuild boot`、`unmount-target`；
详见[恢复指南](recovery.md)。硬件支持与限制分别见
[Asphalt](asphalt/hardware.zh.md)、[Polaris](polaris/hardware.zh.md)、
[Sheng](sheng/hardware.zh.md) 和 [Clover](clover/hardware.zh.md)。
