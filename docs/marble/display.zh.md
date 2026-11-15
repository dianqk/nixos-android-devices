# Marble 显示面板

[English](display.md) · [设备指南](README.zh.md) · [内核补丁](../../pkgs/linux-kernel/sm7475/marble/PATCHES.zh.md)

Marble 装有两种 M16T AMOLED 面板之一（1080×2400，DSC 视频模式）。二者控制器不同，
因此 Linux 为每种各有一个驱动，U-Boot 在每次启动时选择正确的一个。

## 支持的面板

| | 36 02 0a | 36 0d 0b |
| --- | --- | --- |
| ABL 名称（`msm_drm.dsi_display0`） | `qcom,mdss_dsi_m16t_36_02_0a_dsc_vid` | `qcom,mdss_dsi_m16t_36_0d_0b_dsc_vid` |
| 原厂 `mi,panel-id` | `0x4d313654 0x360200` | `0x4d313654 0x360201` |
| Linux compatible | `xiaomi,marble-m16t-36-02-0a` | `xiaomi,marble-m16t-36-0d-0b` |
| Linux 驱动 | `panel-xiaomi-m16t-36-02-0a`（补丁 0016，来自 iLtanaka 的移植） | `panel-xiaomi-m16t-36-0d-0b`（补丁 0047） |
| vddd（PM8350B L1） | 1.2 V | 1.256 V（原厂 1.25 V 不是该稳压器的步进值） |
| 内核 DTB | 默认 | 由 U-Boot 选择 |
| 状态 | 本项目未在实机上测试 | 实机可用（见下文交接） |

两个驱动都编入同一内核镜像。

### 36 0d 0b

该驱动由
[linux-mdss-dsi-panel-driver-generator](https://github.com/msm8916-mainline/linux-mdss-dsi-panel-driver-generator)
从原厂设备树生成后修改：

- 供电按原厂顺序与延时：vddio 1.8 V、vci 3.0 V、vddd。
- 显示时钟交接（Asphalt 补丁 0020）：ABL 交接时有一个显示 PLL 仍在为 MDP 时钟供源。
  probe 时重新配置该 PLL 会让时钟停摆（启动时出现 `disp_cc_mdss_mdp_clk_src: rcg
  didn't update its configuration`）。显示时钟控制器现在保留已在运行的 PLL。用于该面板的
  内核需要此补丁，但仅有它还不够。
- 面板供电交接（0047）：ABL 交接时面板仍上电。若不先断电，面板启动时保持黑屏、所有 DCS
  读取失败，尽管 DSI 链路与背光都报告成功；一次显示关闭/开启循环后才会点亮。驱动在 probe
  时、连接 DSI 主机之前将面板断电（保持复位，按原厂顺序关闭供电，500 ms），使链路首次建立时
  面板是重新上电的。同时使用两项修复的内核在无诊断跟踪的情况下，两次实机启动均成功点亮面板。
- 复位：完整的高-低-高脉冲（高 11 ms、低 1 ms、高 11 ms），与 36 02 0a 面板相同。
  按原厂 36 0d 0b 序列（低 1 ms 后高 20 ms）复位后，面板不响应 DSI 命令。
- DSC：原厂上电序列通过厂商命令 `0x70` 写入解码器参数，其 PPS 为 DSC 1.1、10 bpc、
  8 bpp、540×12 slice（原厂设备树中的 slice 高度 20 并不是写给解码器的值）。驱动按这些
  参数编码，另以标准 PPS 发送同样的参数，并把两个 slice 放入一个包。
- 背光：DCS 亮度，12 位，高字节在前。面板关闭期间写入的亮度先保存，下次上电时发送（0047）。

## 面板选择

ABL 在传递的命令行中给出实际面板，例如
`msm_drm.dsi_display0=qcom,mdss_dsi_m16t_36_0d_0b_dsc_vid:`。内核 DTB 描述的是
36 02 0a。U-Boot 启动时把该名称从 ABL 的 `/chosen/bootargs` 复制到环境变量
`abl_panel`，并在每次把设备树交给 Linux 时设置对应型号的面板 compatible 与 vddd 电压：

- RAM recovery：`bootm` 启动 recovery FIT。
- 已安装系统：`bootefi` 以及 systemd-boot 为启动项 DTB 调用的 EFI 设备树修正协议。

U-Boot 控制台随后显示，例如：

```text
Panel: qcom,mdss_dsi_m16t_36_0d_0b_dsc_vid -> xiaomi,marble-m16t-36-0d-0b
Panel: vddd-supply at 1256000 uV
```

如果 ABL 未给出面板，或给出的名称不在表中，U-Boot 打印警告
（`Panel: unknown panel <name>; device tree unchanged`）并以未修改的 DTB 启动，
Linux 因此加载 36 02 0a 驱动。若实际是其他面板，屏幕很可能保持黑屏；RAM recovery 与
已安装系统的 USB 访问不受影响。该选择需要包含此功能的 U-Boot：RAM recovery 自带一份，
已安装系统则需 `boot_b` 为 `devices.marble.u-boot`。

## 如何确认手机的面板

- Android（root）：`tr ' ' '\n' < /proc/cmdline | grep dsi_display0`
- U-Boot ACM 控制台：上述 `Panel:` 行，或 `printenv abl_panel`
- Linux：

  ```sh
  cat /sys/firmware/devicetree/base/soc@0/display-subsystem@ae00000/dsi@ae94000/panel@0/compatible; echo
  ls /sys/bus/mipi-dsi/drivers/
  ```
