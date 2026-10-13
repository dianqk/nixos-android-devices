# Aurora 音频

[English](audio.md)

使用 OS1.0.3.0.UNACNXM Android 14 固件底包。启用 `hardware.aurora.audio.enable`
（已安装系统的默认值）时，Aurora 模块会安装 AudioReach 拓扑、UCM 以及原厂双
CS35L43 保护固件。RAM recovery 不包含音频固件和用户态路由。

通过 PipeWire 的立体声扬声器播放可用，每个声道分别送到各自的功放。未验证的内容见
[已知限制](#已知限制)。

## 逐机扬声器校准

在仍可获得 Android root 权限时，保留本机原始的 `persist/audio/crus_calr.bin` 和
`persist/audio/crus_calr.txt`。该文本文件标明上方（`T`）和下方（`B`）的原始校准
整数；使用这些整数，而不是括号中的电阻值。切勿复制其他手机的数值，也不要仅为初始化
Linux 而重新运行校准。

现有的固件 override 在 `bluetoothNvm` 之外还接受 `speakerCalibration`。两者放在
同一个 override 中：

```nix
{ inputs, pkgs, ... }: {
  hardware.aurora.firmwarePackage =
    inputs.androidDevices.legacyPackages.${pkgs.stdenv.buildPlatform.system}
      .devices.aurora.firmware.override {
        firmwareVariant = "android14";
        bluetoothNvm = ./hmtnv20.b2e;
        speakerCalibration = builtins.fromJSON
          (builtins.readFile ./aurora-speaker-calibration.json);
      };
}
```

该 JSON 文件必须包含 `top` 和 `bottom`，各为不大于 16777215 的正整数。请把它和
蓝牙 NVM 私下保存。公开固件包含的是产品调音系数，而不是个人校准数据。UCM 加载保护
DSP，并在启用功放前把这些值写入每个 `CAL_R_SEL` 控件。没有该 override 时，不会注入
出厂校准；不能认为声学保护已经验证。

## 播放与诊断

扬声器 PCM 全程使用立体声 48 kHz **S32_LE**。PipeWire/ALSA 可以转换应用的格式，
但直接对 `hw:0,0` 播放时必须使用 S32_LE。S16_LE 前端直接连到 S32_LE TDM 后端会使
Android 14 的 `audio_process`/ADSP 崩溃，因此拓扑为扬声器播放声明 S32_LE，PCM 驱动
也接受该格式。

UCM 同时匹配声卡型号和内核的 `xiaomi-Xiaomi14Ultra` 长名称。DSP 固件文件名为小写，
这是上游 wm_adsp 文件名规范化的要求。HiFi 启用序列把两个功放的数字音量初始化为
-12 dB；应用音量应从低开始，并使用柔和的素材。DSP 预加载后，有界的就绪检查会等待
两个动态校准控件就绪，再写入出厂值并启用输出。超时会中止启用序列；不得以未校准的
播放绕过这一检查。

HiFi verb 会在 ACP 探测播放 PCM 之前启用 MultiMedia1 → secondary TDM 后端。随后，
Speaker 设备激活时加载/校准 DSP 并启用功放。如果只在 Speaker 序列中设置后端路由，
探测时将没有后端：PipeWire 会显示 Dummy Output，并报告 HiFi profile 不受支持。
选择 verb 时功放保持关闭，离开 HiFi 会断开该路由。按此顺序，正常启动后 PipeWire
会自动初始化扬声器 sink。

常用检查：

```sh
cat /proc/asound/cards
aplay -l
alsaucm -c hw:0 list _verbs
amixer -c 0 cget "name=B DSP1 Protection 5f210 CAL_R_SEL"
amixer -c 0 cget "name=T DSP1 Protection 5f210 CAL_R_SEL"
journalctl -k -b | grep -E 'cs35l43|wcd939|APM|audio_process|fatal error'
```

正常启动时会注册两个 CS35L43 A1 功放和 WCD9395 SoundWire 端点，加载原厂保护固件并
回读出厂校准。原厂固件/系数组合会报告轻微的算法版本差异；这些文件与原厂 Android 14
的组合一致，相关消息无害。

## 音量级

诊断无声之前，先检查所有音量级：应用流增益、PipeWire sink 增益/静音以及功放的数字
音量，它们相乘生效。UCM 把功放设为 -12 dB；线性增益为 0.5 的流还会再叠加约 -6 dB。
因此，即使桌面音量开到最大，本身较轻的素材仍可能偏小声。应从 `pw-dump` 读取 sink
实际的线性 `channelVolumes` 和 `softVolumes`，而不要假定应用的音量设置是唯一的衰减。
不要因为某段经过衰减的片段声音小就移除保护或提高功放增益。

PCM 写入成功或时钟/校准回读正常并不能证明有可听的输出；修改音频配置后应实际试听。

## 已知限制

- 麦克风录音、耳机音频/按键和蓝牙音频未验证。
- 持续或大音量输出时的声道平衡、响度和保护未验证。
- 没有逐机校准 override 时，声学保护未经验证。

## 实现说明

### 立体声帧格式

使用 DSP_A（短帧同步，一位数据延迟），与原厂 CS35L43 启动流程一致，配合四个 32 位
slot；I2S 长同步无法送达两个声道。声道 0 送到上方功放，声道 1 送到下方功放。该映射
相对机身固定，不随屏幕旋转变化。

### 扬声器 TDM 引脚

Aurora 使用主 TLMM 的 GPIO 121（时钟）、123（字选择）、122（data0）和 124
（data1），与原厂 `sec_tdm_pinctrl` 节点一致。LPASS LPI GPIO 6–9 提供名称相近的
功能，但不是本板的扬声器连接。使用这些错误引脚时，ALSA 流和 DSP 启动都会无声地
“成功”：两个功放均报告 `CLOCK_OK=0` 且 `AUDIO_IN_MAX` 为零。选择原厂 TLMM 功能后，
`CLOCK_OK=1` 且输入峰值非零。请在播放期间检查这些控件，因为空闲时的值不同。

### 共享供电约束

BOB1 同时为 USB 和显示使用的 LDO 供电。主线 `pmic5_bob` 的电压表为
`3000000 + n * 32000` 微伏。不要把其电压固定为原厂初始请求的 3296000：该值不可选，
会导致 regulator 注册失败，并移除其他 PM8550 regulator。这可能使 USB、存储和显示
一直等待供电，而不会出现内核 panic。本板使用上游 SM8650-HDK 的范围
3296000–3960000，并声明 BOB1 下游的 LDO 依赖，使未使用 regulator 的清理是安全的。

来源：[MiCode Aurora 音频驱动](https://github.com/MiCode/vendor_qcom_opensource_audio-kernel/tree/d2ddef03a379bc82c7bcd08481e29e08bbff80eb)、
[AudioReach TDM API](https://github.com/AudioReach/audioreach-graphservices/blob/3094583c726710b66eb0204fc5d6a7b336d9e575/spf/api/modules/pcm_tdm_api.h)、
[上游 SM8650 HDK](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/arch/arm64/boot/dts/qcom/sm8650-hdk.dts?h=v7.3-rc5)。

### TDM 时钟极性

原厂 Android 14 运行时 DT 请求 ADSP 时钟属性 4（`CLOCK_ATTRIBUTE_INVERT_COUPLE_NO`），
而 MiCode CS35L43 启动流程和手机日志在 codec 端选择 `DSP_A | NB_NF`
（`fmt=0x4004`）。这两项设置针对链路的不同两端。CPU DAI 保持 DSP_A/IB_NF，以保留
该 ADSP 时钟请求；codec DAI 保持 DSP_A/NB_NF，以匹配原厂的采样沿。若两端都从同一
格式推导，还会设置 codec 的 ASP_CONTROL2 BCLK 反相位。

Aurora 提供显式的 CPU TDM 格式；没有该 override 的板子保留现有的、由 codec 推导的
回退行为。此改动有意保留 48 kHz、四个 32 位 slot、DSP 保护和校准。codec TX 宽度与
原厂播放回调不同（Linux 中为 24 位，原厂为 32 位）。

来源：[MiCode codec 启动与 hw_params](https://github.com/MiCode/vendor_qcom_opensource_audio-kernel/blob/d2ddef03a379bc82c7bcd08481e29e08bbff80eb/asoc/codecs/cs35l43/cs35l43.c)、
[MiCode ADSP TDM 时钟请求](https://github.com/MiCode/vendor_qcom_opensource_audio-kernel/blob/d2ddef03a379bc82c7bcd08481e29e08bbff80eb/asoc/msm_common.c)、
[AudioReach 时钟属性](https://github.com/AudioReach/audioreach-graphservices/blob/3094583c726710b66eb0204fc5d6a7b336d9e575/spf/api/modules/audio_hw_clk_api.h)。
