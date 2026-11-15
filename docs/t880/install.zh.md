# T880 首次安装

[English](install.md) · [T880 指南](README.zh.md)

本指南为酷比魔方 iPlay 80 mini Ultra（T880）在 A 槽安装 NixOS 做准备，Android 保留在
B 槽。此流程为实验性质。分区会**清除 Android 的 userdata**，请自行备份所需数据。

前提：bootloader 已解锁，B 槽 Android 可用，主机有 `fastboot`、`adb` 和本仓库的
`mobile-device` 工具（`nix run .#mobile-device -- …`）。构建镜像：

```sh
nix build .#devices.t880.u-boot --out-link t880-u-boot.img
nix build .#devices.t880.recovery.payload --out-link t880-recovery.itb
```

U-Boot 镜像填满 64 MiB 的 `boot_a` 分区并带有 AVB hash footer，原厂 LK 需要它。
recovery FIT 不超过 128 MiB。

## 1. 在 A 槽写入 U-Boot

在 Android 中执行 `adb reboot bootloader`。进入 LK fastboot（product
`p5n1_kb_t880_8883_b0`）后：

```sh
fastboot getvar product
fastboot flash boot_a t880-u-boot.img
fastboot set_active a
fastboot reboot
```

U-Boot 以带平板序列号的 USB fastboot 设备出现。若 90 秒内没有 USB 主机连接，
U-Boot 让看门狗复位平板；数次后 LK 回到 B 槽的 Android。

## 2. 从内存启动 recovery

将 `SERIAL` 设为已核对的 U-Boot USB fastboot 序列号，原样传输 FIT：

```sh
fastboot -s "$SERIAL" stage t880-recovery.itb
fastboot -s "$SERIAL" oem 'run:bootm ${fastboot_addr_r}'
```

主机 `fastboot boot` 可能给原始 FIT 添加 Android 镜像头，此处应使用 `stage`。
OEM 命令的 `run` 后必须有冒号。U-Boot 跳转时 USB 会断开，最后一条命令可能报告
状态读取连接中断。

recovery 在屏幕上显示菜单，并提供 USB 网络：`ssh root@172.16.47.1`（下文
`mobile-device recovery --target` 使用同一地址）。

## 3. 拆分 userdata

先检查。不指定大小时列出可选的 Android userdata 大小（32/64/128/256/512 GiB，即让
`linux-boot` 与 `linux` 仍有至少 64 GiB 的大小，见 [recovery](../recovery.zh.md)）；
指定大小时打印计划分区表。两者都不做任何修改：

```sh
mobile-device recovery --target root@172.16.47.1 prepare-install
mobile-device recovery --target root@172.16.47.1 prepare-install --android-userdata 64G
```

计划只涉及 userdata 范围：Android `userdata` 保留所选大小，其后依次为
`linux-boot`（FAT，1 GiB）和 `linux`
（ext4，其余空间）。GPT 由 82 项扩展为 84 项，其余条目不变。确认分区表无误后：

```sh
mobile-device recovery --target root@172.16.47.1 prepare-install \
  --android-userdata 64G --gpt-backup ./t880-gpt-original --execute
```

此命令先把原始 GPT（两份副本）下载到 `./t880-gpt-original`，再进行分区。recovery
先写 GPT 备份副本、再写主副本，每一步都校验；任何一步失败都会自动恢复原始 GPT。新的
Android userdata 不格式化（清零前 8 MiB），`metadata` 分区不受影响。

## 4. 在 B 槽重新初始化 Android

Android 用自带的 recovery 格式化缩小后的 userdata：

1. 在 NixOS recovery 菜单中选择 “Enter fastboot”（或执行 `mobile-device recovery
   --target root@172.16.47.1 reboot bootloader --execute`）。
2. 执行 `fastboot set_active b`，再执行 `fastboot reboot recovery`。
3. 选择 “Wipe data/factory reset”，然后重启进入 Android。

之后返回 NixOS：`adb reboot bootloader`，再执行 `fastboot set_active a` 与
`fastboot reboot`。

## 5. 安装 NixOS

如有需要再次启动 recovery（从 Android：`adb reboot bootloader`、`fastboot
set_active a`、`fastboot reboot`；U-Boot 在 `linux-boot` 为空时等待 USB fastboot，
再执行第 2 步的原始 FIT 暂存命令）。构建系统及其闭包信息，先检查再安装：

```sh
nix build .#devices.t880.system --out-link t880-system
nix build .#devices.t880.bootstrap-info --out-link t880-bootstrap-info
mobile-device recovery --target root@172.16.47.1 install-initial \
  ./t880-system --bootstrap-info ./t880-bootstrap-info
mobile-device recovery --target root@172.16.47.1 install-initial \
  ./t880-system --bootstrap-info ./t880-bootstrap-info --execute
mobile-device recovery --target root@172.16.47.1 reboot system --execute
```

该过程把闭包写入空的 ext4 `linux`，把 systemd-boot 与当前代安装到 `linux-boot`，
并校验 EFI 代际。第 1 步刷写的 U-Boot 从
`linux-boot` 加载 systemd-boot，并在 misc 中把 A 槽标记为成功，LK 不再递减其重试
次数。后续更新使用常规的 NixOS 代；旧代可在 systemd-boot 菜单中选择。

进入 recovery：Linux 中 `systemctl reboot --reboot-argument=recovery`，U-Boot
fastboot 中 `fastboot reboot recovery`，或 U-Boot 菜单（按住音量下）选择 Fastboot USB；
进入 U-Boot fastboot 后，从主机执行第 2 步的原始 FIT 暂存命令。

## 撤销分区

启动 recovery（第 1–2 步）后写回保存的 GPT：

```sh
mobile-device recovery --target root@172.16.47.1 restore-gpt \
  --gpt-backup ./t880-gpt-original --execute
```

然后在 B 槽原厂 recovery 中清除数据（第 4 步）。

## 出现问题时

- 重启之前，当前 recovery 会话可自行恢复保存的 GPT。
- LK fastboot（在 U-Boot 中执行 `fastboot reboot-bootloader`，在 Linux 中执行
  `reboot bootloader`，在 Android 中执行 `adb reboot bootloader`）始终可以重新刷写
  `boot_a` 或选择 B 槽。
- preloader 与 LK 读取主 GPT，失败时回退到备份副本；recovery 写入时每一步都保留一份
  有效副本。
