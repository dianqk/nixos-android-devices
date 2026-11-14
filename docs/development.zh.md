# 构建与验证改动

[配置指南](configuration.zh.md) · [内核源码](../pkgs/linux-kernel/README.zh.md) · [English](development.md)

## just 命令入口

运行 `just` 查看 [justfile](../justfile) 命令。命令需要 Bash，为子进程启用
Nix 的 `nix-command` / `flakes`，保留其他设置及 `flake.lock`；`queue` 还需要
下文列出的补丁队列工具。

```sh
just devices
just artifacts unicorn          # 可用产物
just plan unicorn kernel        # 预览编译任务和下载
just drv unicorn kernel         # 只求值 derivation 路径
just build unicorn kernel       # result-unicorn-kernel
just build unicorn recovery     # result-unicorn-recovery
just build unicorn              # 默认构建 system
just log unicorn kernel         # 查看已有构建日志
just size result-unicorn-system # 已构建系统的闭包大小
just eval --all-systems          # 两种平台，只求值
just check-one public-api       # 单项主机检查
just dev                        # 内核开发 shell
just tools                      # Android、部署和内核工具
just queue --help
```

将 `unicorn` 和 `kernel` 换为目标设备与产物，也支持 `minimal.system` 等嵌套名。
输出链接为 `result-<device>-<artifact>`；末尾可追加 Nix 参数，例如
`just build unicorn kernel --max-jobs 1 --cores 8`。日志、闭包大小和工具命令
均可由 `just` 查看；`mobile` 原样转发参数给
[mobile-device](../pkgs/mobile-device/README.zh.md)。

## 构建迭代

保留锁定输入及需要的产物以复用缓存，只构建当前需要的产物；同一构建平台上的
system/recovery 复用设备内核，避免频繁 GC 清除后续构建需要的产物。
并行任务数（`--max-jobs`）与每任务线程数
（`--cores`）应共同调整，见 [Nix 并行度说明](https://nix.dev/manual/nix/stable/advanced-topics/cores-vs-jobs.html)。
单个内核可从 `--max-jobs 1 --cores 8` 开始，按内存和 CPU 余量调整；
不要把两项都设为 CPU 数，以免并发线程过多。
未命中缓存的 ARM 原生任务可交给 [ARM 远程构建机](https://nix.dev/manual/nix/stable/advanced-topics/distributed-builds.html)，
减少 QEMU 编译；原生与交叉编译的项目产物使用不同缓存。

内核迭代可使用 `just dev`、已准备的源码和 Nix 内核有效配置，为每台设备保留
独立输出目录：`make O=/absolute/build-dir CC='ccache clang' -j8 Image dtbs`，
通过 `ccache -s` 检查命中。普通 Nix 构建缓存完整产物，不保留增量对象文件；
进入开发 shell 不会为其启用 ccache。最终仍用正式产物构建验证仓库输入。

## 求值与测试

公开 API、平台、原生用户态、模块边界、直接启动和发布配置的求值检查已在两种构建
平台的 `checks` 中注册。`nix flake check` 还会运行仅在主机上执行的镜像/fastboot
和存储回归测试，从不连接设备。

构建镜像前先运行求值。它检查配置和 derivation 的构造，不代表硬件验证：

```sh
nix flake check --no-build --all-systems --option allow-import-from-derivation false
nix eval --impure --json --option allow-import-from-derivation false --expr '
  let f = builtins.getFlake ("git+file://" + toString ./.);
  in import (f.outPath + "/tests/public-api.nix") { flake = f; }
'
nix eval --impure --json --option allow-import-from-derivation false --expr '
  let f = builtins.getFlake ("git+file://" + toString ./.);
  in import (f.outPath + "/tests/eval-platforms.nix") { flake = f; }
'
```

[软件包集成指南](packages.zh.md)介绍共享 scope 和使用者覆盖。`package-scope`
检查（`tests/package-scope.nix`）覆盖主机/目标选择、scope 依赖、可选 overlay
和模块软件包替换。

[模块边界指南](modules.zh.md)说明设备策略应放在哪里，以及共享 NixOS 模块使用
哪些显式输入。

`public-api.nix` 测试独立的下游配置。平台测试集检查打包的示例、recovery、可选
硬件以及原生/交叉输出。`tests/` 中的 UEFI 和 USB 测试检查各自的配置约定。在内存
有限的电脑上，可从返回的属性集中选择 `.aarch64-linux` 或 `.x86_64-linux`，一次只
求值一个平台。完整 flake 检查时，将 `--all-systems` 分别替换为
`--system aarch64-linux` 和 `--system x86_64-linux`，分两次调用以限制求值内存。

进入 `nix develop .#kernel` 可获得原生内核工具，并已配置 `ARCH=arm64`、`LLVM=1`
和目标编译器前缀。内核使用 LLVM 23；其他软件包保留 Nixpkgs 的编译器。项目设备
编译使用 `environment.compilationPkgs`，发起主机工具使用
`environment.buildPackages`。软件包注册表的 `packaging` scope 为主机构建器提供
脚本和预编译程序所需的目标原生运行时引用。不要全局替换上游 `pkgs` 构建器：它们的
缓存身份必须保持不变。[构建要求](configuration.zh.md)介绍了未命中缓存的原生 ARM
任务如何回退到 QEMU。

`tests/native-userspace.nix` 将上游 derivation 身份与纯原生 Nixpkgs 对比，并检查
主机上的固件/脚本/镜像组装、目标脚本解释器、所选编译器平台，以及全部受支持设备
（包括实验性的 Aurora）的模块选择。

在目标设备上显式运行[基本硬件测试](../tests/basic/README.zh.md)和[主机测试](../tests/README.zh.md)。求值、实际编译、
启动以及物理输入/显示验证是彼此独立的结果；请测试你打算部署的配置。

实现参考：[U-Boot](../pkgs/u-boot/README.md)、
[USB 软件包改动](../pkgs/usb-signaller/README.md)，以及各设备固件来源：
[Asphalt](asphalt/README.zh.md)、
[Clover](clover/README.zh.md)、
[Polaris](polaris/README.zh.md)、
[Sheng](sheng/README.zh.md)、
[Aurora](aurora/firmware.zh.md)。

<a id="recovery-on-a-new-board"></a>
## 设备支持状态

每台设备在 `docs/<device>/status.toml` 中记录支持情况，为
[`docs/status/items.toml`](status/items.toml) 的每个项目给出一个状态：Works、
Partial、Broken、Untested，设备没有该硬件时写 N/A。说明同时写英文（`note`）和
中文（`note_zh`）；Partial 和 Broken 必须附简短说明。项目还可以记录最近一次真机
验证的日期 `verified = "YYYY-MM-DD"`（页面上显示为“（日期 验证。）”），以及
Geekbench 结果 `benchmark = "https://browser.geekbench.com/…"`（页面上显示为链接）。
修改后重新生成并检查页面：

```sh
tools/status-pages.py
tools/status-pages.py --check
```

生成器会拒绝缺失或未知的项目、未知状态或字段、只有一种语言的说明、没有说明的
Partial 或 Broken 项目，以及格式错误的 `verified` 日期或 `benchmark` URL；页面过期时
`status-pages` flake 检查失败。新增项目时先加入 `items.toml`，再加入每台设备的文件。

## 在新设备上启用 recovery

先打通内核/DTB 和 USB 控制器/PHY/设备角色支持，然后是 ACM shell
（`androidDevices.initrdUsb.enable = true;` 和
`androidDevices.initrdUsb.network.enable = false;`），之后再加入 NCM/SSH。两者都
需要可用的 USB 硬件；ACM 无法捕获其 gadget 建立之前的故障。同一模块也可在正常
启动的 initrd 中显式启用。`androidDevices.initrdUsb.roleSwitch` 复用板级角色切换
设置，可针对新控制器覆盖。在 switch-root 前，它会停止会话并移除其 gadget 功能，
让 stage 2 接管。正常系统应使用 usb-signaller/SSH。已安装系统默认使用 NCM，可另外
添加 ACM 登录控制台。

每块板子单独验证：求值、真实镜像构建、RAM 启动、ACM、NCM/DHCP/SSH、只读挂载、
离线系统代更新和重启。Polaris 的硬件验证不能代表其他设备的行为。

<a id="kernel-patch-queues"></a>
## 内核补丁队列

每台设备的内核由上游 Linux tag 加上 `pkgs/linux-kernel/` 下签入的有序补丁队列
组成。签入的队列是构建输入；`tools/kernel-queue.py` 负责在队列与 Git 分支之间
相互转换以便编辑。它需要 Git、Nix、Python 3、GNU patch 和 tar。

将上游发布标签获取到任意内核 Git 仓库：

```sh
git init linux
git -C linux remote add upstream https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
git -C linux fetch --depth=1 --no-tags upstream tag v7.3.4
git -C linux show v7.3.4
```

导入前，将标签身份与所选 Nix 源码核对。`v7.3.4` 标签对象为
`8310b43a724c54668eeaa6860234078a7886915a`，提交为
`7595a62d45ee1a2297eafa5f2ef5d0a45142d84d`；Nixpkgs 获取的 `linux-7.3.4.tar.xz`
SHA256 为 `sha256-sRtt+Clejpkf8EC3GqpJlKi1XKojtrCSkH8ZW1hA/R8=`。仅获取签名标签并不能确立
签名可信；有条件时用可信维护者的密钥验证。

将设备队列导入为分支 `android/<release>/<device>` 并验证：

```sh
python3 tools/kernel-queue.py import --repo ../linux --device aurora \
  --version 7.3.4 --base v7.3.4
python3 tools/kernel-queue.py verify --repo ../linux --device aurora \
  --version 7.3.4 --base v7.3.4
```

使用 `pkgs/linux-kernel/default.nix` 为该设备预期的发布版本；见
[内核状态](../pkgs/linux-kernel/README.zh.md)。该工具对 derivation 的有序队列求值，
每个补丁导入为一个提交，并独立重放队列以比较 Git 树。它会拒绝已存在的分支、不兼容
的基线，或预期版本不同的队列。邮件格式补丁保留作者、日期、说明和 trailer；纯 diff
则归属于执行导入的用户。导入清单位于 `.git/android-queues/`。导入失败时，先检查
不完整的分支再删除；该工具不会重置已有工作。

用普通 Git 编辑分支（例如 `git rebase -i v7.3.4`）。保留作者、上游链接和
review/sign-off trailer，并单独说明本地适配。然后导出到新目录：

```sh
python3 tools/kernel-queue.py export --repo ../linux --device aurora \
  --version 7.3.4 --base v7.3.4 --output ../export-aurora
```

审阅导出的补丁，将每个补丁复制到 `pkgs/linux-kernel/` 下其现有的共享或板级路径，
补丁顺序或成员变化时更新 Nix 补丁列表。不要把共享补丁复制到板级目录。再次运行
`verify`；结果必须与编辑后的分支一致。

用于增量树外构建时，`prepare --source-identity <nix-source-path>` 会创建独立的
`android-prepared/<release>/<device>` 分支，加入 Nixpkgs 的源码准备步骤。切勿将
准备提交导出到队列中。Git 树验证不会编译内核，也不能证明硬件行为；发布构建始终
通过 Nix 使用签入的队列。
