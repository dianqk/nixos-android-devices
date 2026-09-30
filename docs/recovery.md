# RAM recovery over USB

Recovery runs entirely in the systemd initrd. It exposes a physical ACM root
console and an NCM Ethernet interface with OpenSSH. It does not mount storage
at boot. Fastboot remains the Android
bootloader transport.

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

SSH server host keys are generated in RAM on each boot; this is separate from
client authentication. Use a separate known_hosts file from the installed
system. Accept the new host identity on a trusted USB connection; for stronger
verification, read `/run/mobile-recovery/ssh_host_ed25519_key.pub` through ACM
and verify its fingerprint before pinning it. Never embed a shared private key.
After each recovery reboot, refresh only this recovery host's saved identity.
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

## Mount, inspect and leave

Inside the device's recovery shell:

```sh
recovery mount-target                 # root at /mnt, FAT at /mnt/boot, read-only
recovery target-status
recovery enter                        # isolated chroot; no activation/services
exit
recovery unmount-target
```

Mounting validates the board, partition/filesystem identities and read-only
fsck. It never formats or updates the profile/boot files. Existing read-only
mounts are not silently made writable. Finish all sessions before unmounting.
Polaris resolves the unique stock GPT names on its built-in UFS by default;
an exact per-phone contract remains optional. Clover requires its storage
contract. Asphalt/Sheng require the prepared separate ext4 linux
and standard 1 GiB linux-boot ESP, while preserving slot A and Android super.

`recovery enter` uses a private mount namespace and temporary /run and /tmp;
it does not run NixOS activation or expose recovery's systemd socket inside
the target. It requires a complete installed EFI system and working target
Nix tools. Empty or broken roots need the first-install/repair flow.

## Offline update

```sh
recovery mount-target --rw
recovery enter
nixos-rebuild boot --store-path /nix/store/...-nixos-system-device-version
# Alternatively: nixos-rebuild boot --flake /path/to/config#device
# Or: nixos-rebuild boot --rollback
exit
recovery unmount-target
recovery reboot-system --confirm
```

`recovery rebuild boot ...` runs the same operation without an interactive
shell. Only boot is supported; switch/test would target the wrong running
system. The wrapper disables nixos-rebuild self-reexec so an offline rollback
needs no Nixpkgs checkout. `--store-path` uses the current nixos-rebuild-ng
prebuilt-system interface; verify support if using an older installed NixOS.
Build/copy on the host first when possible; the USB management link does not
provide Internet access by default. Direct `nixos-rebuild --target-host
RECOVERY_HOST` does not automatically target /mnt.

For incremental closure transfer, first mount --rw and explicitly start
`mobile-recovery-store.service`, then run `mobile-device recovery --target
RECOVERY_HOST copy SYSTEM`. It forwards the existing store/status Unix sockets
through SSH and preserves on-device progress. Copying is separate from profile
and EFI selection. Stop the service before unmounting; `unmount-target` does so.

A pending marker records interrupted offline rebuilds. Repair/retry before
rebooting; do not simply remove it. Root and FAT writes are not one atomic
transaction. Keep prior generations and avoid GC during updates. Ordinary
updates use the standard EFI installer and do not require rewriting U-Boot.
Formatting, EFI deployment, supported recovery-image installation and reboot
commands are available through SSH. All four boards provide the
[shared `install-initial` flow](initial-install.md) for a prepared empty root and
FAT boot partition. It installs EFI and matching U-Boot without automatic reboot.
