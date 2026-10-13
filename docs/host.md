# Android/NixOS development host

[中文](host.zh.md)

Import the standalone host module on the computer connected to the phone or
tablet. It does not import a device module or select a kernel, bootloader, user,
SSH key or network backend.

```nix
{
  imports = [ inputs.androidDevices.nixosModules.host ];
  androidDevices.host = {
    enable = true;
    users = [ "developer" ]; # An existing local user; new groups need a new login.
    adb.extraDeviceIds = [ "18d1:d00d" ]; # Explicit USB permissions for this setup.
  };
}
```

## Tools

| Area | Included tools |
| --- | --- |
| Connection and deployment | `adb`, `fastboot`, existing `mobile-device`, OpenSSH, rsync, picocom |
| DTB and inspection | dtc/fdtget/fdtput, file, jq, Python 3, strace, lsof, lsusb |
| Images (`imageTools.enable`) | U-Boot tools, binutils, GPT/partition/filesystem tools, cpio and common compression tools |
| Network checks (`networkTools.enable`) | iperf3, ethtool, tcpdump |

Android boot/AVB and sparse-image tools (`avbtool`, `mkbootimg`,
`unpack_bootimg`, `lpunpack`, `simg2img`) come with `android-tools`.
The image/network groups default to enabled; set either to false for a smaller
host installation. `extraPackages` extends the toolset. These are native host
packages, including on x86-64 workstations debugging AArch64 devices. Python is
installed on the host; this module does not add it to recovery or the device.
Kernel compilation remains in `nix develop .#kernel`; see [development](development.md).
For the existing checked flashing/deployment workflow, see
[mobile-device](../pkgs/mobile-device/README.md). Installing tools performs no
flashing, erasure, partitioning or audio playback, and starts no test servers.

## ACM consoles and USB networking

Use `/dev/serial/by-id/` to select a console and open it explicitly with
`picocom --baud 115200 --flow n /dev/serial/by-id/<console>`. Opening a console
can interrupt a bootloader countdown; do not keep it open unintentionally.
`usb.consoleSerials` excludes only the listed USB serial strings from
ModemManager probing. Users listed above receive `dialout` and `adbusers` access.
Additional `adb.extraDeviceIds` are vendor:product pairs; they grant device
access to that group and local active-seat users. No world-writable rules are
installed. A USB product label is not proof of a device's identity.

For NCM management on a NetworkManager host:

```nix
{
  networking.networkmanager.enable = true;
  androidDevices.host.usb = {
    consoleSerials = [ "my-debug-device" ];
    networks.phone-usb = {
      mac = "02:00:00:00:00:01"; # Replace with the gadget's HOST-side MAC.
      uuid = "11111111-2222-3333-4444-555555555555"; # Choose a stable unique UUID.
      # address = "192.0.2.2/24"; # Optional host address; default uses gadget DHCP.
    };
  };
}
```

Match by MAC instead of a USB-port-dependent interface name. Profiles are local
management links: they never supply a default route or accept DNS/extra routes
from the gadget, and IPv6 is disabled on these profiles. Other USB docks and
Android tethering connections remain independent. Verify the host-side MAC in
the gadget configuration, keep host/device addresses distinct, and check
`ip route get <device-address>` before SSH or an iperf3 measurement. A stale
address routed over ordinary LAN is not a successful USB connection.

`adb.enable` and `usb.enable` default to the top-level `enable`, but may be
selected independently for connection-only hosts without installing the full
tool bundle. USB profiles require an already-enabled NetworkManager; this
module does not switch the host's network manager or open firewall ports.
SSH aliases, host keys, addresses, device inventories and credentials belong in
the consumer configuration.

## USB compatibility

Set `usb.disableAutosuspend = [ "vendor:product" ];` only for interfaces whose
power-management problems have been established. It adds a targeted udev
power/control rule, a TLP denylist without enabling TLP, and the kernel's `k`
(NO_LPM) USB quirk. The kernel command line takes effect after a host reboot.
The setting is empty by default and does not change all USB devices.

## Diagnosis workflow

Select the target explicitly with `adb -s <serial>` or `fastboot -s <serial>`;
inspect identity/slot before a write. Use `lsusb -t` and `ethtool <interface>`
for transport negotiation, `ip route get` to select the measurement path, and
`iperf3` in both directions. Start listeners only when needed and choose any
firewall access explicitly. `usbmon`/packet capture require the corresponding
host privileges; this module does not enable packet capture on login.

Collect device logs over SSH/ACM (`journalctl -b`, `dmesg`, failed system/user
units). GPU/video tests (`vulkaninfo`, `vainfo`, ffmpeg/mpv), input/rotation
checks and `bluetoothctl`/`btmon` run on the endpoint being tested. Installing
these on the workstation cannot validate the phone's drivers. Select them in
the device's system configuration; do not add large diagnostic stacks to RAM
recovery just to match the host. Keep OEM backups and runtime captures outside
package sources, and record the base firmware version alongside results.
