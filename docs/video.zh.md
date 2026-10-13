# 本地视频播放与编码

[配置](configuration.zh.md) · [English](video.md)

所有设备模块的 `androidDevices.video.ffmpegPackage` 均默认使用上游 `pkgs.ffmpeg`。
播放器使用上游 `pkgs.mpv`／`pkgs.celluloid`，无需替换 libmpv 的 FFmpeg 依赖。
VA-API 支持由独立配置的驱动与内核提供；默认选包不代表每台设备都已通过硬件验证。

## 可选 VA-API 驱动

导入设备模块后，可启用共享 Iris/Venus 后端：

```nix
{ pkgs, ... }: {
  androidDevices.video.vaapi.enable = true;
  environment.systemPackages = [ pkgs.ffmpeg pkgs.libva-utils ];
}
```

通过 `androidDevices.video.vaapi.package` 可替换后端。模块启用 graphics 并安装驱动，
不替换 FFmpeg／播放器，不设置全局 LIBVA 环境变量，RAM recovery 中不生效。
两个构建主机平台均导出原生 AArch64 `libva-v4l2` 包，以复用目标平台的图形库缓存。
构建平台、硬件验证命令、补丁、编解码限制及可选录屏 VPP 见
[驱动说明](../pkgs/libva-v4l2/README.md)。

## 可选的裁剪版 FFmpeg

保留的高通专用包用于直接 V4L2 M2M 诊断、后端对比，以及希望减少原生／交叉构建
依赖的本地 H.264/HEVC 应用。设备模块不再默认选用。如需显式选择带补丁的版本
（Venus 将 `asphalt` 替换为 `polaris`）：

```nix
{ androidPackages, config, ... }:
{
  androidDevices.video.ffmpegPackage = androidPackages.devices.asphalt.ffmpeg;
  environment.systemPackages = [ config.androidDevices.video.ffmpegPackage ];
}
```

此覆盖仅选择诊断用 FFmpeg，不会重新编译播放器。以下功能和依赖限制仅针对这个
可选包，不适用于上游默认包。

## 保留的功能

- H.264/HEVC 的 V4L2 M2M 编解码，以及 VAAPI 解码入口和编码器。VAAPI 需要单独安装
  兼容的驱动并具备内核支持；启用 API 不代表设备已经通过硬件验证。
- 本地容器、解析器、码流过滤器和内置音频、字幕编解码器。录音可使用内置 AAC 编码器。
- PNG/JPEG 封面和截图、原始帧、软件像素转换、音频重采样和内置过滤器。保留
  `ffmpeg`、`ffprobe` 和 libav 库，供播放器及采集程序使用。
- file/pipe/fd 和本地辅助协议；保留 lavfi 过滤器及诊断源。屏幕、音频采集由录屏程序
  提供，例如通过 PipeWire；不包含 FFmpeg 的 ALSA/Pulse 采集输入。

VAAPI 解码依赖内置 H.264/HEVC 解码器作为入口，因此也保留了这两个解码器的软件回退。
选择硬件解码属于播放器或应用策略。其他动态视频编码格式、x264/x265 等软件视频编码库
已移除。实际支持的格式和限制以设备硬件文档为准，包括 Polaris 的 HEVC Main 10 限制。

mpv 使用自己的 libass 渲染字幕。FFmpeg 仍负责内嵌文本、位图字幕的解封装和解码，
因此保留这些编解码器以及 Matroska 压缩支持。移除的是 FFmpeg 自己的 libass、字体
渲染过滤器；不能再使用 FFmpeg 的 `subtitles`/`ass` 过滤器烧录字幕。

## 依赖边界

此配置移除了 ffplay/SDL 及其 GTK 依赖链、网络播放和 TLS 库、无关厂商 GPU API、
OpenCL/CUDA/Vulkan 过滤器、外部视频及音频编解码库和文档生成器。显式库输入只保留
libdrm、libva-minimal、libc iconv 和 zlib。libdrm 关闭 Intel/PCI 和 Valgrind 支持。
构建平台遵循 `compilationPkgs`，支持 AArch64 原生构建和 x86_64 到 AArch64 的交叉构建。

这个边界只针对 FFmpeg。播放器自己的 libass、图形/音频后端或 GTK 前端仍有各自依赖。
全局 `pkgs.ffmpeg` 不变。依赖设备修复的直接 V4L2 诊断必须显式选择上述带补丁的版本。

## 检查

自定义 FFmpeg 构建关闭 `doCheck` 和 `doInstallCheck`。以下测试独立运行、按需执行，
不增加构建依赖。

在能够执行目标架构的机器上运行
`python3 tests/ffmpeg-local-playback.py /path/to/ffmpeg/bin /path/to/test-directory`。
测试不需要视频硬件，覆盖编解码器和协议边界、本地音频和字幕的封装/解码，以及 PNG
截图。设备上还需验证实际硬件后端；参见 [Asphalt 编码](asphalt/hardware.zh.md)。
