# Polaris EFI 控制台实现

[English](boot-menu-reference.md)

已安装链路为 Android firmware → U-Boot → systemd-boot → Linux EFI。Android boot
header 包装 U-Boot；只有 RAM recovery 通过 Android firmware 直接启动 Linux。
U-Boot 位于物理 `boot`。物理 `system` 为 FAT32，挂载到 `/boot`，包含
`EFI/BOOT/BOOTAA64.EFI`、标准 NixOS `EFI/nixos/` payload 和
`loader/entries/` 代际。Userdata 是普通 ext4。

## 显示与定制

systemd-boot 261.2 在 Linux 前通过 UEFI Simple Text Output/Input 运行；它不是
Linux tty/getty。该固件上 U-Boot 将文本渲染到继承的 1080×2160 framebuffer，并
同时通过串口/USB ACM 输出控制台。构建的 U-Boot 配置选择 `VIDEO_FONT_8X16` 和
本地 `VIDEO_FONT_SCALE=3`，得到 24×48 字形和 45×45 字符网格。TrueType 和运行时
字体选择被禁用。Linux `console.font` 不能改变该菜单。

[loader.conf](https://github.com/systemd/systemd/blob/v261.2/man/loader.conf.xml)
提供 timeout、默认条目、控制台模式和条目可见性；它不提供图形主题引擎、自定义
控件或任意字体文件。[菜单实现](https://github.com/systemd/systemd/blob/v261.2/src/boot/boot.c)
使用固件文本渲染。自定义图形菜单需要修改该实现或使用其他 EFI 前端，并完成相应
代际和输入集成。

`console-mode` 选择固件文本模式，不是可移植字号控制。在此 U-Boot 版本中，
`efi_cout_set_mode()` 改变逻辑文本模式并清屏，不缩放字形。`query_vidconsole()`
只在 `stdout` 以 `vidconsole` 开头时使用 video-console 尺寸；环境使用
`vidconsole,serial,usbacm`（USB ACM 在 preboot 加入）。不要假设
`console-mode max` 会让手机文字变大；显式位图缩放在 EFI 查询显示前设置字形大小。
原生面板分辨率和 Linux 字体不变。参见
[U-Boot EFI console 源码](https://github.com/u-boot/u-boot/blob/5508406582f6f7120dce0c4b3059819a41788db2/lib/efi_loader/efi_console.c)。

## 实体按键

编译的固件启用 `BUTTON_KEYBOARD`、`BUTTON_GPIO`、`BUTTON_QCOM_PMIC` 和
`BUTTON_REMAP_PHONE_KEYS`。`button-kbd` 与串口、USB ACM 一起包含在 `stdin`。
上游映射：

| 手机按键 | EFI 菜单输入 |
| --- | --- |
| 音量加 | Up |
| 音量减 | Down |
| 电源短按 | Enter |

参见[上游映射](https://github.com/u-boot/u-boot/blob/5508406582f6f7120dce0c4b3059819a41788db2/drivers/button/button-uclass.c)
和 [systemd-boot 菜单键](https://systemd.io/BOOT/)。Polaris DT 将音量加描述为
PM8998 GPIO 6，音量减为 PM8998 resin，电源为 PM8998 power-key 输入。U-Boot 启动
时按住音量减会请求 **U-Boot 自己的** recovery/utility 菜单；选择 “Boot NixOS”
进入 systemd-boot。systemd-boot 中的短按导航选择代际。

自动 EFI 启动和代际回滚已验证。实体按键导航和面板字体可读性尚未测试；见
[使用指南](boot-menu.zh.md)。长按电源键仍受 PMIC 硬件行为约束。
