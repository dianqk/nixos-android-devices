# Sheng first installation

[中文](first-install.zh.md)

Use the Rust daemon recovery on slot B; preserve A, super, calibration and independent recovery.
The recovery initrd contains no Python. Standard NixOS installation/update tools may use
Python from the target system inside chroot.

Starting from the original userdata layout, check and explicitly execute **destructive**
preparation below. Android and Linux each receive approximately half of the original
userdata allocation; the Linux half contains a separate FAT ESP (1 GiB by default) and
ext4 root. Android userdata is destroyed and requires a separate factory reset.
Already partitioned devices are refused by this operation.

```sh
ssh RECOVERY_HOST 'recovery prepare-install --check'
ssh RECOVERY_HOST 'recovery prepare-install --confirm-erase-userdata'
```

Then follow [first installation](../initial-install.md) to import the system, install EFI
and write matching U-Boot last. Update installed systems with `recovery rebuild boot`
or host-side `mobile-device recovery deploy`. Existing root/ESP ordering and alignment
gaps remain supported; ordinary updates do not repartition.

To erase only an existing Linux root, check `recovery format-root --check`, then use
`--confirm`. This leaves Android and the ESP intact. The daemon operations have not
been hardware-validated on every device.
