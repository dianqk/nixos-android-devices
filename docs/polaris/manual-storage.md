# Polaris: prepare storage manually in recovery

[中文](manual-storage.zh.md) · [First installation](first-install.md) · [USB recovery connection](../recovery.md)

This device has no A/B slots. **Keep the GPT unchanged**: physical `userdata` is ext4 `/`, and physical `system` is FAT32 `/boot`. These commands erase the existing contents of both partitions. Check the phone and the root label in your build first. The example uses the default labels `NIXOS` and `NIXOS_BOOT`.

On the host, temporarily boot a recovery image built for this phone. The first `mobile-device` invocation checks; the second boots it:

```sh
mkdir -p tmp/systemd-artifacts
nix build .#devices.polaris.recovery --out-link tmp/systemd-artifacts/devices.polaris.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.polaris.recovery
nix run .#mobile-device -- --serial FASTBOOT_SERIAL fastboot boot tmp/systemd-artifacts/devices.polaris.recovery --execute
```

ACM and NCM are both available. Open the phone's `/dev/serial/by-id/` port at 115200/8N1 for the ACM root console. After the host obtains an NCM DHCP address, connect to recovery at `172.16.42.1`. Recovery SSH host keys change at every boot; first configure a separate trusted `RECOVERY_HOST` alias as described in the [connection guide](../recovery.md#configure-and-connect).

```sh
ls -l /dev/serial/by-id/
picocom -b 115200 /dev/serial/by-id/CHOOSE_POLARIS_ACM
ssh root@172.16.42.1
ssh RECOVERY_HOST 'lsblk -b -o NAME,SIZE,TYPE,PARTLABEL,PARTUUID,FSTYPE,LABEL,UUID,MOUNTPOINTS'
```

Run the following in a **root shell inside recovery**, via either ACM or `ssh RECOVERY_HOST`. Confirm unique `system` and `userdata` partitions on the built-in UFS, with expected sizes and no mounts:

```sh
recovery status
ROOT=$(readlink -f /dev/disk/by-partlabel/userdata)
ESP=$(readlink -f /dev/disk/by-partlabel/system)
lsblk -b -o NAME,SIZE,TYPE,PARTLABEL,PARTUUID,FSTYPE,LABEL,MOUNTPOINTS "$ROOT" "$ESP"
blkid -p "$ROOT" "$ESP"
```

After checking, format the **existing partitions** without running `sfdisk`. If a custom storage contract fixes filesystem UUIDs, add the corresponding `mke2fs -U` / `mkfs.fat -i` parameters; the default example lets the formatters generate them.

```sh
mke2fs -F -t ext4 -m 0 -L NIXOS "$ROOT"
mkfs.fat -F 32 -n NIXOS_BOOT "$ESP"
sync
e2fsck -fn "$ROOT"
fsck.fat -n "$ESP"
blkid -p "$ROOT" "$ESP"
```

The targets, filesystem types and default labels match `recovery format-userdata --confirm` and `recovery prepare-boot --confirm`. **Raw manual commands are not equivalent to the checked workflow**: the tools also check board identity, built-in UFS, unique GPT names and filesystem state. If FAT already matches, `prepare-boot` checks it without reformatting. When reformatting is needed, it first verifies an existing complete store or a new empty root and writes an installation-pending marker. Formatting alone does not install the Nix closure, EFI files or U-Boot; use the [checked `install-initial` flow](first-install.md#install-from-ram-recovery) for the complete first installation.
