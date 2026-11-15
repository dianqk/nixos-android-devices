# Sheng first installation

[中文](first-install.zh.md)

Use the Rust daemon recovery on slot B; preserve A, super, calibration and independent recovery.
The recovery initrd contains no Python. Standard NixOS installation/update tools may use
Python from the target system inside chroot.

Starting from the original userdata layout, check and explicitly execute **destructive**
preparation below. Android keeps the userdata size you choose (32/64/128/256/512 GiB,
offered while Linux keeps at least 64 GiB; see
[recovery](../recovery.md#ab-devices-preparing-linux-storage)); Linux gets the rest as a
separate FAT ESP (1 GiB by default) and ext4 root. Android userdata is destroyed and
requires a separate factory reset. Already partitioned devices are refused by this
operation.

```sh
ssh RECOVERY_HOST 'recovery prepare-install --check'   # lists the offered sizes
ssh RECOVERY_HOST 'recovery prepare-install --android-userdata 64G --check'
ssh RECOVERY_HOST 'recovery prepare-install --android-userdata 64G --confirm-erase-userdata'
```

Use the [separate firmware procedure](../u-boot-install.md#build-and-flash-u-boot-independently)
if compatible U-Boot is missing. Then follow [first installation](../initial-install.md)
to import the system and install its EFI generation. Update installed systems with `recovery rebuild boot`
or host-side `mobile-device recovery deploy`. Existing root/ESP ordering and alignment
gaps remain supported; ordinary updates do not repartition.

To erase only an existing Linux root, check `recovery format-root --check`, then use
`--confirm`. This leaves Android and the ESP intact. The daemon operations have not
been hardware-validated on every device.
