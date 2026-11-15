# 原生 boot-choice 工具

[English](README.md)

本目录包含 `boot-choice-native`、`boot-choice-efi` 和 KernelSU 模块共享的
Rust 主机/原生实现。它执行有界离线普通文件操作和受保护的只读状态；实时
install/reboot 只通过匹配的 boot-choice 产品和固件上下文暴露。

受支持基线、构建命令和安全限制见公开的 [boot-choice 指南](../../docs/boot-choice.zh.md)。
不要用 shell 写入把离线文件打包桥接到块设备。
