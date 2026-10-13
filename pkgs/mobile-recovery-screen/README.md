# Recovery screen

[中文](README.zh.md) · [Y700 2023](../../docs/asphalt/README.md) ·
[Polaris](../../docs/polaris/README.md) · [Sheng](../../docs/sheng/README.md) ·
[Clover](../../docs/clover/README.md)

The device RAM recovery screens share these actions: Show
recovery log, Boot NixOS, Restart recovery, Enter fastboot, and Power off.
Device actions require explicit confirmation. First installation uses the
SSH/ACM commands in each device guide.

The interface uses Linux VT/fbcon on tty2: a black background, white text,
plain menus and a character progress bar. It scales the kernel bitmap font to
fit at least 40 columns and 32 rows, writes only changed character spans, and
sends kernel messages to tty1. No TTF files, font rasterizer, userspace pixel
buffer or display server is required. The kernel must provide VT, framebuffer
console and DRM fbdev emulation. Existing panel refresh and backlight handling
remain device-specific. SSH/ACM remains independent if the screen fails.

Use Volume +/- to move and Power to select. Leaving recovery requires a second
confirmation, with Cancel selected by default. During a transfer the screen
shows progress and locks action keys. Logs wrap to the available columns and
show the most recent lines. Non-ASCII and control characters are shown as `?`
to keep cell widths predictable and prevent terminal escape injection.

For a local text preview, run `mobile-recovery-screen --preview OUTPUT.txt`.
`MOBILE_RECOVERY_PREVIEW_SIZE=COLUMNSxROWS` selects the character grid (default
50x40, supported range 40..240 by 32..160). Set
`MOBILE_RECOVERY_PREVIEW_STATE=confirm|error|log|update` to preview another page,
and `MOBILE_RECOVERY_PREVIEW_LOG=PATH` to supply a log file. Preview mode does
not access devices or run recovery actions.

Every device uses the [Rust recovery daemon and shell](daemon.md) for all recovery
operations. Its UI subscribes to daemon task state, and its initrd contains no
Python runtime or storage/install shell backend.
