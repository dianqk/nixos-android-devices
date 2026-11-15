# 小米 Redmi Note 12 Turbo / POCO F5（marble）

[English](README.md) · [全部设备](../README.zh.md) · [支持状态](status.zh.md) · [内核补丁](../../pkgs/linux-kernel/sm7475/marble/PATCHES.zh.md)

状态：**实验性。** `boot_b` 上的 U-Boot 已在实机上启动，提供
USB ACM 控制台、屏幕、按键与只读 UFS 访问。RAM recovery 可通过 `fastboot boot` 在实机上
启动（Linux 7.3、USB 控制台与网络、UFS、触摸与按键）。在装有 36 0d 0b 面板的机器上，
一个测试构建启动即可显示画面，已安装系统可在其上启动图形会话；当前内核尚未验证
（见[显示面板](#显示面板)）。该机（型号 23049RAD8C）使用骁龙 7+ Gen 2（SM7475），与 SM8450/SM8475
共用时钟、引脚与 UFS 模块。Android 保留在 A 槽；NixOS 只使用 B 槽。

## 产物

| 输出 | 内容 |
| --- | --- |
| `devices.marble.u-boot` | 供 `boot_b` 使用的 v4 头 boot 镜像：U-Boot v2026.10 作为 gzip 内核，其后附加板级 DTB，无 ramdisk。 |
| `devices.marble.kernel` | Linux 7.3，带 [Marble 补丁队列](../../pkgs/linux-kernel/sm7475/marble/PATCHES.zh.md)与 `qcom/sm8475-xiaomi-marble.dtb`。 |
| `devices.marble.recovery` | RAM recovery：同一 U-Boot 镜像，以 FIT（内核、initrd、DTB）作为 ramdisk。 |
| `devices.marble.firmware` | 原厂 OEM 固件（非自由软件），输出 `out`、`dsp`、`modem`、`audio` 与 `sensors`；见[固件](firmware.zh.md)。 |
| `devices.marble.system` | 带 USB 网络的示例控制台系统（未测试；见[安装 NixOS](#安装-nixos实验性)）。 |

```sh
nix build .#devices.marble.u-boot --out-link result-u-boot
nix build .#devices.marble.recovery --out-link result-recovery
```

请使用导出的模块 `nixosModules.marble`；本机选项位于 `hardware.marble.*`。

## U-Boot

每次启动都会开启 USB ACM 控制台（主机上的 `/dev/ttyACM*`）与屏幕控制台，然后扫描
UFS。没有 `linux-boot` ESP 时 U-Boot 打开菜单：列出所有 UFS LUN 的分区表（只读）、
USB 串口控制台、shell、重启与关机。音量键移动，电源键选择；U-Boot 启动时按住音量减
可直接打开菜单。由于 ACM 控制台占用唯一的 USB gadget 槽位，不提供 UMS 和 Fastboot。

UFS 扫描之后 U-Boot 倒计时 3 秒再启动。在 ACM 控制台按任意键或按音量键会停在
U-Boot shell（`run menucmd` 打开菜单）；shell 空闲 60 秒后会重新启动。

存在 ESP 时，U-Boot 从 `linux-boot` 加载 `/EFI/BOOT/BOOTAA64.EFI`，随后把 B 槽标记为
成功：在检查所有 UFS GPT 与槽位标志之后，只在 `boot_b` 所在 LUN 的两份 GPT 副本中设置
其成功位，ABL 因此不再递减 B 槽的重试次数。除此之外不写任何内容（不写 BCB、PON 状态或
环境变量）；检查失败时记录日志并继续启动。见[引导操作](../boot-actions.zh.md#automatic-slot-b-confirmation)。

请以 raw 模式、关闭回显打开 ACM 控制台（例如 `picocom -b 115200 /dev/ttyACM0` 或
`screen /dev/ttyACM0`）。直接 `cat /dev/ttyACM0` 时终端会把菜单的转义序列回显给
U-Boot，被当作按键处理，可能选中“关机”等菜单项。

## RAM recovery

recovery 镜像与 U-Boot 一样由原厂引导程序（ABL）启动。ABL 加载 v4 头镜像时会同时
加载 `vendor_boot_b`，并把镜像自身的 ramdisk 放在 vendor ramdisk 之后。U-Boot 读取
`vendor_boot_b` 的头部（只读），在 vendor ramdisk 之后找到标记为
`android-devices,payload = "ram-recovery"` 的 FIT，复制到 fastboot 缓冲区并启动。
没有该 FIT 的 boot 镜像（已安装的 `boot_b`）照常启动。recovery 的 USB 序列号为
`RECOVERY_MARBLE`，USB 网络地址为 `172.16.48.1`。

在原厂引导程序的 fastboot 模式下、B 槽为活动槽且 `dtbo_b` 有效（见下文）时启动，
不会写入手机：

```sh
fastboot set_active b
fastboot boot result-recovery
ssh root@172.16.48.1
```

recovery 的 SSH 服务允许 root 无密码登录。若客户端先提供多个密钥，可能达到服务端
的认证次数上限；此时加上 `-o PubkeyAuthentication=no`。

## 显示面板

Marble 装有两种 M16T 面板之一：「36 02 0a」或「36 0d 0b」，各有自己的 Linux 驱动。
U-Boot 读取 ABL 给出的面板名，并在交给 Linux 的设备树中选择对应的驱动与 vddd 电压，
因此同一份构建适用于两者。36 0d 0b 已在实机上验证；36 02 0a 本项目未测试。面板表、
选择方式、如何确认手机的面板以及内核所需的显示交接见
[显示面板](display.zh.md)。

## 存储

NixOS 使用 LUN 0 的 userdata 分配区（`userdata` 是其最后一个分区）：recovery 的
`prepare-install` 为 Android userdata 保留所选大小（256 GB 机型为 64 或 128 GiB），
并用其余空间创建 FAT ESP `linux-boot`（标签 `BOOT`）和 ext4 根分区 `linux`（标签
`NIXOS`）。保留的 Android userdata 会被清除；之后 A 槽 Android 需要恢复出厂设置。
A 槽、`super`、`misc`、`metadata`、`dtbo_*` 与校准分区保持不变。见
[recovery](../recovery.zh.md)。

## 安装 NixOS（实验性）

尚未在实机上试过。模块安装原厂 GPU、视频、Wi-Fi、蓝牙、ADSP 与 SLPI 固件
（见[固件](firmware.zh.md)，非自由软件：需允许 `marble-firmware` 与
`marble-firmware-zstd`）；基带可选（`hardware.marble.modem.enable`，实验性，见
[基带](../modem.zh.md)），音频亦可选（`hardware.marble.audio.enable`，见[音频](#音频)）。已安装系统通过 USB 访问（序列号
`MARBLE`，ACM 控制台与位于 `172.16.48.1` 的 SSH）。

1. 用同一份锁定配置构建 recovery、系统及其闭包信息（此处为 `devices.marble.*`，或你自己
   导入 `nixosModules.marble` 的配置）：

   ```sh
   nix build .#devices.marble.recovery --out-link result-recovery
   nix build .#devices.marble.system --out-link result-system
   nix build .#devices.marble.bootstrap-info --out-link result-bootstrap-info
   nix build .#devices.marble.u-boot --out-link result-u-boot
   ```

2. 启动 RAM recovery（见 [RAM recovery](#ram-recovery)）；若 `linux-boot` 与 `linux`
   尚不存在，先划分一次存储（见[存储](#存储)；可在 recovery 界面中进行，或者）：

   ```sh
   mobile-device recovery --target root@172.16.48.1 prepare-install --android-userdata 64G
   mobile-device recovery --target root@172.16.48.1 prepare-install --android-userdata 64G \
     --gpt-backup ./marble-gpt-original --execute
   ```

3. 检查启动 LUN 的备份 GPT。原厂 ABL 切换槽位（`fastboot set_active b`）时只更新主
   GPT；过时的备份会让 recovery 的所有写入操作以及 U-Boot 的槽位确认拒绝执行。若检查
   报告需要修复，确认无误后执行（只写备份副本；见
   [recovery](../recovery.zh.md#stale-backup-gpt-after-an-oem-slot-change)）：

   ```sh
   ssh root@172.16.48.1 recovery repair-backup-gpt --check
   ssh root@172.16.48.1 recovery repair-backup-gpt --confirm
   ```

   之后每次 `fastboot set_active` 后都要再检查一次。

4. 如果设备尚无兼容的 U-Boot，在 RAM recovery 中单独刷写到 `boot_b`：

   ```sh
   mobile-device recovery --target root@172.16.48.1 install-image ./result-u-boot \
     --partition /dev/disk/by-partlabel/boot_b
   mobile-device recovery --target root@172.16.48.1 install-image ./result-u-boot \
     --partition /dev/disk/by-partlabel/boot_b --execute
   ```

5. 检查并安装。该操作把闭包写入空的 `linux`，把 systemd-boot 与系统代安装到
   `linux-boot`。安装成功后显式重启。

   ```sh
   mobile-device recovery --target root@172.16.48.1 install-initial \
     "$(readlink -f result-system)" --bootstrap-info ./result-bootstrap-info
   mobile-device recovery --target root@172.16.48.1 install-initial \
     "$(readlink -f result-system)" --bootstrap-info ./result-bootstrap-info --execute
   mobile-device recovery --target root@172.16.48.1 reboot system --execute
   ```

之后 ABL 从 `boot_b` 启动 U-Boot，U-Boot 从 `linux-boot` 加载 systemd-boot 并把 B 槽标记为
成功，ABL 因此不再回退到 Android。较早的系统代仍可在 systemd-boot 菜单中选择。菜单暂不提供
重启到 recovery 或 Android：要回到 recovery，请进入原厂 fastboot 模式（开机时按住音量减）并
`fastboot boot result-recovery`；`fastboot set_active a` 返回 Android。失败处理见
[首次安装](../initial-install.zh.md)。

## 音频

状态：两只扬声器与底部麦克风已在实机（Linux 7.3）上可用：音乐可从每只扬声器以原厂 Android 的功放电平清晰播放，麦克风可录音。语音通话、作为通话输出的听筒以及有线耳机（耳机与耳麦麦克风）尚不支持。
`hardware.marble.audio.enable = true;`（默认关闭）会安装：

- AW88263S 扬声器功放配置 `qcom/sm8475/xiaomi/marble/aw88261_acf.bin`，由固件源中
  原厂 `aw882xx_acf.bin` 派生（`audio` 输出，见[固件](firmware.zh.md)）；
- AudioReach 拓扑 `qcom/sm8450/SM8475-Xiaomi-Marble-tplg.bin`，由
  [`pkgs/marble/audio`](../../pkgs/marble/audio) 构建：MultiMedia1 经第三路 TDM 接口
  播放到两只扬声器（96 kHz、32 位、四时隙帧；与原厂 Android 相同，驱动时隙 0-2），MultiMedia3 经 `TX_CODEC_DMA_TX_3`
  从 WCD9385 录音；
- 供 PipeWire 与 WirePlumber 使用的 ALSA UCM 配置（verb `HiFi`，设备 `Speaker` 与
  `Mic`），以及 `alsa-utils`。

声卡为 `SM8475-Xiaomi-Marble`（驱动 `sm8450`）。控件按扬声器的物理位置命名，与原厂引脚名
（`aw882xx_reset_active_top`/`_bot`）一致：

| 控件前缀 | 功放 | TDM 时隙 | 扬声器 |
| --- | --- | --- | --- |
| `Speaker Top` | I2C 0x34 的 AW88263S | 0（左） | 顶部，听筒一端；gpio52 将其切换到听筒 |
| `Speaker Bottom` | I2C 0x35 的 AW88263S | 1（右） | 底部 |

UCM `Speaker` 设备同时输出到两者。UCM verb 将两颗功放设为 `Music`
配置、音量 349/360（每级 0.25 dB，即 -2.75 dB，为该配置自身的音量，原厂 Android
播放时也保持该值）；主机侧没有扬声器保护，请用 PipeWire 输出音量保持适中音量。麦克风为 AMIC1，经 ADC1 与 TX macro DEC0。内核细节见
[7.3 上的扬声器 TDM](../../pkgs/linux-kernel/sm7475/marble/PATCHES.zh.md#73-上的扬声器-tdm)。

不播放任何声音即可检查声卡与控件：

```sh
cat /proc/asound/cards
aplay -l; arecord -l
alsaucm -c SM8475-Xiaomi-Marble list _verbs
amixer -c SM8475-Xiaomi-Marble contents | grep -A2 -E "Speaker (Top|Bottom)"
```

## 传感器

状态：实验性；加速度计与屏幕旋转已在实机上于四个方向验证。
`hardware.marble.sensors.enable`（默认关闭）把 SLPI 传感器接入共享的 [SSC 传感器支持](../sensors.zh.md)：在 `/dev/fastrpc-sdsp` 上运行
`sdsprpcd sensorspd`，以及 libssc 与 iio-sensor-proxy。固件的 `sensors` 输出包含 SSC
registry 默认值（由固件归档中的原厂传感器配置生成，见[固件](firmware.zh.md)）与 SLPI
FastRPC 库。内核加载 SLPI 固件并订阅其 `msm/slpi/sensor_pd` 域（见
[SLPI 传感器](../../pkgs/linux-kernel/sm7475/marble/PATCHES.zh.md#slpi-传感器)）。

```nix
{
  hardware.marble.sensors.enable = true;
}
```

之后 iio-sensor-proxy 根据 BMI26x 加速度计报告屏幕方向；会话可用任意 iio-sensor-proxy
客户端旋转输出（例如 niri 在 `DSI-1` 上使用 iio-niri）。加速度计按 Android 设备坐标轴
报告，因此使用默认的单位安装矩阵（共享 SSC 后端已为 iio-sensor-proxy 适配坐标轴）；
其他取值只是剩余校正，必须在四个方向上确认。

registry 只在首次播种到 `/var/lib/ssc-sensors`，更新时保留；SLPI 写入的校准也保存在
那里。不导入 Android persist 分区中的出厂校准（屏幕方向不需要）。其他 SSC 传感器
（TCS3701 的环境光与接近、磁力计、SAR）在 registry 中，但尚未配置或检查。

启动后检查：

```sh
systemctl status android-ssc-sensors iio-sensor-proxy
ssccli --sensor accelerometer --timeout 2
monitor-sensor --accel
```

## 挂起与唤醒

状态：实验性；`deep` 挂起已在实机上以 UFS `spm_lvl` 3 验证。固件提供
`deep`（PSCI 系统挂起，内核默认）与 `s2idle`。`hardware.marble.suspend.memSleep`
（默认 `null`，即内核的选择）设置后会加入 `mem_sleep_default=`；
`hardware.marble.suspend.ufsSpmLevel`（默认 `null`）设置后在启动时写入 UFS 主机的
`spm_lvl`。`null` 保留补丁 0081 带来的内核级别 5（与 Asphalt 相同，其 UFS PHY 在 CX
断电后不保留状态）。有了 SM8475 UFS 系列（0082-0091），级别 5 在 Marble 上可从
`s2idle` 正常恢复；此前以级别 5 挂起后 UFS 控制器无法重新启用。`s2idle` 可选，但尚未在 Marble 上测量。PMK8350 RTC 闹钟已启用，用于 RTC 唤醒（RTC 时间由固件管理，Linux 无法设置）。

在电池供电下以 `deep` 验证：各级 `pm_test`；20–35 秒的真实挂起中 RTC 唤醒与电源键唤醒；
唤醒后 Wi-Fi、各 remoteproc（modem、ADSP、SLPI）、ModemManager、音频、显示、触摸、
传感器与 UFS 读取均正常。

SoC 低功耗状态：在没有补丁 0080/0081 与相机时钟控制器驱动的内核上，挂起期间 SoC 从未
进入睡眠状态（`/sys/kernel/debug/qcom_stats` 中 `aosd`、`cxsd` 与 `ddr` 计数一直为 0，
平均耗电约 137 mA）。由于相机时钟控制器、GMU 与 QCE 节点没有驱动，RPMh 电源域、GCC、
GPUCC 与互连的 `sync_state()` 一直未完成；在此之前 RPMh 电源域把所有电源轨保持在最高
档位，互连保持启动时的带宽。内核现在编译相机时钟控制器驱动，带有共享的 GMU 系列并禁用
QCE，因此这些都能完成。随后第一次 74 秒的 `deep` 挂起仍未进入 CX 或 DDR 睡眠
（`aosd`/`cxsd`/`ddr` 计数为 0，DDR 停在最低频率）；其余的投票者尚未查明。已安装系统不再传入
`clk_ignore_unused` 与 `pd_ignore_unused`：启动时关闭未使用的时钟与电源域，显示、触摸、
存储、USB、Wi-Fi、调制解调器、传感器、音频设备、相机与 `s2idle` 均正常工作。设置
`hardware.marble.ignoreUnusedClocksAndDomains = true` 可恢复这两个参数；RAM recovery
仍保留它们。已安装系统同样不传入 `regulator_ignore_unused`：每个在用的稳压器都有消费者，
存储在写入负载下没有错误。设置 `hardware.marble.ignoreUnusedRegulators = true` 可恢复它；
RAM recovery 仍保留它。启动日志中的
`sync_state() pending due to …` 会指出仍在阻止它的消费者。

设备模块为共享的[唤醒策略](../configuration.zh.md#挂起唤醒源)声明了唤醒源：
`powerKey`、`volumeKeys`（音量加）、`rtc`（闹钟与 alarmtimer）、`battery`（电池管理器的
电池供电）、`usbPower`（电池管理器的 USB 与无线供电、UCSI）、`adsp`（ADSP remoteproc：
电池管理器、Type-C 与音频）、`modem`（MPSS：经 QMI 的来电与短信）、`mobileData`（IPA）、
`sensors`（SLPI remoteproc）、`thermal`（TSENS）和 `wifi`（WCN6855）。目前只保留
`powerKey`、`volumeKeys` 与 `rtc`；插入 USB 暂不能唤醒设备：

- 各 remoteproc（`adsp`、`modem`、`sensors`）会唤醒设备：较长的 deep 挂起约每七分钟结束一次，
  没有 Linux 唤醒中断，而 glink 与 AOSS 消息计数增加（最可能是 ADSP 上电池管理器的周期性
  状态）。在没有“暗唤醒后再次挂起”的策略之前，保留它们只会缩短挂起时间。来电与短信
  （`modem`）需要先有该策略。在没有上述 `sync_state()` 修复的内核上，只保留 `powerKey`、
  `volumeKeys` 与 `rtc` 的挂起也在约 450 秒后结束，没有唤醒中断。
- `wifi` 不是有效的唤醒源：WCN6855 在挂起期间断电，唤醒时重新上电。
- `mobileData`：没有 SIM 卡或数据连接时，IPA 在挂起几秒后唤醒设备且没有唤醒中断。
- `battery` 与 `usbPower`：这些电池管理器与 UCSI 供电通过 pmic_glink 接收同样的 ADSP
  周期性状态。保留 `battery` 时设备约两分钟后唤醒；保留 `usbPower`（且没有其他 glink
  唤醒源）时约三分钟后唤醒，同样没有唤醒中断。
- 挂起的设备不需要 `thermal`。

启用所有驱动默认唤醒源时，设备几乎立即唤醒。例如：

```nix
{
  androidDevices.power.wakeup = {
    enable = true;
    keep = [ "powerKey" "volumeKeys" "rtc" ];
  };
}
```

已知问题：八次唤醒中有两次，WCN6855 固件在唤醒后不久崩溃（PCIe 可纠正错误，随后
`firmware crashed: MHI_CB_EE_RDDM`）；ath11k 重启固件，Wi-Fi 在约 15 秒内重新连接。
无论 `wifi` 是否为唤醒源都会出现。

## 测试与安装

请先检查镜像（见软件包 README）。然后在原厂引导程序的 fastboot 模式下：

1. 可选，不写入：`fastboot boot result-u-boot`。
2. 只安装到 B 槽并切换：

   ```sh
   fastboot flash boot_b result-u-boot
   fastboot set_active b
   fastboot reboot
   ```

不要写入 `boot_a`、`super`、`userdata`、`persist`、`modem*` 或 `fsg`。在已安装系统的
EFI 入口被加载（从而把 B 槽标记为成功）之前，ABL 用完重试次数后会回退到 A 槽；随时可用
`fastboot set_active a` 返回 Android，`fastboot set_active b` 会重置次数。

**保持 `dtbo_b` 有效。** 与可以擦除 `dtbo_b` 的 Asphalt 和 Aurora 不同，Marble 的
ABL 在 `dtbo_b` 被擦除或无效时拒绝启动 B 槽（正常启动和 `fastboot boot` 都是如此）：
它会减少重试次数并停留在 fastboot。若已擦除，请从 `dtbo_a` 恢复。该 overlay 只修改
ABL 传给 U-Boot 的 DT；Linux 的 DTB 来自 U-Boot。

## 致谢

本移植基于 iLtanaka（Tatsuki Tanaka）的工作：

- [u-boot-marble](https://github.com/iLtanaka/u-boot-marble)：U-Boot 移植，其提交
  构成本软件包的补丁序列
- [linux-marble](https://github.com/iLtanaka/linux-marble)：主线 Linux 移植，其提交
  构成内核补丁队列
- [pmaports 的 `marble` 分支](https://github.com/iLtanaka/pmaports/tree/marble)：
  postmarketOS 打包，包括此处使用的内核命令行
- [firmware-xiaomi-marble](https://github.com/iLtanaka/firmware-xiaomi-marble)
- [Wiki 页面](https://wiki.nura.eco/wiki/Xiaomi_POCO_F5_/_Redmi_Note_12_Turbo_(xiaomi-marble))

SM8475 引脚控制器、设备树以及 SM8475 UFS、cpufreq 与 pd-mapper 支持由
Danila Tikhonov 完成；SM8450 显示、RPMh 与 GPU 设备树修改由 Jens Reidel 完成，
来自 [sm8450-mainline](https://github.com/sm8450-mainline) 项目。
