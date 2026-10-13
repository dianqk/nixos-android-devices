# RAM recovery over USB

[中文](recovery.zh.md)

Recovery runs entirely in the systemd initrd. It exposes a physical ACM root
console and an NCM Ethernet interface with OpenSSH. At startup, full recovery
may briefly mount the verified Linux root to load or create its own SSH identity;
it unmounts it before exposing the console and recovery tools. Fastboot remains
the Android bootloader transport.

## Configure and connect

```nix
androidDevices.recovery.enable = true;
```

Use the exported device module and a unique `androidDevices.usbSerial`.
`androidDevices.initrdUsb.address` defaults to `172.16.43.1/24` for Asphalt,
`.42.1` for Polaris, `.45.1` for Sheng and `.44.1` for Clover. Choose different
subnets for simultaneous devices. The Linux host needs cdc_ncm and DHCP on the
resulting Ethernet interface. Recovery offers DHCP without default route/DNS.

ACM and NCM are independent functions of one composite USB gadget, not competing
backends. Both are enabled by default. Use a serial terminal on
`/dev/serial/by-id/` at 115200/8N1 for a passwordless physical root console.
Set `androidDevices.initrdUsb.acm.enable = false` for NCM/SSH only, or
`androidDevices.initrdUsb.network.enable = false` for ACM only. Evaluation
checks built-in kernel support and rejects both functions disabled or a
competing initrd gadget/SSH server. Controller endpoint capacity and
host interoperability still require hardware validation.

SSH listens on the USB address, port 22, and allows root login with no password
or client key by default, just like the minimal example. Connect with
`ssh -p 22 root@172.16.42.1`. For a personal image requiring a client key:

```nix
androidDevices.initrdUsb = {
  ssh.requirePublicKey = true;
  authorizedKeys = [ "ssh-ed25519 YOUR_PUBLIC_KEY" ];
  acm.enable = false; # Optional: also remove the unauthenticated physical console.
};
```

Full recovery keeps its own Ed25519 SSH host key on the Linux root at
`/var/lib/mobile-recovery/ssh/ssh_host_ed25519_key`, separate from the installed
system's SSH identity and from client authorization. Existing keys are read
through a temporary read-only mount; a missing key is generated locally and
saved through a brief read-write mount. Private keys are root-owned, mode 0600,
and never included in an image, Nix store, or source repository.

This requires the configured internal partition, device-tree compatible,
controller, ext4 label and clean filesystem state to match. Missing partitions,
Android userdata, active/dirty filesystems, unsafe key paths and invalid keys
fall back to a new RAM-only identity. Recovery does not repair filesystems or
replace an existing bad key automatically. The preparation has a 15-second
service timeout and must not prevent SSH from starting. No target filesystem
remains mounted. Minimal recovery and normal early boot retain RAM-only keys.
To disable persistent identity in full recovery:

```nix
androidDevices.initrdUsb.ssh.hostKeyStorage.enable = false;
```

Read `/run/mobile-recovery/ssh-host-key-state` (`persistent` or `temporary`) and
`/run/mobile-recovery/ssh_host_ed25519_key.pub` through ACM to verify the identity.
The console also reports the state and fingerprint. Use a separate known_hosts
file from the installed system. Establish initial trust on a trusted USB
connection; retain strict host-key checking. Repeated recovery boots use the
same identity while the saved key remains accessible. After a temporary-key
boot, reformatting, or deleting the saved key, verify the new fingerprint before
updating only that recovery host's entry. Partitioning during a running recovery
session does not change its identity; persistence begins on a subsequent boot.
First installation preserves these two identity files if recovery was restarted
after formatting the Linux root. Other unexpected files still prevent initial
installation. A filesystem requiring journal recovery uses a temporary identity until repaired
explicitly. The public file is derived from the private key when loaded.

Define a host alias `RECOVERY_HOST` with the address, port 22, user root and
that known_hosts file. Establish trust with interactive SSH before running the
noninteractive CLI. Only custom key-authenticated images need IdentityFile.

```sh
ssh RECOVERY_HOST
mobile-device recovery --target RECOVERY_HOST status
mobile-device recovery --target RECOVERY_HOST shell
mobile-device recovery --target RECOVERY_HOST push ./file /tmp/file
mobile-device recovery --target RECOVERY_HOST pull /tmp/file ./download
mobile-device recovery --target RECOVERY_HOST exec journalctl -b --no-pager
```

Use `recovery --ssh-config FILE --target HOST` for a separate SSH config, or set
`target` and `ssh_config` in the optional device TOML. `serial` selects fastboot
only. SFTP and ordinary SSH TCP/Unix socket forwarding are also available.

## Recovery operations

Every device's full recovery uses the Rust daemon, screen and `recovery shell`
client. No Python is included in the recovery initrd. Standard NixOS tools
inside the target chroot use their own dependencies, including Python.

```sh
recovery capabilities
recovery status
recovery mount-target --rw
recovery rebuild boot --flake /etc/nixos#DEVICE
recovery generations
recovery select-generation 12 --confirm
recovery unmount-target
recovery deploy-check-boot
recovery reboot-system --confirm
```

Use your configured host name in place of `DEVICE`; generation selection is an
explicit alternative for rollback. All requested installation/update writes go
through the daemon, including
host-side `mobile-device recovery deploy`. Clients may disconnect and reconnect
with `recovery task TASK_ID`. Recovery has no unrestricted `recovery enter` or
project shell backend. The Rust shell accepts the commands shown without a
leading `recovery`.

For destructive first preparation, see [Asphalt](asphalt/first-install.md),
[Sheng](sheng/first-install.md), [Aurora](aurora/README.md),
[Polaris](polaris/first-install.md) or [Clover](clover/first-install.md).
Existing installations retain their root/ESP layout. See the [daemon reference](../pkgs/mobile-recovery-screen/daemon.md)
for transfer, cancellation and failure semantics. The daemon storage and
first-install operations have not been hardware-validated on every board.

### Store access after initial installation

The recovery daemon keeps a private umask for its own state. Installed `/nix`
and the store/profile parent directories must nevertheless be readable and
traversable by system service users. Initial install, deployment and generation
selection share this setup and verify execution as an unprivileged numeric UID.
A read-only boot check rejects inaccessible parents. To repair an older install,
mount it read-write and explicitly select its current generation again; this
reinstalls its EFI entry without changing the system or firmware. Private Nix
DB contents and other directories are not recursively chmodded.

### Filesystems after an interrupted boot

An unclean shutdown can leave the Linux ext4 journal or FAT ESP dirty. Normal
mount/deploy checks remain read-only. To repair explicitly from RAM recovery:

```sh
recovery repair-filesystems --check
recovery repair-filesystems --confirm
```

The daemon verifies the configured slot and storage roles, the existing partitions and filesystem identities, requires
unmounted storage, then runs ext4 journal recovery/preen and automatic FAT repair.
Only exit codes 0 (clean) and 1 (corrected) are accepted; other results stop the
operation for investigation. Both filesystems must pass a separate read-only
check afterward. It does not format partitions or touch Android userdata.

### Stale backup GPT after an OEM slot change

If a deployment refuses a GPT CRC or copy mismatch, preserve the metadata and
inspect the two copies before changing anything. A/B recovery provides an
explicit, narrowly scoped repair for the disk containing `linux`:

```sh
recovery repair-backup-gpt --check
recovery repair-backup-gpt --confirm
```

This requires RAM recovery, no mounted block filesystems, independently verified
active B, a valid primary GPT and matching primary/backup geometry. Differences
must be limited to paired A/B type GUID swaps or Qualcomm slot attribute bits;
partition locations, sizes, unique GUIDs and names must match. It does not repair
a damaged primary/header or choose between different layouts. Confirmation saves
both metadata copies in RAM, writes only the backup array/header at their existing
locations, and verifies both copies. Download the reported snapshot before reboot.
Normal installation/update operations remain strict and never repair implicitly.

## Single-slot devices: Clover and Polaris

Clover and Polaris have no A/B slots. Their physical `userdata` is the ext4
root and physical `system` the FAT `/boot`; the GPT is never changed. Recovery
finds each storage role (root, ESP, firmware, recovery, misc) as the unique GPT
name on the internal storage controller and checks the kernel geometry. Measured
values in `hardware.<device>.storageRoles` must also match:

```nix
hardware.polaris.storageRoles.root = {
  partuuid = "YOUR_USERDATA_PARTUUID";
  number = 21;          # GPT entry number
  offset = 1234567;     # start in 512-byte units (blkid PART_ENTRY_OFFSET)
  bytes = 115964116992;
};
```

Polaris works with GPT names alone. Clover refuses root, firmware, recovery and
misc operations until they are measured; its ESP is the unique `system` on the
eMMC within a plausible size range. The installed system carries the same roles,
and recovery refuses a system whose roles differ.

```sh
recovery format-root --check          # erases only the root role
recovery format-root --confirm
recovery prepare-boot --check         # formats FAT /boot if it is not already FAT
recovery prepare-boot --confirm
```

`prepare-boot` requires a formatted root that is empty or holds a store that
verifies, and leaves a pending marker until the first installation completes.
Polaris applies its UFS clock safe mode before every storage operation
(`recovery safe-ufs` applies it alone). `reboot-recovery` writes `boot-recovery`
to the misc BCB transactionally; `reboot-system` and `reboot-bootloader` clear
it. `prepare-install` and backup GPT repair are A/B-only.

Formatting, EFI deployment, supported recovery-image installation and reboot
commands are available through SSH. All supported boards provide the
[shared `install-initial` flow](initial-install.md) for a prepared empty root and
FAT boot partition. It installs EFI and matching U-Boot without automatic reboot.
