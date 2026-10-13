# 移动设备 initrd 依赖收集器

[English](README.md)

在锁定的 Nixpkgs `makeInitrdNGTool` 上应用小范围源码补丁。
共享 systemd-initrd 模块为 `makeInitrdNG` 选择构建主机原生工具，
不修改设备端 systemd 或动态库。

- 将 `.note.dlopen` 中的 SONAME 数组作为一组备选项，选择首个可用版本。
  这样不会同时要求 OpenSSL 3/4、两个 libbpf ABI 和多个 libcrypt ABI。依据：[UAPI.12](https://uapi-group.org/specifications/specs/elf_dlopen_metadata/)。
- 在 RUNPATH/RPATH 查找失败后，收集同目录中实际存在的依赖。
  当前交叉 GCC 的 libstdc++ 只在 RUNPATH 中记录 glibc，而 libgcc_s.so.1
  就位于旁边。这是收集器的补充查找，不会改变运行时动态链接器的搜索路径。
- DT_NEEDED 仍逐项处理；真正缺失的库仍报告警告。
  不创建把 `.so.4` 指向 `.so.3` 的错误兼容链接。

六项 Rust 回归测试覆盖备选版本、未满足依赖、同目录查找及 RUNPATH 优先级。
