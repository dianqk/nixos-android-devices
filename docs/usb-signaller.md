# Connect over USB and update a system

[Configure a system](configuration.md) · [Installation paths](README.md)

## Enable the device connection

Installed systems default to USB NCM with U-Boot/UEFI.
Enable SSH and configure your public key:

```nix
{
  androidDevices.usbSerial = "my-phone-01";
  androidDevices.usb.ssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY"
  ];
}
```

The module supplies USB NCM, DHCP on the management link and SSH bound to the
USB IPv4 address. SSH uses keys by default; no demo password or user is added.
The device chooses the following default address. Override it with
`androidDevices.usb.signaller.address` if it overlaps a LAN/VPN or another connected unit.
Set unique USB serials as they determine the gadget MAC addresses.

| Device | Device IPv4 address |
| --- | --- |
| Asphalt | `172.16.43.1/24` |
| Polaris | `172.16.42.1/24` |
| Sheng | `172.16.45.1/24` |
| Clover | `172.16.44.1/24` |

U-Boot exposes an ACM console. RAM recovery independently provides
[ACM/NCM and OpenSSH](recovery.md). Installed systems use NCM, with an optional
ACM login console enabled explicitly by the examples. The normal boot initrd
does not enable USB management by default; usb-signaller starts in stage 2. Recovery configures its gadget directly in the initrd and
does not run usb-signaller. Optional early-boot ACM/NCM uses `initrdUsb` and
tears down its gadget before switch-root. The USB transport does not select
a boot method, prepare storage or install U-Boot.
`androidDevices.usb.ssh.enable` only configures USB access; for SSH on Wi-Fi or other
interfaces, use `services.openssh` directly and set its listen/authentication policy.

## Connect from the computer

Connect a data-capable USB cable. Configure the new Ethernet interface on the
computer with DHCP. For a NetworkManager computer:

```sh
nmcli device status
# Replace USB_INTERFACE with the new USB Ethernet interface.
nmcli device connect USB_INTERFACE
ip -4 address show dev USB_INTERFACE
ssh root@172.16.42.1
```

The computer should receive an address in the same subnet (normally `.2`). The
link supplies no default route, DNS or Internet forwarding, so the computer's
normal connection remains in use. The device does not need a desktop login;
NetworkManager may manage Wi-Fi separately from networkd's USB interface.

If SSH fails, inspect from a local console or another working connection:

```sh
ip -4 address show usb0
systemctl status usb-signaller sshd.socket
journalctl -b -u usb-signaller -u sshd -u systemd-networkd
```

No USB Ethernet interface usually indicates a cable, port or gadget/controller
problem. An address without SSH access points to credentials, DHCP/routing or
SSH configuration. RAM recovery remains the fallback when the installed system
cannot start. Asphalt and Polaris have hardware-validated NCM/SSH updates. Sheng has passed
installed B-slot U-Boot/EFI Linux, NCM/SSH and Wi-Fi with its 7.2.6 example. Asphalt's
connectors have different support, so consult its [hardware notes](asphalt/hardware.md).

## Optional ACM console

Set `androidDevices.usb.acm.enable = true;` to expose an ACM serial login
console alongside NCM in developer mode. It defaults to `false`; the public
USB examples enable it explicitly. The kernel must include `USB_CONFIGFS_ACM`.
Connect using the device's serial-number link under `/dev/serial/by-id/` on the
host. Linux runs the standard `serial-getty@ttyGS0` login service when the gadget
port appears. Your configured getty/login policy applies; the module does not
create a user, password, or root autologin. Public desktop examples retain their
explicit demo-user autologin policy.

ACM does not replace NCM or SSH, and boot does not wait for a host to open it.
It disappears in charging-only/host mode and returns with developer mode.
U-Boot's ACM is a separate console that ends at Linux handoff; the installed
system re-enumerates its own USB gadget. RAM recovery uses its independent
`androidDevices.initrdUsb.acm.enable` setting.

For SSH without socket activation, set `services.openssh.startWhenNeeded = false;`.
When changing USB or the only SSH listener, keep another established management
channel until a **new** connection succeeds. A successful activation command
alone does not establish that a replacement listener is reachable.

## Standard updates

Once the computer has an NCM address and SSH access, this is a normal NixOS
remote target. Assuming your flake exports `nixosConfigurations.phone`:

```sh
nixos-rebuild boot --flake .#phone --target-host root@172.16.42.1
ssh root@172.16.42.1 systemctl reboot
```

`switch` also works for immediate activation. Prefer `boot` followed by reboot
when updating the USB daemon, networking, SSH or their configuration: restarting
the transport during `switch` can disconnect the client. Keep Wi-Fi SSH available
when changing the management transport. Build with an appropriate native,
cross or remote builder for the target architecture.

The standard installer updates the store, system profile, EFI kernel/initrd/DTB
and generation entries on FAT `/boot`. Ordinary updates do not flash U-Boot or
recovery. Transfer completion and activation/boot success are separate checks.
An initrd emergency still uses local/U-Boot console or independent recovery;
this backend deliberately does not add networking to the normal initrd.

## Modes and peripherals

The supported modes are `developer_mode`, `charging_only`, and
`host_mode`. MTP, tethering and mass storage are not advertised because their
supporting services and policy are not configured here. USB role changes are
root-only; ordinary users may query the daemon over the system bus.

```sh
busctl call com.meego.usb_moded /com/meego/usb_moded com.meego.usb_moded get_modes
busctl call com.meego.usb_moded /com/meego/usb_moded com.meego.usb_moded mode_request
# These disconnect USB networking; issue them locally or through Wi-Fi SSH.
sudo busctl call com.meego.usb_moded /com/meego/usb_moded com.meego.usb_moded set_mode s host_mode
sudo busctl call com.meego.usb_moded /com/meego/usb_moded com.meego.usb_moded set_mode s developer_mode
```

| Attachment | Required behavior and remaining boundary |
| --- | --- |
| Computer | Device role + NCM provides DHCP and configured SSH. |
| Mouse/keyboard | A working host/VBUS path lets standard USB HID and the desktop input stack handle it. usb-signaller does not supply power or input drivers. |
| USB disk/card reader | Host/VBUS and USB Storage/UAS/SCSI expose block devices. Mounting and filesystem permissions are normal OS/desktop policy; this minimal Sway example has no automount UI. |
| Display/dock | USB-C DP needs real DP wiring, CC/PD, orientation/mux/PHY and DRM support, followed by compositor output policy. A data-role write alone cannot enable DP. DisplayLink is a separate USB graphics path. |

usb-signaller monitors Type-C events but this integration does not implement an
automatic host policy or a desktop mode-selection dialog. Automatic roles may
already be supplied by a fully wired kernel connector driver; incomplete ports
still require board-level CC/VBUS/role/mux work. Multi-connector arbitration is
not implemented. Driver configuration alone is not a physical peripheral test.


Package patches and upstream details are documented [with the package](../pkgs/usb-signaller/README.md).
