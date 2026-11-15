# Dodge 同槽位启动选择

[English](boot-choice.md)

Dodge 可以让 Android 和 NixOS 共用一个 Android 槽位，并在不切换 A/B 槽的情况下
选择下一次启动目标。这是实验性的主机验证功能，不是通用 Android ROM 安装器，也
不能替代独立 RAM recovery。

## 组件

- `boot-selector-builder`：受保护早期 selector 的主机构建器。
- `boot-choice-native`：静态 AArch64 Linux `boot-choice` 所有者 CLI。
- `boot-choice-template`：与基线无关的 Dodge 模板，含匹配的 U-Boot raw/ELF/config
  和 EFI helper。
- `boot-choice-efi`：NixOS 模块使用的 freestanding UEFI helper。
- `boot-choice-kernelsu`：自包含 KernelSU Manager ZIP。

从本检出构建：

```sh
nix build "git+file://$PWD#boot-selector-builder" --out-link result-builder
nix build "git+file://$PWD#boot-choice-native" --out-link result-native
nix build "git+file://$PWD#boot-choice-template" --out-link result-template
nix build "git+file://$PWD#boot-choice-kernelsu" --out-link result-kernelsu
```

KernelSU ZIP 为 `result-kernelsu/dodge-boot-choice-kernelsu.zip`。模块包含原生
所有者、模板、匹配固件/helper 和哈希；不包含 Android boot image、APK、Python、
Nix 或编译器。

## 要求

- 保留可用的 Android、独立 RAM recovery 和回滚资产。
- 先在受支持的当前 Android 内核中安装或 patch KernelSU；本模块不安装 KernelSU。
- 已启动槽必须使用受支持的 kernel-only BOOT4：无 boot ramdisk/boot signature、
  未压缩 MZ ARM64 Image、有界 AVB 框架，原始内核占用不超过 48 MiB。其他布局会被
  拒绝。
- 当前 KernelSU 需要挂载型 metamodule（如 meta-overlayfs）才能让
  `system/bin/boot-choice` 出现在 Android PATH。Manager WebUI 和原生操作不依赖
  该 overlay。

## KernelSU 安装与使用

1. 将 ZIP 复制到 Android 并在 KernelSU Manager 中安装。标准安装器解压文件并运行
   `customize.sh`；不提供 recovery `META-INF` 安装器。
2. 模块将模板资产复制到 `/data/adb` 下的私有临时目录，并调用原生所有者一次。
   复制/保护失败会在写镜像前停止；已验证提交后的清理失败会如实报告，不会伪装成
   回滚。
3. 读取原生输出。`install TEMPLATE` 采用实际新鲜启动基线，或校验/更新已有镜像。
   变更镜像保留偏好并递增 sequence；相同内容是 no-op。
4. Manager 为下一次 Android 启动暂存更新。打开模块 WebUI 只读。明确的
   **切换到 NixOS / 切换到 Android** 按钮每次点击调用一次
   `boot-choice reboot TARGET`；忙时锁定，并显示原生错误，不自动重试。
5. 模块 `action.sh` 只读状态。入口、刷新、URL 参数和启动都不会选择目标或请求
   重置。

有 Android system overlay 时：

```sh
su -c 'boot-choice status'
su -c 'boot-choice reboot nixos'
```

没有 overlay 时直接使用模块的 `bin/boot-choice`。NixOS 中启用
`hardware.dodge.bootChoice.enable = true` 后：

```sh
sudo boot-choice status
sudo boot-choice reboot android
```

## 原生模板流程

运行时打包不需要 Python、Nix 或编译器：

```sh
result-native/bin/boot-choice image embed "$(realpath result-template)" \
  fresh-baseline.img embedded.img
result-native/bin/boot-choice image update "$(realpath result-template)" \
  previous-owned.img updated.img
result-native/bin/boot-choice image restore embedded.img original.img
```

输入输出是有界普通文件，绝不是块设备。输出创建独占、模式 0600、同步并回读；
已有输出不会被覆盖。文件打包不授予实时设备写权限；设备写入使用原生 live 命令。

## 安全限制

- 主机构建和测试不能证明硬件、EFI 运行时或断电验收。
- 在 OEM AVB/EFI 之前，整镜像写入不是断电原子的。保留原始镜像和独立 recovery。
- 早期音量键选择器只读，且只对本次启动生效。
- 持久偏好只来自明确的 CLI/WebUI 操作，不来自菜单浏览、启动参数或模块启动。
- `hardware.dodge.bootChoice.enable` 为显式启用，需要匹配固件、helper 和单独部署
  试验。

周边部署约定见 [Dodge 固件](dodge/firmware.zh.md)、[recovery](recovery.zh.md) 和
[启动动作](boot-actions.zh.md)。
