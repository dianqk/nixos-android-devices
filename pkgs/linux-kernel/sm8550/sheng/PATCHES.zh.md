# Sheng 内核

[English](PATCHES.md) · [Sheng 指南](../../../../docs/sheng/README.zh.md)

默认输出 `devices.sheng.kernel` 及其别名 `kernel-mainline` 使用固定版本的
[`ianchb/sm8550-mainline` Linux 7.2.6 源码](https://github.com/ianchb/sm8550-mainline/commit/42f3b40c702abbc37c3a04c95af008cd283aeaf3)
及原有两条本地补丁。此版本已在 Sheng 上通过 U-Boot/EFI 启动并连接 Wi-Fi；
源码提交和哈希见 [mainline.nix](mainline.nix)。`devices.sheng.kernel-testing`
保留 Nixpkgs Linux 7.3-rc5 的 [Sheng 补丁集](series.nix)。每个补丁标明来源提交和
本地 7.3 适配；[ORIGINS.md](patches/ORIGINS.md) 保留原作者、日期、完整提交说明和
trailer。7.3 已能启动，但目前在 Sheng 上加载 WCN7850 固件失败。两种内核均使用
`config.aarch64`，构建 `sm8550-xiaomi-sheng.dtb`。

在 x86_64 主机上，此输出使用 x86_64 构建平台、AArch64 目标平台。构建内核：

```sh
nix build .#devices.sheng.kernel --builders '' \
  --out-link tmp/systemd-artifacts/devices.sheng.kernel
nix build .#devices.sheng.kernel-mainline --builders '' \
  --out-link tmp/systemd-artifacts/devices.sheng.kernel-mainline
nix build .#devices.sheng.kernel-testing --builders '' \
  --out-link tmp/systemd-artifacts/devices.sheng.kernel-testing
```

7.3 补丁集包括当前配置需要的设备树、显示、输入、电池、音频、相机、Type-C、DP 和
WCN7850 及 FPC1553 指纹改动。指纹用户态需要 FPC1553 驱动和设备树节点。
7.3 已能启动，但替换 7.2.6 前仍需修复 Wi-Fi 并验证其余外设。

FPC1553 驱动有两处已知限制：prepare 先禁用再启用时不会重新启用已申请的 IRQ；
移除驱动时先释放资源、后移除 sysfs。两条路径尚未经 Sheng 实机验证。

内核补丁遵循上游 Linux GPL-2.0 条款及所改文件的许可证声明。
