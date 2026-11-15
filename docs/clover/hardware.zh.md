# 硬件支持

[返回使用指南](README.zh.md) · [支持状态](status.zh.md) · [English](hardware.md)

## 硬件适配状态

“已配置”表示仓库包含适配代码，不代表已在设备上测试。

| 领域 | 适配内容 | 状态 |
| --- | --- | --- |
| 启动与存储 | SDM660 内核/设备树、Android boot/recovery、按原厂 GPT 名称识别的 eMMC 存储角色、`userdata` ext4 | 可用：ABL → U-Boot → systemd-boot → Linux 7.3，代际更新与回滚，经由同一 U-Boot（FIT ramdisk）从 `recovery` 启动 RAM recovery。ramdisk 超过 35 MiB 时 ABL 不会启动镜像，因此 recovery FIT 使用 LZMA 内核和 xz initrd |
| 显示与输入 | 8 英寸 LTE 面板、FT5406 触摸、recovery 按键 | 已配置 |
| GPU 与视频 | Adreno 固件和内核驱动 | 已配置；端到端使用未验证 |
| USB | 正常系统 NCM/SSH；recovery ACM+NCM/SSH；系统 ACM 可选 | 已配置，所选传输方式需在实机验证 |
| Wi-Fi、蓝牙、调制解调器 | WCN3990 和原厂分区固件加载器；逐机地址可选 | 已配置；设备身份信息需逐机提供 |
| 音频 | ADSP、ALSA UCM 与路由 | 已配置；扬声器路由未验证 |
| 相机与传感器 | 内核设备树支持 | 用户空间路径未验证 |
