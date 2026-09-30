# Y700 2023：U-Boot / EFI

[设备指南](README.zh.md) · [安装步骤](first-install.zh.md)

`devices.asphalt.u-boot` 与 `devices.asphalt.boot` 均提供 U-Boot 固件。
设备模块默认使用 U-Boot → systemd-boot → NixOS；启动、Wi-Fi 更新和代际回退已验证。
菜单显示已确认，实体按键选择仍待验证。

## 构建与安装

```sh
nix build .#devices.asphalt.u-boot --builders '' \
  --out-link tmp/systemd-artifacts/devices.asphalt.u-boot
```

固件写入 `boot_b`，按 GPT 名称查找 `linux-boot` 并加载
`EFI/BOOT/BOOTAA64.EFI`。使用独立 1 GiB FAT32 ESP 和 ext4 `linux` 根分区，
保留 Android A 和 super。systemd-boot 默认保留 10 代，更新前检查 FAT 可用空间。

保留 ABL 画面的固件需要搭配包含 Lucid OLE PLL 保留补丁的内核；本仓库默认内核
已包含该补丁。版本不匹配可能造成黑屏或触摸初始化失败。保持独立 RAM recovery 可用。

按[存储准备](manual-storage.zh.md)核对布局并准备分区，然后使用
[首次安装器](../initial-install.zh.md)安装系统、EFI 文件及匹配的 U-Boot。
`recovery plan-uefi` 只生成分区计划，不会修改存储；执行计划可能清除 Android userdata。
普通系统更新使用 `nixos-rebuild boot`，不重写固件。

## 开发参考

固件使用官方 U-Boot v2026.10-rc5、Android v2 header、未压缩 ARM64 payload
和独立 DTB，容量上限为 `boot_b` 的 96 MiB。USB ACM 在 UFS 扫描前启用。
固件使用 USB2 peripheral；Linux 提供 USB3/DP 支持。

补丁来源、构建检查和硬件限制见 [SM8475 包说明](../../pkgs/u-boot/sm8475/README.md)。
