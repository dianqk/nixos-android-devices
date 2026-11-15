# 主机测试

[English](README.md)

这些测试在构建主机上运行，不连接手机。它们用脚本化的对端和固定装置检查启动镜像
格式、U-Boot 辅助程序、存储操作、固件归档和 Rust recovery 工具。硬件测试是独立
步骤，列在各设备指南中。

运行完整主机测试的 flake 检查：

```sh
nix flake check --no-build --system x86_64-linux
```

`host-tools` 和 `recovery-daemon` 检查会构建并运行 Python 与 Rust 单元测试。
内核驱动测试用 mock 编译选定的生产源码；传入 `--source /path/to/linux`，可选
`--cc clang`。这些测试不能证明真机上的固件行为、中断时序、电源切换或驱动核心
生命周期。
