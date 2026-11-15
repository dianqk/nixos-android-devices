# GMU 驱动核心集成

[English](README.md)

Akhil P Oommen 的[五补丁系列](https://lore.kernel.org/r/20260513-gmu-sync-state-fix-v1-0-6e33e6aa9b4f@oss.qualcomm.com)
将 GMU 注册为 component driver。没有驱动绑定 GMU 节点时，fw_devlink 会让 GCC
和 GPUCC 的 `sync_state()` 在整个启动期间保持 pending，启动时打开的电源域因此
不会关闭。这里作为上游提案（RFT v1）携带，不声称已合并。导入时（2026-10-11）
没有更新版本，也不在 msm-next 或 linux-next；当前上游状态请查看链接线程。保留
原作者、日期、消息和 sign-off。补丁 1/3/5 的 review tag 和系列 test tag 来自
链接线程的回复；外部测试在 X1E80100 上完成。

该系列由带 A6xx/A7xx GMU 的板共享：Polaris（SDM845，A630）、Asphalt
（SM8475，A730）、Marble（SM7475，A730）、Sheng（SM8550，A740）和 Aurora
（SM8650，A750）。Clover 的 A5xx 没有 GMU。

补丁 1–4 无需修改即可应用。补丁 5 变基到 7.3-rc5 的 scoped `device_node`
清理、性能计数器新增和更新后的 sysprof 原型；对 7.3-rc6 仍原样应用。其 GMU
节点引用保持 scoped；加入旧的显式 `of_node_put()` 会重复释放。该系列不改变
GPU 工作点、GMU 固件或 fenced-write 超时阈值。绑定成功不代表 suspend 可靠，
也不能解决间歇性的 fenced-write 延迟。
