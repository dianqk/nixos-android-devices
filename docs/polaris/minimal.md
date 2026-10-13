# Root TTY example

[中文](minimal.zh.md)

`examples/polaris/minimal.nix` is a separate installed U-Boot/EFI example.
It automatically logs root into the console, has no normal users or graphical
session, and omits Wi-Fi/Bluetooth/audio userspace. System service accounts
remain. The existing kernel and its USB peripheral drivers are unchanged.
Only display firmware is included.

usb-signaller starts NCM developer mode at boot. networkd supplies the USB host
with DHCP; the phone is `172.16.42.1`. NetworkManager is not needed. For your own system, use the [consumer configuration](../configuration.md) with
`hardware.polaris.radio.enable = false`, `hardware.polaris.audio.enable = false`,
and USB networking/SSH enabled. Choose your own credentials and configure a
unique USB serial. Recovery resolves the stock GPT partition names on the
built-in UFS and checks the filesystem labels; use a matching root label in
the installed and recovery configurations.
See [first installation](first-install.md).

This intentionally open lab example accepts **root SSH with an empty password**
at `172.16.42.1`, without distributing a personal key. SSH listens only on the
configured USB address and the firewall opens port 22 only on `usb0`. Anyone
connected to that USB management link has root access. Connect with
`ssh root@172.16.42.1`; if a client prompts for a password, submit an empty one.
The desktop example's key-only authentication is unchanged.

Available packages on both build platforms:

- `devices.polaris.minimal.system`: complete system closure.
- `devices.polaris.minimal.bootstrap-info`: matching recovery registration and manifest inputs.
- `devices.polaris.minimal.rootfs`: ext4 `system.img`, expanded on first boot.
- `devices.polaris.minimal.boot-files`: matching EFI files, not a FAT partition image.
- Existing `devices.polaris.u-boot` and `devices.polaris.recovery` provide firmware and RAM recovery.

Build the system and first-install metadata:

```sh
nix build .#devices.polaris.minimal.system -o result-system
nix build .#devices.polaris.minimal.bootstrap-info -o result-bootstrap-info
```

For a customized `nixosConfigurations.polaris-minimal`, update over USB with:

```sh
nixos-rebuild boot --flake .#polaris-minimal --target-host root@172.16.42.1
ssh root@172.16.42.1 systemctl reboot
```

The host builds and transfers missing store paths; the phone retains Nix and
`switch-to-configuration` to install standard EFI generations. The phone does
not include Nixpkgs source or local rebuild helpers. Recovery `install-initial`
uses the system and bootstrap-info, while `deploy` updates an existing system.
These recovery workflows do not consume the rootfs image or require a separate
ESP download. Retain RAM recovery for a failed boot or USB configuration.

## Customize after installation

A matched U-Boot + FAT ESP + minimal ext4 root is enough to boot this starting
system, once the required partitions have been prepared. Keep a recovery image
available separately. A small rootfs grows within userdata on first boot; FAT
should use the prepared full boot partition to leave room for future generations.

Users can then keep their configuration on the computer and build a new system
with added users, services or a desktop. Export it as a `nixosConfigurations`
entry and run the USB update commands above. Preserve the Polaris device module,
UEFI storage paths, root filesystem identity, and USB access in that configuration.
Ordinary configuration/kernel updates install generations without reflashing
the root filesystem or U-Boot. The computer must supply an appropriate native,
cross or remote builder for AArch64; the minimal phone is not a build workstation.

To enable radios/audio in your own configuration later, set the corresponding
`hardware.polaris.radio.enable` / `hardware.polaris.audio.enable` options to `true`,
provide radio identity data and configure the normal NixOS services. Generic
console/desktop policy stays in your own modules. No upstream example or internal
source file needs to be imported. Preserve your intended USB authentication policy
when moving away from this intentionally passwordless lab image.

Configuration regression check (no device writes):

```sh
nix eval --json --impure --expr 'import ./tests/polaris-minimal.nix { flake = builtins.getFlake (toString ./.); }'
```
