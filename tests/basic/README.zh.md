# 基础硬件测试

在有 Python 3 和 OpenSSH 的主机执行；示例系统需启用 root SSH 并已启动 Sway：

```sh
python3 tests/basic/run.py --ssh DEVICE_HOST --media tmp/basic-media --output tmp/basic-results
# Clover 或其他不支持 Vulkan 的设备：
python3 tests/basic/run.py --ssh DEVICE_HOST --media tmp/basic-media --output tmp/basic-results-no-vulkan --skip vulkan
```

需要指定 SSH 配置时，使用已验证的主机密钥：

```sh
python3 tests/basic/run.py --ssh asphalt-wifi --ssh-config /path/to/ssh_config \
  --media tmp/basic-media --output tmp/basic-results-wifi --min-cameras 3
```

SSH 使用密钥认证并严格检查主机密钥，不自动接受新密钥。
SSH 配置可指定 Wi-Fi 地址、密钥和已验证的 known_hosts；所有测试和视频传输都使用该连接。

`--skip` 支持逗号分隔的多个项目，也可重复使用。每次使用新的主机结果目录。
结果为 PASS、FAIL、INCONCLUSIVE 或 SKIP；日志和 `results.json` 保存在主机。
退出码：0 为所选项目通过，1 为失败，2 为扫描结果不确定。开机不自动运行。

| 项目 | 检测内容 |
| --- | --- |
| `display` | Sway 输出、分辨率、刷新率、缩放、旋转、DRM 接口／模式及背光信息。实体是否可见需另行截图和拍照确认。 |
| `wifi` | 一次实时 Wi-Fi 扫描，不连接。 |
| `bluetooth` | 扫描附近设备 15 秒，不配对、不连接。 |
| `audio` | 内核 ALSA 声卡和物理 PCM 设备节点，不播放、不录音；不验证实际声音或耳机插入。 |
| `camera` | 枚举 libcamera 相机，逐个获取相机并验证可用流配置和像素格式；不拍照，不验证画质。Polaris 使用 `--min-cameras 2`，Y700 2023 使用 `--min-cameras 3`。 |
| `h264`、`hevc` | FFmpeg V4L2 M2M 完整解码各 180 秒的 1080p、8-bit 无声视频，检查完整帧数，不允许回退软件解码。 |
| `opengl`、`vulkan` | 在 Wayland 中渲染小场景三秒，拒绝已知软件渲染器；分数不作为性能门槛。 |

扫描会临时开启关闭的接口／控制器，并在退出时恢复电源状态。
扫描不到附近设备标记为不确定。脚本不发起连接，也不更改已有连接。
日志可能包含附近设备标识；跳过不代表通过。视频通过 SSH 上传，测试结束后删除，
设备无需联网。

## 视频素材

在安装 Python 3、curl 和 FFmpeg 的主机准备一次：

```sh
python3 tests/basic/prepare-media.py tmp/basic-media
```

脚本按固定校验和下载免费 [H.264](https://test-videos.co.uk/bigbuckbunny/mp4-h264)
和 [H.265](https://test-videos.co.uk/bigbuckbunny/mp4-h265) 的
**Big Buck Bunny** 片段，© 2008 Blender Foundation，
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)。
每个十秒片段不重编码，循环封装为三分钟且不含音轨的视频
（H.264 60 fps；H.265 30 fps）。仅按需下载，不打包进镜像。
示例只安装必要 CLI 应用：iw、BlueZ、FFmpeg、libcamera（`cam`）、glmark2、vkmark 及已有系统工具。
Polaris 和 Asphalt 使用带各自设备补丁的 FFmpeg。
