# 使用 Polaris 启动菜单

[设备指南](README.zh.md) · [首次安装](first-install.zh.md) · [English](boot-menu.md)

已安装的 EFI 系统将 NixOS 系统代保存在 FAT `/boot` 中。普通系统更新在此添加系统代，
不会重写物理 `boot` 中的 U-Boot。保留独立的 RAM recovery，以备启动失败。

该模块还启用了[电源和特殊重启操作](../boot-actions.zh.md)。Bootloader/recovery
条目需要更新后的 U-Boot，并会要求确认；其硬件行为尚未验证。

## 选择系统代

在 systemd-boot 菜单中选择所需的 NixOS 系统代并确认。固件将音量加/减映射为导航，
短按电源键映射为 Enter。物理按键操作已配置，但尚未在面板上验证；在可用时，USB
ACM/串口控制台可作为替代。U-Boot 阶段按住音量减会进入其自身的工具菜单；选择
“Boot NixOS” 进入 systemd-boot 系统代菜单。长按电源键由 PMIC 处理。

在运行中的 Linux 中查看已安装条目：

```sh
bootctl list
ls /boot/loader/entries
```

新系统代启动失败时，在下次启动时选择较旧的系统代。如果没有可用条目，启动 RAM
recovery 并使用[部署工具](../../pkgs/mobile-device/README.zh.md)。根文件系统和
EFI 文件必须对应同一个系统闭包。

## 修改超时和保留的系统代数量

在自己的 NixOS 配置中设置：

```nix
{
  boot.loader.timeout = 10;
  boot.loader.systemd-boot.configurationLimit = 10;
}
```

用 `nixos-rebuild boot` 构建并安装改动，然后重启。确保 FAT 分区有足够空间容纳
保留的内核/initrd/DTB 文件以及一次更新。默认保留 10 个系统代；空间不足时 EFI
安装器会拒绝安装。不要把生成的条目文件当作配置的来源去编辑。

菜单使用 U-Boot 的 24×48 位图字形。Linux `console.font`、合成器设置和 TrueType
字体不会影响它。当前固件没有运行时字号选项；修改字形大小需要重新构建并验证
U-Boot。渲染器、按键等细节见[实现参考](boot-menu-reference.md)。
