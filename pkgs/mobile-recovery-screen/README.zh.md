# Recovery 屏幕程序

[English](README.md) · [Y700 2023](../../docs/asphalt/README.zh.md) ·
[Polaris](../../docs/polaris/README.zh.md) · [Sheng](../../docs/sheng/README.zh.md) ·
[Clover](../../docs/clover/README.zh.md)

各设备的 RAM recovery 共用以下菜单项：Show recovery log、
Boot NixOS、Restart recovery、Enter fastboot 和 Power off。设备操作需要
明确确认。首次安装使用各设备指南中的 SSH/ACM 命令。

界面通过 Linux VT/fbcon 在 tty2 显示：黑底白字、简单菜单和字符进度条。
程序放大内核位图字体，保证至少 40 列、32 行，只写入变化的字符区间，
内核日志重定向到 tty1。无需 TTF 文件、字体渲染库、用户态像素缓冲或显示服务器。
内核需要启用 VT、framebuffer console 和 DRM fbdev emulation。
各设备原有的面板刷新、背光处理保持独立；界面失败不影响 SSH/ACM。

音量键移动，电源键选择。离开 recovery 需要再次确认，默认选中取消。
传输期间显示进度并锁定操作按键。日志按列换行，显示最近内容；非 ASCII
字符及控制字符显示为 `?`，保证字符宽度一致并防止终端转义注入。

本地文字预览运行 `mobile-recovery-screen --preview OUTPUT.txt`。
`MOBILE_RECOVERY_PREVIEW_SIZE=COLUMNSxROWS` 指定字符网格（默认 50x40，
范围为 40..240 列、32..160 行）。使用
`MOBILE_RECOVERY_PREVIEW_STATE=confirm|error|log|update` 预览其他页面，
`MOBILE_RECOVERY_PREVIEW_LOG=PATH` 指定日志文件。预览不访问设备或执行恢复操作。

所有设备均使用 [Rust recovery daemon 与交互 shell](daemon.md)：UI 与 CLI
订阅同一任务状态，设备端操作由 daemon 管理。initrd 不包含 Python 运行时及
Shell 分区/安装后端。
