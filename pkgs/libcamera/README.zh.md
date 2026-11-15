# 适配传感器的 libcamera 运行时

[English](README.md)

`androidDevices.camera.package` 提供带现有移动传感器增益/属性补丁的 libcamera，
包含 GStreamer libcamera provider 和 `libcamerasrc`；消费者可将该包的
`lib/gstreamer-1.0` 目录加入自己的插件搜索路径。摄像头选择属于消费者；请使用
provider 标识和标准位置属性，不要依赖 video 节点编号。

与被补丁的 VA 驱动一样，这个上游运行时在两种移动发起平台上都按目标原生构建。
其上游 GStreamer 和其他库标识保持原生，可复用二进制缓存。项目应用和内核仍使用
各自选定的原生/交叉编译路径。这不改变系统 PipeWire 或 Snapshot 的库选择。

构建/发现成功不代表采集质量或校准。设备指南记录各传感器的硬件结果和剩余限制。

GPU 软件 ISP 还带有已合并的
[GLES 矩阵修复](https://gitlab.freedesktop.org/camera/libcamera/-/commit/1df5cbe722a839ce4e257093550fa8107c02cf8b)
以及实验性回移：
[居中裁剪](https://patchwork.libcamera.org/patch/28704/)、
[可见传感器测光](https://patchwork.libcamera.org/patch/28707/)及其
[几何测试](https://patchwork.libcamera.org/patch/28708/)。后一个 v5 系列在上游
被拒绝/未合并；这些是本地实验回移，不是上游发布保证。它们修正 GPU 输出被裁剪
或缩放时的传感器坐标统计窗口，包括匹配 360p/720p 宽高比。聚焦几何检查包含
packed-Bayer 边界情况，并在原生包构建时运行。它们不提供传感器噪声、颜色或镜头
校准。

本地 simple-pipeline 修复会在不信任缓存链路状态的情况下禁用竞争 media link。
没有它时，另一个进程（例如 `cam`）路由到共享 CAMSS receiver 的摄像头会阻止
PipeWire 切换到其他传感器，直到 WirePlumber 重启。
