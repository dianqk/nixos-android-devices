# Sheng first installation

Read the [U-Boot installation workflow](../u-boot-install.md) and [device configuration](README.md) first.

After preparing the partitions below, use the [shared first installer](../initial-install.md) to import the closure, install EFI and write matching U-Boot firmware.

Use a separate 1 GiB FAT linux-boot and ext4 linux. Operate on B only; preserve A and super. If Android userdata fills the original allocation, safely shrink its filesystem or prepare to recreate it before reducing its GPT entry.

See the [Sheng manual storage example](manual-storage.md) for temporary recovery boot, ACM/NCM access and per-device GPT preparation commands. It also explains the scope of the checked `format-root` command.
