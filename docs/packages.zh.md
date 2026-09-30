# 复用和覆盖软件包

[English](packages.md) · [配置指南](configuration.zh.md)

设备模块使用调用方的 Nixpkgs 包集合。`libssc` 等上游包直接通过 `pkgs.libssc`
使用；本项目只定义自己的包和设备适配。导入设备模块不要求额外应用 overlay。

## 选择服务软件包

通过模块的 package 选项替换单个服务实现：

```nix
{ pkgs, ... }:
{
  androidDevices.usb.signaller.package = pkgs.usb-signaller;
}
```

替代包必须提供配置所需的功能。本项目的 usb-signaller 包含系统集成和可选 ACM
补丁，没有这些补丁的上游包并不等价。其他入口包括
`androidDevices.camera.package`、
各设备 recovery 的 `screenPackage` 选项。

## 直接使用包集合

公共函数 `lib.mkPackageSet` 接受已有的 `pkgs`。通过构建环境选择编译器，同时保留
AArch64 原生系统包：

```nix
let
  environment = androidDevices.lib.mkBuildEnvironment {
    buildSystem = "x86_64-linux";
  };
  devicePackages = androidDevices.lib.mkPackageSet { inherit (environment) pkgs; };
  hostPackages = androidDevices.lib.mkPackageSet { pkgs = environment.buildPackages; };
in {
  usb-signaller = devicePackages.usb-signaller;
  mobile-device = hostPackages.mobile-device;
}
```

`environment.pkgs` 是 AArch64 原生集合；`environment.compilationPkgs` 根据
构建平台选择原生或 x86_64 到 AArch64 的交叉编译；`environment.buildPackages`
提供发起主机的工具。这里 `environment.pkgs.buildPackages` 仍是 AArch64，
主机工具应使用环境显式导出的 `buildPackages`。

`mkPackageSet` 也接受显式的 `compilationPkgs`，默认继承构建环境的选择；没有选择时
使用传入的 `pkgs`。项目编译包走编译器集合，固件、预编译程序、脚本和镜像组装走
注册表的 `packaging` 集合：构建和检查在发起主机执行，运行时引用仍使用目标原生
`pkgs`。显式的组装工具使用 `packaging.buildPackages`；不要将此集合覆盖到上游
Nixpkgs。普通上游包不变；交叉工具链及库依赖仍可能需要单独构建，其交叉产物
不会因此命中上游原生缓存。调用者显式传入完整交叉 `pkgs` 时仍保留该行为。
参见[构建要求](configuration.zh.md#构建平台与远程构建机)。

设备内核包可直接使用
`devicePackages.devices.<device>.kernel`，设备模块也将其作为默认值。
Sheng 默认使用固定版本 7.2.6，`kernel-mainline` 是它的别名；7.3-rc5 移植版仍以
`kernel-testing` 提供。Clover 默认使用 7.3，另有固定版本 7.2.3 的
`kernel-mainline` 回退包。要在单独的 Sheng 系统配置中测试 7.3，可显式选用：

```nix
# 放在 flake 的 modules 列表内，外层已定义 inputs：
({ lib, pkgs, ... }: {
  androidDevices.kernelPackage = lib.mkForce (
    inputs.androidDevices.lib.mkPackageSet { inherit pkgs; }
  ).devices.sheng.kernel-testing;
})
```

Clover 的 7.2.3 回退包为 `devices.clover.kernel-mainline`。Recovery 可在自己的
系统配置中独立选择内核。
包集合还提供 `mkKernel`、`mkUBoot`、
`mkAndroidBootImage`、`mkRootfsImage` 和 `mkRecoveryScreen` 等工厂函数。
flake 的 `packages` 只选择可构建的 derivation，不直接导出包含函数的整个 scope。

## 可选 overlay

`overlays.default` 将同一集合提供为 `pkgs.androidDevicePackages`。
构造 Nixpkgs 时应用它，再按需要覆盖 scope：

```nix
[
  androidDevices.overlays.default
  (final: prev: {
    androidDevicePackages = prev.androidDevicePackages.overrideScope (self: old: {
      usb-signaller = old.usb-signaller.overrideAttrs (attrs: {
        patches = (attrs.patches or [ ]) ++ [ ./my-usb-signaller.patch ];
      });
    });
  })
]
```

将此列表传入 `lib.mkSystem` 的 `overlays` 参数或自己导入的 Nixpkgs。
设备模块自动使用覆盖后的 scope。没有 overlay 时，模块从传入的 `pkgs`
实例化相同的包集合。

包定义及其依赖关系放在 `pkgs/`；NixOS 模块负责配置、服务顺序和运行策略。
包通过 `callPackage` 接收依赖，不另行导入 Nixpkgs。

各板包定义位于 `pkgs/asphalt`、`pkgs/polaris`、`pkgs/sheng` 和 `pkgs/clover`。
固件、ALSA UCM、无线服务适配、recovery 工具和 Sheng 可选服务均由同一 scope 提供。
recovery 工厂从模块接收存储标识和主机名参数，求值或服务启动时不会自动操作存储。

Sheng 的 `hardware.sheng.{thp,pen-status}` 选项提供 `package`。
指纹使用普通的 `services.fprintd.enable = true`；Sheng 模块默认将
`services.fprintd.package` 设为此包 scope 的 `devices.sheng.fprintd`，
它链接 `devices.sheng.libfprint`。需要替换时直接设置 `services.fprintd.package`，
不再提供重复的指纹 package 选项。设备模块只补充必要的 QTEE 服务、设备权限和
运行路径；PAM 由 NixOS 管理，login、greetd 和 keyring 策略由消费者自行配置。
底层 QTEE/TA 包可通过 scope override 替换。
`hardware.sheng.sensors` 提供 `fastrpcPackage`、`registryPackage`、
`qrtrPackage` 和 `devauthPackage`；Polaris radio 提供 `rmtfsPackage` 和
`tqftpservPackage`。固件等共享包可通过 scope override 替换，无需复制模块。

## 设备命名空间

`asphalt`、`polaris`、`sheng`、`clover` 是作为稳定标识的设备代号，
不是处理器名称或产物类型：

| 代号 | 设备 |
| --- | --- |
| `asphalt` | 联想 Y700 2023 |
| `polaris` | 小米 MIX 2S |
| `sheng` | 小米平板 6S Pro |
| `clover` | 小米平板 4 LTE（当前支持的变体） |

设备专用包使用 `devicePackages.devices.<代号>`，例如
`devices.asphalt.firmware`、`devices.sheng.thp`；`usb-signaller` 等通用包保留在顶层。
每台设备都是可独立 `overrideScope` 的包集合。在父集合内覆盖设备集合，
同组依赖也会使用替换后的包：

```nix
packages.overrideScope (self: old: {
  devices = old.devices // {
    sheng = old.devices.sheng.overrideScope (device: prev: {
      firmware = myShengFirmware;
    });
  };
})
```

示例产物采用相同的设备命名空间：

```sh
nix build .#devices.asphalt.system
nix build .#devices.asphalt.u-boot
nix build .#devices.polaris.recovery
nix build .#devices.polaris.minimal.system
```

flake 引用写作
`androidDevices.legacyPackages.${buildSystem}.devices.asphalt.u-boot`。
模块使用 `nixosModules.<代号>`；设备专属选项使用 `hardware.<代号>.*`，
共享能力使用 `androidDevices.*`。
根据 [Nix flake 输出规则](https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-flake-check.html)，
`packages.<system>.<name>` 必须直接是 derivation，嵌套设备产物放在 `legacyPackages`；
通用工具仍从 `packages` 导出，两者均可通过 `nix build .#<属性路径>` 构建。
