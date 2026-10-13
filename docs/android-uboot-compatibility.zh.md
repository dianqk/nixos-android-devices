# Asphalt / Sheng / Aurora 的 Android 与 U-Boot 兼容范围

[English](android-uboot-compatibility.md)

当前安装方式保留 Android A，在 B 安装 U-Boot，并保留独立 NixOS recovery。
本仓库不提供 Android/U-Boot 复合启动镜像，也不支持在这些设备上由 U-Boot
直接启动 Android。安装请按 [Asphalt](asphalt/first-install.zh.md)、[Sheng](sheng/first-install.zh.md) 或
[Aurora](aurora/README.zh.md) 指南操作。

## 已安装系统的启动路径

原厂启动固件 → `boot_b` 中的 U-Boot → `linux-boot` FAT ESP → systemd-boot →
所选 NixOS 代际的内核/initrd → ext4 `linux` 根分区。

ESP 与根分区是从原 userdata 空间划出的外层 GPT 独立分区，没有 A/B 后缀。
U-Boot 加载 EFI，Linux 挂载根分区。原厂固件在进入 U-Boot 前选择 Android 槽位。
准备 Linux 布局时保留 Android A 和 super。

独立 recovery 自带内核、DTB 和 initrd，不依赖已安装系统的内核或 ESP。
更新 U-Boot 或 NixOS 时应保留该恢复入口。

## Android 启动兼容性

U-Boot 上游支持 [Android 镜像](https://docs.u-boot-project.org/en/v2026.10/android/boot-image.html)，
不代表具体设备已适配。Android 启动仍需配套的 DT/DTBO、ramdisk、bootconfig
和 vendor 模块，包括 `vendor_boot` 及适用时的 `init_boot`，见
[Android 启动布局](https://source.android.com/docs/core/architecture/partitions/generic-boot)。
从源码编译 Android 内核不会自动补齐这些输入，也不代表已实现 Android/U-Boot
集成。Android 和 NixOS 可以使用各自的内核。

Android A 可启动不能证明 Android B 可用。仅修改 `slot_suffix` 无法补齐每槽所需的
镜像、逻辑分区、AVB 元数据和固件。完整 Android A/B 还需要正确处理启动成功确认、
重试、失败回退和 OTA，见 [AOSP A/B 要求](https://source.android.com/docs/core/ota/ab/ab_implement)。
NixOS 的代际选择和回退独立于 Android A/B。
