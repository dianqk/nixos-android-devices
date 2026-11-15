# U-Boot 安装


> **Dodge 例外：** 独立可刷写 U-Boot 角色已退役，请使用
> [同槽位原生/KernelSU 产品](boot-choice.md)，不要将新独立加载器刷入
> `boot_b`。`devices.dodge.boot-firmware` 仅提供 raw/ELF/config 嵌入输入，不是
> OEM 启动镜像。保留既有独立 B/RAM recovery 和回退资源。原生事务及 EFI
> 防护已实现并通过主机测试，但真机、运行时和断电验证仍单独进行。
> 其他设备的独立固件角色和安装步骤不变。

[English](u-boot-install.md)

已安装的移动系统使用 U-Boot → systemd-boot → Linux。`devices.<device>.u-boot`
在支持的设备上提供独立 U-Boot 固件（Dodge 除外）。已安装系统的 `boot-files` 提供 FAT 上的 EFI 文件。`recovery`
提供 RAM 救援镜像，格式和入口依设备而定。
[T880](t880/install.zh.md) 通过已安装的 U-Boot 接收主机提供的 raw FIT；
[Dodge](recovery.md#dodge-host-supplied-fit) 保留 raw FIT 角色；独立 OEM 救援还需另行保留已启动验证的 RAM 引导镜像。

| 型号 | FAT `/boot` | ext4 `/` | 固件分区 |
| --- | --- | --- | --- |
| Asphalt | 独立 1 GiB `linux-boot` ESP | 独立 `linux` | 仅 `boot_b` |
| Polaris | 物理 `system` | `userdata` | `boot`，无 A/B |
| Sheng | 独立 1 GiB `linux-boot` ESP | 独立 `linux` | 仅 `boot_b` |
| Aurora | 独立 1 GiB `linux-boot` ESP | 独立 `linux` | 仅 `boot_b` |
| Clover | 物理 `system` | `userdata` | `boot`，无 A/B |
| Marble | 独立 `linux-boot` ESP | 独立 `linux` | 仅 `boot_b` |
| Dodge | 独立 `linux-boot` ESP | 独立 `linux` | 同槽位原生嵌入；保留独立 B |
| T880 | 独立 `linux-boot` ESP | 独立 `linux` | 仅 `boot_a` |

Asphalt、Sheng、Aurora、Marble、Dodge 的两个 Linux 分区均来自原 userdata 分配范围，位于外层 GPT；
保留 Android A 和 super。T880 保留 Android B 和 super。不要将 rootfs 镜像写入 system 或将 EFI 文件目录当成分区镜像。

1. 按[配置指南](configuration.zh.md)设置本机身份、登录凭据和存储约定。
2. 对支持独立固件的设备（Dodge 除外），如果尚无兼容固件，单独构建或获取该型号的 U-Boot，并按设备指南刷写。
3. 通过设备支持的方式启动 RAM recovery。测量 GPT 并核对分区身份，显式准备 FAT
   和空 ext4 根，再用[共享首次安装器](initial-install.zh.md)安装系统和 EFI 代际。
4. 验证正常启动、RAM recovery、SSH、代际更新及回退。普通系统更新只更新 EFI 代际，
   固件可在需要时单独更新。

## 单独构建和刷写 U-Boot

在本仓库中将 `DEVICE` 换成实际型号：

```sh
nix build .#devices.DEVICE.u-boot --out-link DEVICE-u-boot.img
sha256sum DEVICE-u-boot.img
```

此输出是可独立分发、刷写的设备固件镜像。消费 flake 的 `boot` 输出提供同一角色。
已有固件的设备可继续使用兼容版本。设备支持原厂 fastboot 刷写时，按设备指南操作。
如果已经在兼容的 RAM recovery 中，也可用其固件更新操作。把 `BOOT_PARTLABEL`
替换为上表中的固件分区名：

```sh
mobile-device recovery --target RECOVERY_HOST install-image DEVICE-u-boot.img \
  --partition /dev/disk/by-partlabel/BOOT_PARTLABEL
mobile-device recovery --target RECOVERY_HOST install-image DEVICE-u-boot.img \
  --partition /dev/disk/by-partlabel/BOOT_PARTLABEL --execute
```

recovery 根据设备和槽位规则确定实际目标分区，核对镜像身份和容量，并回读校验写入结果。
完成设备指南中的其余启动准备后再启动系统。

已有 EFI 系统可在 recovery 使用 `mount-target --rw`、`rebuild boot`、`unmount-target`；
详见[恢复指南](recovery.zh.md)。硬件支持与限制分别见
[Asphalt](asphalt/hardware.zh.md)、[Polaris](polaris/hardware.zh.md)、
[Sheng](sheng/hardware.zh.md)、[Aurora](aurora/hardware.zh.md) 和 [Clover](clover/hardware.zh.md)。
