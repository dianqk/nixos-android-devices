# Sheng 首次安装

[English](first-install.md)

使用 Rust daemon recovery，在 B 槽执行操作，保留 A、super、校准和独立 recovery。
Recovery initrd 不包含 Python；标准 NixOS 安装与更新可在 chroot 中使用目标系统的 Python。

从原厂 userdata 布局开始，以下命令先检查，再明确执行**破坏性**准备：Android 与 Linux
各约占原 userdata 的 50%，Linux 一侧包含独立 FAT ESP（默认 1 GiB）和 ext4 根。
Android userdata 数据不保留，之后需要单独恢复出厂初始化。已分区设备不会重新分区。

```sh
ssh RECOVERY_HOST 'recovery prepare-install --check'
ssh RECOVERY_HOST 'recovery prepare-install --confirm-erase-userdata'
```

完成后按[首次安装](../initial-install.zh.md)导入系统、安装 EFI，最后写入匹配的 U-Boot。
已有系统使用 `recovery rebuild boot` 更新，或从 host 使用 `mobile-device recovery deploy`。
旧有的 root/ESP 顺序和对齐间隙仍受支持；普通更新不重新分区。

仅需清空已有 Linux 根时，可用 `recovery format-root --check` 检查，
再通过 `--confirm` 格式化；此操作不清空 Android 或 ESP。新的 daemon 操作尚待各设备实机验证。
