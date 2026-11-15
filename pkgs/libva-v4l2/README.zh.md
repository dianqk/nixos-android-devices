# V4L2 VA-API 后端

[English](README.md)

导入设备模块后启用共享模块：

```nix
{
  androidDevices.video.vaapi.enable = true;
}
```

模块启用 NixOS 图形支持，并把驱动加入 `hardware.graphics.extraPackages`。默认
关闭，在 RAM recovery 中无效。它不选择桌面、播放器或 FFmpeg 变体。只替换后端时，
将 `androidDevices.video.vaapi.package` 设为自己的 derivation。使用原版
FFmpeg/mpv；需要 `vainfo` 时自行加入 `pkgs.libva-utils`。

NixOS 在 `/run/opengl-driver/lib/dri` 下暴露 `qcom_drv_video.so` 及其
`msm_drv_video.so` / 旧 `v4l2_drv_video.so` 别名。Libva 从 MSM DRM 设备发现它，
不需要全局 `LIBVA_DRIVER_NAME`。用户需要 DRM/render、video 和 system DMA-heap
访问；共享移动模块提供 system-heap udev 规则。

软件包固定 [qcom-va-driver 1.1.1](https://github.com/radxa-pkg/qcom-va-driver/tree/0980a1decf26d34c9aa71cd0a4a0d25703a7a17f)。
本地扩展保留 system-heap CPU 上传一致性、固定方向 GLES RGB→NV12 录制和 Venus
解码/编码兼容性。上游已提供 AV1 重建、YUV Vulkan VPP、采集内存预算和硬件测试
程序。GPU surface copy 和 Vulkan VPP 启用；可选专有 CDSP VPP 保持关闭。现有
RGB 基础转换保留 GLES 路径，YUV/HDR/overlay 使用上游 Vulkan。硬件能力随内核、
固件和板而异；安装后端或列出 profile 不等于硬件解码可用。Aurora 的历史结果和
限制见[硬件文档](../../docs/aurora/hardware.zh.md#可选-va-api-后端)。

可选 VA 模块在会话和 user manager 中设置 `GST_VA_ALL_DRIVERS=1` 供 GStreamer
发现。不强制全局 libva 驱动名或路径。在已运行 user manager 下启动的服务也应
在自己的 unit 中显式设置该变量。标准 NixOS 驱动发现使用 MSM 别名。

## MediaTek T880 后端

导入公开 T880 模块并启用 VA-API：

```nix
modules = [
  androidDevices.nixosModules.t880
  { androidDevices.video.vaapi.enable = true; }
];
```

T880 后端识别 `mtk-vcp-dec`，使用 Panthor render-node 发现别名，并要求 GLES 3
进行 tiled-frame 转换。它暴露 H.264/HEVC/VP9/AV1 解码和 H.264/HEVC 编码的
有界支持；AV1/VP9 编码和 10-bit 编码输入不受支持。硬件验收和剩余限制见
[T880 状态](../../docs/t880/status.zh.md)。

## 构建与限制

软件包在两种移动发起平台上使用目标原生图形依赖构建，以便复用二进制缓存；项目
编译仍使用选定的工具链。构建成功、`vainfo` 列出 profile 或软件帧比较不能证明
真实播放、色彩、长时热行为或每个编码参数。驱动日志和逐帧比较仍需在目标设备上
单独验证。
