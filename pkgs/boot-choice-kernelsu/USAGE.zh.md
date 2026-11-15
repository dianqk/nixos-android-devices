# Dodge 同槽位启动选择（KernelSU 模块）

本模块安装静态 AArch64 `boot-choice` 所有者和匹配模板。它不安装 KernelSU，
不提供 Android boot image，也不替代 RAM recovery。受支持基线、安全限制和完整
流程见公开的 [boot-choice 指南](../../docs/boot-choice.zh.md)。

1. 保留可用的 Android、独立 RAM recovery 和回滚资产。
2. 先在受支持的当前 Android 内核中安装或 patch KernelSU。
3. 在 KernelSU Manager 中安装 `dodge-boot-choice-kernelsu.zip`。
4. 打开模块 WebUI 读取状态。只有确实要改变下一次启动目标时才使用明确的切换按钮。

有 Android system overlay 时：

```sh
su -c 'boot-choice status'
su -c 'boot-choice reboot nixos'
```

模块 action 只读状态。入口、刷新和启动都不会请求重启。主机验证不能证明硬件或
断电验收。
