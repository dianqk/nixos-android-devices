# HIDRAW、原生 USB 触摸、虚拟 U 盘和摄像头

这些功能接入已安装系统的 usb-signaller。启动默认仍为 NCM／可选 ACM；一次选择
一个模式。模式切换会断开原 USB 数据连接，操作入口使用手机本地终端或 LAN。
本实现不包含 ADB、键鼠模拟或触屏控制界面。

## HIDRAW 与触摸

Unicorn 内核包含 `HIDRAW`。启用下面的选项后，本地活动用户通过 udev 的
`uaccess` ACL 访问 HID 外设；普通键鼠输入不依赖这些 raw 接口。

```nix
androidDevices.usb.hidraw.enable = true;
androidDevices.usb.signaller.hidTouch.enable = true;
```

原生触摸模式让电脑识别一个最多十点的 HID 触摸屏。它不自动读取或转发手机自己的
触摸事件。触点由命令行或本地程序提交，后续图形界面可复用同一接口。

```sh
sudo busctl call com.meego.usb_moded /com/meego/usb_moded com.meego.usb_moded set_mode s hid_touch_mode
sudo usb-touch tap 16384 16384
sudo usb-touch stream
```

`stream` 从标准输入逐行读取 JSON，输入结束时释放全部触点：

```json
{"contacts":[{"id":0,"x":1000,"y":2000},{"id":1,"x":6000,"y":7000}]}
{"contacts":[{"id":0,"x":2000,"y":3000}]}
{"contacts":[]}
```

每帧描述完整的活动触点集合，`id` 为 0–9，`x/y` 为 0–32767，原点在左上。
相同编号更新位置，消失的编号抬起；不要用鼠标相对位移解释这些坐标。
程序接口为 `/run/usb-signaller/touch.sock` 上的 Unix stream socket，使用相同的
JSON-lines 格式，每个请求返回 `{"ok":true}` 或带 `error` 的失败响应。
同时只允许一个控制会话；客户端断开、模式退出时释放触点。
权限默认是 root，也可通过现有 `androidDevices.usb.signaller.controlGroup` 授权。

## 可选虚拟 U 盘

此功能默认关闭，不占用镜像空间。它把独立镜像呈现为电脑上的磁盘；日常共享
`USB-Share` 文件夹仍使用 MTP。创建镜像的工具拒绝覆盖已有文件。

```sh
sudo install -d -m 0700 /var/lib/usb
sudo usb-storage-image create /var/lib/usb/share.img --size-mib 2048
```

```nix
androidDevices.usb.signaller.massStorage = {
  enable = true;
  image = "/var/lib/usb/share.img";
  readOnly = false; # 默认为 true。
};
```

配置生效后选择 `mass_storage_mode`。只接受普通镜像文件，拒绝块设备、符号链接和
已绑定到本地 loop 设备的镜像。导出期间持有镜像锁，手机端不要挂载或修改镜像。
电脑弹出后可切回其他模式，再在手机端挂载镜像。不会导出系统磁盘或自动格式化文件。

## UVC 摄像头

```nix
androidDevices.usb.signaller.uvc = {
  enable = true;
  source.type = "test";
};
```

选择 `uvc_mode` 后输出 VGA 640×480、30 fps 测试彩条。也可显式设置视频源：

```nix
# 二选一；示例路径/编号应替换为实际视频源。
androidDevices.usb.signaller.uvc.source = {
  type = "v4l2";
  device = "/dev/v4l/by-id/your-capture-device";
};
# 或 { type = "libcamera"; camera = "0"; }
```

V4L2 视频源需要支持 VGA30 YUYV；libcamera 使用 MJPEG，必要时由 YUV420 软件编码。
源缺失或格式不匹配会报错，不自动改为彩条。UVC 模式需要 USB High-Speed 连接；
默认测试源不依赖内置相机。此功能不修复内置相机的识别或图像处理问题。

用 `get_status` 查询实际模式、忙碌状态和错误；`set_mode` 返回仅表示请求已排队。
后端异常退出时，管理器核对进程身份后解绑并清理，保留错误，等待新请求或连接变化；
不会仅凭残留的就绪文件报告正常，也不会反复重启失败的视频源。

```sh
busctl call com.meego.usb_moded /com/meego/usb_moded com.meego.usb_moded get_status
sudo busctl call com.meego.usb_moded /com/meego/usb_moded com.meego.usb_moded set_mode s developer_mode
```

## 自动化检查

`usb-gadgets` 检查触摸帧状态、输入校验、镜像创建和占用；`usb-gadgets-vm` 在隔离
NixOS VM 的 dummy_hcd 上检查触摸枚举、Feature Report、主机 evdev 事件、磁盘读写、
只读和模式清理。dummy_hcd 没有等时端点，不能证明 UVC 实际视频传输。
UVC 软件包另检查实际彩条供帧和格式拒绝；`unicorn-usb-kernel` 编译 ARM64 驱动。
后端具体失败原因可用 `journalctl -b -u 'usb-signaller*'` 查询。
