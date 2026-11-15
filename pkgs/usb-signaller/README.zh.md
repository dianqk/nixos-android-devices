# usb-signaller 软件包

[English](README.md)

配置、连接和更新见 [USB 网络](../../docs/usb-signaller.zh.md)。

## 本地打包改动

上游源码：<https://codeberg.org/DylanVanAssche/usb-signaller/src/tag/v0.4.2>。
软件包保留上游源码，并加入有文档的本地补丁：

- NixOS 模块提供稳定的 USB serial/MAC/接口名；
- 显式选择 controller/role-switch，并且只拥有 `usb-signaller-*` gadget；
- 配置模式广播、串行化转换和失败报告；
- gadget/角色切换前关闭 ACM console，开发者模式设置后异步重启；
- 可选保留外部管理的 Type-C data role；
- 初始 `none` 角色处理，以及通过 systemd 重试失败启动。

可执行路径替换为 Nix store 路径。两个上游单元测试改用现有 `/` 和 `.`，不再
假设构建沙箱中存在 `/sys` 和 `/home`。网络配置使用原生 networkd，而不是上游的
NetworkManager/unudhcpd 辅助脚本。上游不受限的 D-Bus 策略改为所有用户可查询、
仅 root 可改模式。

Configfs 重配置仍会断开 USB。软件包不承诺每次失败后回滚到旧 gadget，也不承诺
从失败的内核启动自动恢复；请保留标准代际和独立 RAM recovery。
