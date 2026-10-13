# SSC 传感器与屏幕旋转

[English](sensors.md)

在已安装系统配置中启用对应设备的传感器支持：

```nix
hardware.asphalt.sensors.enable = true;
# Or: hardware.polaris.sensors.enable = true;
```

本页适用于 Asphalt 和 Polaris。Aurora 的传感器见
[Aurora 传感器](aurora/sensors.zh.md)；Sheng 可选的 `hardware.sheng.sensors`
服务列在 [Sheng 硬件](sheng/hardware.zh.md)中。

Polaris 和 Asphalt 的桌面示例启用传感器支持以便诊断，但保持 Niri 默认的屏幕方向，
不运行自动旋转客户端。Recovery 不启用传感器服务。使用 `lib.mkSystem` 时，传入
`nixpkgsConfig.allowUnfree = true`，或传入允许 `asphalt-sensors` 和
`polaris-sensors`（包括其 `-zstd` 固件变体）的谓词：这些包含有专有 OEM 数据。
普通 NixOS 配置改用 `nixpkgs.config.allowUnfreePredicate`。

可单独构建所选设备的数据，例如：

```sh
nix build .#devices.asphalt.sensors --out-link result-sensors
```

Polaris 将 `asphalt` 换成 `polaris`。内核/DTS 改动还需按正常设备流程更新
已安装系统和系统代启动文件。只在旧内核上启用用户态选项是不够的。

这两款设备通过 QRTR/QMI 使用 SLPI SSC，配合原生高通 `sdsprpcd sensorspd`、
libssc 和 iio-sensor-proxy，不需要内核 IIO 加速度计节点。固件声明相应传感器时，
proxy 提供加速度/方向、环境光、接近和指南针。libssc 的 CLI 还支持磁力计和
陀螺仪读数。未设置自动亮度或接近感应熄屏策略。

<a id="check-startup"></a>
## 检查启动

```sh
systemctl status android-ssc-sensors iio-sensor-proxy
journalctl -b -u android-ssc-sensors -u iio-sensor-proxy
ssccli --sensor accelerometer --timeout 10
ssccli --sensor light --timeout 10
ssccli --sensor proximity --timeout 10
ssccli --sensor compass --timeout 10
ssccli --sensor gyroscope --timeout 10
monitor-sensor --accel
```

proxy 以有限次数重试等待实际的加速度计样本。失败时检查 `/dev/fastrpc-sdsp`、
SLPI 固件加载、QRTR 发现和监听器日志。Polaris 使用现有的用户态 PD mapper；
Asphalt 使用 SM8450 的内核 mapper。不要再添加相互竞争的 locator 守护进程。
可选的 FastRPC PDR 订阅会确认传感器 PD 通知，但不实现 static PD 崩溃后的完整恢复。

监听器在自己的服务命名空间内映射 `/vendor/etc/sensors`、`/vendor/dsp`、
`/persist/sensors` 和 `/mnt/vendor/persist/sensors`。可写状态位于
`/var/lib/ssc-sensors`，包括 registry 父目录、版本标记和临时/缓存文件。
默认值只在首次启动时复制；后续系统代保留校准数据。更新后的默认值不会自动替换
已有状态。有意重新初始化前先保存该状态。

<a id="desktop-clients"></a>
## 桌面客户端

可执行程序导出为 `packages.<buildSystem>.sensor-rotate`。在合成器会话中运行，
并确保合成器 IPC 工具位于 `PATH` 中：

```sh
mobile-sensor-rotate --compositor sway --output DSI-1
mobile-sensor-rotate --compositor niri --output DSI-1
mobile-sensor-rotate --compositor hyprland --output DSI-1 \
  --touch-device 'nt36523n-capacitive-touchscreen'
```

Polaris 使用 Hyprland 时，`--touch-device 'synaptics-*'` 在恰好匹配一个设备时
选中内置 RMI 触摸屏。连接了其他 Synaptics 触摸设备时检查 `hyprctl devices -j`：
匹配不唯一会阻止旋转。客户端会映射并旋转该触摸屏，同时保留显示器几何。
Sway/Niri 用户应在合成器配置中将触摸屏绑定到 `DSI-1`。每个输出只运行一个旋转程序。

客户端会处理初始方向和方向变化、未定义读数、重复事件和角度方向。
`--offset 90` 增加逆时针方向的屏幕偏移。SSC 加速度事件已使用 Android 设备坐标系。
传感器模块为 libssc 打补丁以保留这些样本：SSC 属性 20 是安装位置元数据，
不是需要再次应用的变换。proxy 的 SSC 后端将设备坐标轴适配到其方向分类器；
Z 轴保持朝外，用于判断正面朝上/朝下。`androidDevices.sensors.mountMatrix`
的默认单位矩阵仅表示屏幕安装的剩余校正。不要重复 DSP 芯片坐标轴映射，也不要用
旋转客户端的偏移补偿错误的面板安装元数据。

Asphalt 的原生显示模式为竖屏 1600×2560，面板旋转为 0。使用合成器默认的输出变换
和旋转客户端默认的方向映射。Niri 将请求的旋转与 DRM 面板安装元数据组合；对描述
正确的硬件应保持这一行为。偏好的桌面方向属于会话策略，不属于 DTS。

<a id="validation-limits"></a>
## 验证范围

已验证 registry 生成、用户态打包、源码/配置检查以及驱动和 DTB 编译。尚未覆盖的
硬件项目包括长时间采样、四个屏幕方向、触摸对齐、冷启动和挂起/恢复。Android
property bridge 指令已省略，因为原生监听器无法加载仅适用于 Bionic 的库，且采集的
Asphalt registry 缺少这些可选的 property 文件。在缺少这些指令时，两份固件是否仍
请求 bridge，仍需运行时确认。在 Polaris 上，打包的固件和默认值已通过原生监听器
产生加速度计样本。四个屏幕方向、冷启动和挂起/恢复仍需在设备上验证。

参见 [libssc 文档](https://libssc.dylanvanassche.be/docs/)，以及
[Asphalt](../pkgs/asphalt/sensors/README.md) 和
[Polaris](../pkgs/polaris/sensors/README.md) 的数据来源说明。

<a id="updating-ssc-packages"></a>
### 更新 SSC 软件包

同时更新 FastRPC 包和传感器数据，然后重启，使 SLPI 重新初始化。较旧的 FastRPC
监听器或较旧的传感器数据与当前软件包混用，可能破坏监听器请求，或使固件 registry
解析器崩溃。监听器使用一致性 FastRPC 内存分配，并拒绝被截断或超长的传输帧。

传感器服务在启动前重排已有 registry JSON 的顺序，保留已存储的值和校准数据。
不要为应用此修复而删除状态目录。固件要求 `owner` 位于分组条目之前，并按
`type`、`ver`、`data` 的顺序排列，尽管 JSON 本身不要求对象键的顺序。
服务在 `/vendor/etc/sensors` 和 `/system/vendor/etc/sensors` 提供同一份只读配置：
即使已有 registry 文件存在，Polaris 固件仍读取后者。缺少该目录时，SSC 可能响应
QMI 请求，却既不提供 registry，也不提供加速度计传感器。
Polaris 还需要两个 FastRPC 会话，分别用于监听器的分配器和传输连接，导出的 SDSP
缓冲区从其共享内存池分配。同时更新内核和传感器模块，然后重启，使 SLPI 以修正后的
配置初始化。
旧版 libssc 可能将安装位置误解为安装矩阵，在保留非对角小数项的同时报告全零的
回退值。同时更新传感器模块的 libssc/proxy 组合；不要通过修改校准数据抵消该缺陷。
更新后验证四个物理屏幕方向和触摸。
