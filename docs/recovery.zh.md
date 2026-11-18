# 通过 USB 使用 RAM recovery

[English](recovery.md)

Recovery 完全运行于 systemd initrd 中。它提供物理 ACM root 控制台，以及带
OpenSSH 的 NCM 以太网接口。完整 recovery 启动时，可能会短暂挂载经过验证的
Linux 根分区，以加载或创建自己的 SSH 身份；在开放控制台和 recovery 工具之前
会将其卸载。Fastboot 仍是 Android bootloader 的传输方式。

<a id="configure-and-connect"></a>
## 配置与连接

```nix
androidDevices.recovery.enable = true;
```

使用导出的设备模块。发布的 `devices.<device>.recovery` 正是该模块仅设置
`recovery.enable` 的结果；不添加其他 recovery 选项的使用者配置会得到相同的 derivation。
USB serial 默认为 `RECOVERY_<DEVICE>`（例如 `RECOVERY_POLARIS`）。
`androidDevices.initrdUsb.address` 的默认值为：Asphalt `172.16.43.1/24`，
Polaris `.42.1`，Sheng `.45.1`，Clover `.44.1`，Aurora `.46.1`，T880 `.47.1`。同时连接多台设备时，请选择
不同的子网。Linux 主机需要 cdc_ncm，并在生成的以太网接口上运行 DHCP。
Recovery 提供 DHCP，但不下发默认路由/DNS。

ACM 和 NCM 是同一复合 USB gadget 的两个独立功能，而非互斥的后端。两者默认
均启用。在 `/dev/serial/by-id/` 上使用 115200/8N1 的串口终端，即可获得
无需密码的物理 root 控制台。
设置 `androidDevices.initrdUsb.acm.enable = false` 仅保留 NCM/SSH，或设置
`androidDevices.initrdUsb.network.enable = false` 仅保留 ACM。求值时会检查
内核内置支持，并拒绝两项功能均禁用或存在竞争的 initrd gadget/SSH 服务器的配置。
控制器端点容量和主机互操作性仍需真机验证。

SSH 监听 USB 地址的 22 端口，默认允许 root 无密码、无客户端密钥登录，与
minimal 示例相同。使用 `ssh -p 22 root@172.16.42.1` 连接。个人镜像如需
客户端密钥：

```nix
androidDevices.initrdUsb = {
  ssh.requirePublicKey = true;
  authorizedKeys = [ "ssh-ed25519 YOUR_PUBLIC_KEY" ];
  acm.enable = false; # Optional: also remove the unauthenticated physical console.
};
```

完整 recovery 在 Linux 根分区的
`/var/lib/mobile-recovery/ssh/ssh_host_ed25519_key` 保存自己的 Ed25519 SSH
主机密钥，与已安装系统的 SSH 身份及客户端授权相互独立。已有密钥通过临时只读
挂载读取；缺少密钥时在本地生成，并通过短暂的读写挂载保存。私钥属主为 root，
权限 0600，绝不会包含在镜像、Nix store 或源码仓库中。

这要求所配置的内部分区、设备树 compatible、控制器、ext4 标签和干净的文件
系统状态均匹配。分区缺失、Android userdata、处于活动/脏状态的文件系统、
不安全的密钥路径和无效密钥都会回退为新的仅 RAM 身份。Recovery 不会自动修复
文件系统，也不会自动替换已存在的损坏密钥。该准备步骤的服务超时为 15 秒，
且不得阻止 SSH 启动。不会保留任何已挂载的目标文件系统。minimal recovery 和
普通早期启动仍使用仅 RAM 的密钥。在完整 recovery 中禁用持久身份：

```nix
androidDevices.initrdUsb.ssh.hostKeyStorage.enable = false;
```

通过 ACM 读取 `/run/mobile-recovery/ssh-host-key-state`（`persistent` 或
`temporary`）和 `/run/mobile-recovery/ssh_host_ed25519_key.pub` 以核对身份。
控制台也会显示状态和指纹。使用与已安装系统分开的 known_hosts 文件。在可信的
USB 连接上建立初始信任；保持严格的主机密钥检查。只要已保存的密钥仍可访问，
多次启动 recovery 都使用同一身份。在使用临时密钥启动、重新格式化或删除已保存
的密钥后，先核对新指纹，再仅更新该 recovery 主机的条目。在运行中的 recovery
会话里分区不会改变其身份；持久化从下一次启动开始生效。
如果格式化 Linux 根分区后重启过 recovery，首次安装会保留这两个身份文件。
其他意外文件仍会阻止初始安装。需要日志恢复的文件系统在显式修复前使用临时身份。
加载时，公钥文件由私钥导出。

定义主机别名 `RECOVERY_HOST`，包含地址、22 端口、用户 root 和上述
known_hosts 文件。在运行非交互 CLI 前，先用交互式 SSH 建立信任。只有使用
密钥认证的自定义镜像才需要 IdentityFile。

```sh
ssh RECOVERY_HOST
mobile-device recovery --target RECOVERY_HOST status
mobile-device recovery --target RECOVERY_HOST shell
mobile-device recovery --target RECOVERY_HOST push ./file /tmp/file
mobile-device recovery --target RECOVERY_HOST pull /tmp/file ./download
mobile-device recovery --target RECOVERY_HOST exec journalctl -b --no-pager
```

使用单独的 SSH 配置时，运行 `recovery --ssh-config FILE --target HOST`，或在
可选的设备 TOML 中设置 `target` 和 `ssh_config`。`serial` 仅用于选择 fastboot。
同样可以使用 SFTP 以及普通的 SSH TCP/Unix socket 转发。

<a id="recovery-operations"></a>
## Recovery 操作

所有设备的完整 recovery 都使用 Rust 守护进程、屏幕界面和 `recovery shell` 客户端。
recovery initrd 不包含 Python。目标 chroot 中的标准 NixOS 工具使用其自身的依赖，
包括 Python。

```sh
recovery capabilities
recovery status
recovery mount-target --rw
recovery rebuild boot --flake /etc/nixos#DEVICE
recovery generations
recovery select-generation 12 --confirm
recovery unmount-target
recovery deploy-check-boot
recovery reboot-system --confirm
```

将 `DEVICE` 替换为你配置的主机名；选择系统代是回滚的另一种显式方式。所有请求的
安装/更新写入都经由守护进程，包括主机端的 `mobile-device recovery deploy`。
客户端可以断开，再用 `recovery task TASK_ID` 重新连接。recovery 没有不受限制的
`recovery enter`，也没有项目 shell 后端。Rust shell 接受上述命令，无需前缀 `recovery`。

破坏性的首次准备见 [Asphalt](asphalt/first-install.zh.md)、
[Sheng](sheng/first-install.zh.md)、[Aurora](aurora/README.zh.md)、
[Polaris](polaris/first-install.zh.md) 或 [Clover](clover/first-install.zh.md)。已有安装
保留其根分区/ESP 布局。传输、取消和失败语义见
[recovery 屏幕包](../pkgs/mobile-recovery-screen/README.zh.md)。守护进程的存储和
首次安装操作尚未在每块板子上经过真机验证。

### 初始安装后的 store 访问

Recovery 守护进程对自身状态使用私有 umask。但已安装的 `/nix` 以及
store/profile 的父目录必须可被系统服务用户读取和遍历。初始安装、部署和
系统代选择共用此设置，并以非特权数字 UID 验证执行。只读启动检查会拒绝
不可访问的父目录。修复旧安装时，以读写方式挂载，并再次显式选择其当前系统代；
这会重新安装其 EFI 条目，而不改变系统或固件。不会递归 chmod 私有的 Nix
DB 内容和其他目录。

### 启动中断后的文件系统

非正常关机可能使 Linux ext4 日志或 FAT ESP 处于脏状态。普通的挂载/部署检查
仍保持只读。在 RAM recovery 中显式修复：

```sh
recovery repair-filesystems --check
recovery repair-filesystems --confirm
```

守护进程验证配置的槽位和存储角色、现有分区和文件系统身份，要求存储处于未挂载状态，
然后执行 ext4 日志恢复/preen 和 FAT 自动修复。只接受退出码 0（干净）和
1（已修正）；其他结果会停止操作以便调查。之后两个文件系统都必须通过单独的
只读检查。它不会格式化分区，也不会触及 Android userdata。

只读 FAT 检查只容忍一项结果：FSInfo 空闲簇计数错误（"Free cluster summary
wrong"）。该计数只是提示值，U-Boot 的 FAT 写入（systemd-boot 的随机种子、EFI
变量）会使其过时，Linux 会重新统计；检查只记录日志，不做任何修复。其他任何
FAT 问题仍会停止操作。

<a id="stale-backup-gpt-after-an-oem-slot-change"></a>
### OEM 切换槽位后过时的备份 GPT

如果部署因 GPT CRC 或副本不一致而拒绝执行（备份处于修复范围内时，错误信息会给出
磁盘并指向此处），请保留元数据，并在做任何修改前检查两份副本。A/B recovery 为包含
固件槽（`boot_b`；MediaTek 为 `boot_a`）和 `userdata` 的磁盘提供显式且范围严格的修复：

```sh
recovery repair-backup-gpt --check
recovery repair-backup-gpt --confirm
```

此操作要求处于 RAM recovery、没有已挂载的块设备文件系统、B 为活动槽且经过独立验证
（依据主 GPT）、主 GPT 头部和数组 CRC 有效、备份头部 CRC 有效，且几何参数一致（头部
位置、可用范围、磁盘 GUID、条目数量与大小）。备份数组的 CRC 可以是过时的。每个不同的
备份条目必须：

- 属于名为 `<name>_a` 或 `<name>_b` 且对应分区存在的分区；
- 唯一 GUID、起止 LBA 和名称不变；
- 只在类型 GUID（任意非零类型：Qualcomm 固件成对互换类型，小米固件还会给非活动槽
  设置占位类型）以及属性位 48-55（Qualcomm 槽位标志）和 60 上不同。

未使用的条目和其他所有分区必须完全一致。它不会修复损坏的主 GPT/头部，也不会在不同
布局之间做选择。`--check` 按磁盘列出不同条目的数量以及备份 CRC 是否过时。确认后会在
RAM 中保存每个磁盘的两份元数据副本，仅在现有位置用主 GPT 重写备份数组/头部，并验证
回读和两份副本。重启前请下载报告的快照。普通安装/更新操作仍保持严格检查，绝不隐式
修复。

<a id="single-slot-devices-clover-and-polaris"></a>
## A/B 设备：准备 Linux 存储

在 A/B 设备（Asphalt、Sheng、Aurora、Marble 与 T880）上，Linux 位于 userdata
分配区内，该分配区必须是所在磁盘的最后一个分配区。`prepare-install` 为 Android
userdata 保留你选择的大小，并用其余空间创建 `linux-boot`（FAT ESP，标签 `BOOT`）
和 `linux`（ext4 根分区，标签 `NIXOS`）。
userdata 分配区以外的内容不变：A 槽、`super`、`misc`、`metadata`、`dtbo_*` 和
校准分区都会保留。

可选的 Android 大小为 32、64、128、256 和 512 GiB。只有当 Android 部分向上对齐到
1 MiB 后，Linux 的 ESP 与根分区仍能占用 userdata 分配区中至少 64 GiB 时，才会
提供该大小。例如 256 GB 的手机（约 224 GiB
userdata）提供 32G、64G 和 128G。没有符合条件的大小时拒绝拆分。

```sh
recovery prepare-install --check                              # lists the offered sizes
recovery prepare-install --android-userdata 64G --check       # shows the exact plan
recovery prepare-install --android-userdata 64G --confirm-erase-userdata
```

没有默认大小：确认时必须给出 `--android-userdata`。保留的 Android userdata 会被
清除（前 8 MiB 置零）；A 槽的 Android 在使用前需要恢复出厂设置。recovery 屏幕的
“Prepare Linux storage”提供同样的选择：先选大小，查看计划，再确认。不需要主机。

写入前，拆分会把原始 GPT（两份副本）保存在 recovery 内存中的
`/run/mobile-recovery/gpt-original`（检查已保存时直接使用）。已保存的副本与磁盘
不一致时拒绝写入。在 recovery 重启之前，先运行 `recovery restore-gpt --check`，
再运行 `--confirm`，即可用该副本撤销拆分（Linux 分区及其数据将无法访问）。
重启后内存副本即丢失；需要永久副本时使用主机流程，它会在写入前下载副本：

```sh
mobile-device recovery --target … prepare-install --android-userdata 64G \
  --gpt-backup DIR --execute
mobile-device recovery --target … restore-gpt --gpt-backup DIR --execute   # 之后撤销
```

不带 `--gpt-backup` 时，`mobile-device … prepare-install --execute` 和
`restore-gpt` 使用内存副本。已有安装不会重新分区；仅影响新的拆分。

## 单槽设备：Clover 与 Polaris

Clover 和 Polaris 没有 A/B 槽位。物理 `userdata` 是 ext4 根分区，物理 `system`
是 FAT `/boot`；GPT 始终不变。recovery 将每个存储角色（root、ESP、firmware、
recovery、misc）解析为内部存储控制器上唯一的 GPT 名称，并核对内核分区几何信息。
`hardware.<device>.storageRoles` 中的实测值也必须一致：

```nix
hardware.polaris.storageRoles.root = {
  partuuid = "YOUR_USERDATA_PARTUUID";
  number = 21;          # GPT entry number
  offset = 1234567;     # start in 512-byte units (blkid PART_ENTRY_OFFSET)
  bytes = 115964116992;
};
```

两者仅凭 GPT 名称即可工作。Clover 还会核对原厂 64 MiB 的 `boot`、`recovery`
和 1 MiB 的 `misc` 容量；其 ESP 是 eMMC 上唯一的 `system`，且容量须在合理范围内。已安装系统
携带相同的角色定义，角色不一致的系统会被 recovery 拒绝。

```sh
recovery format-root --check          # erases only the root role
recovery format-root --confirm
recovery prepare-boot --check         # formats FAT /boot if it is not already FAT
recovery prepare-boot --confirm
```

`prepare-boot` 要求根分区已格式化且为空，或其中的 store 能通过校验；首次安装完成前
会保留待处理标记。Polaris 在每次存储操作前启用 UFS 时钟安全模式（`recovery safe-ufs`
可单独执行）。`reboot-recovery` 以事务方式向 misc 的 BCB 写入 `boot-recovery`；
`reboot-system` 和 `reboot-bootloader` 会清除它。不写 BCB 时（A/B 设备以及
`poweroff`），`reboot-recovery`、`reboot-bootloader` 和 `poweroff` 只要求没有挂载 UFS
文件系统，不读取分区表或槽位元数据，因此损坏的 GPT 不会把你困在 recovery 中。
`reboot-system` 仍会先检查已安装系统，这一步会读取分区表。`prepare-install`
和备份 GPT 修复仅适用于 A/B 设备。

格式化、EFI 部署、受支持的 recovery
镜像安装和重启命令均可通过 SSH 使用。所有受支持的板子都提供
[共享的 `install-initial` 流程](initial-install.zh.md)，用于已准备好的空根分区和
FAT 启动分区。它安装 EFI 代际。固件使用[独立 U-Boot 流程](u-boot-install.zh.md)，
之后显式重启。

## 全部 userdata 的 Linux 布局

`androidDevices.recovery.daemon.linuxOnly` 默认为 `false`，Unicorn 启用此选项。
在支持的 A/B 设备上，它将全部 userdata 空间替换为 Linux ESP 和根分区，保留其他
GPT 项，拒绝 `--android-userdata` 参数。CLI 和屏幕先显示只读计划，再明确确认
清除数据。检查和实际写入路径均先在 RAM 保存原始 GPT；恢复前校验原 userdata
边界及无关分区项。恢复 GPT 无法恢复已被覆盖的文件系统数据。其他设备保留原流程。
