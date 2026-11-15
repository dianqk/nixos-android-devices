# T880 Wi-Fi

[中文](wifi.zh.md) · [T880 guide](README.md)

The T880's Wi-Fi (MT6897 connsys with the MT6637 radio) runs on the MediaTek
connsys drivers, built out of tree for the device kernel
(`devices.t880.connectivity-modules`): conninfra, connfem, wmt_chrdev_wifi and
the gen4m Wi-Fi driver. NetworkManager with the iwd backend manages `wlan0`.

## Configuration

`nixosModules.t880` enables `hardware.t880.connectivity` on installed systems.
At boot, the `t880-wifi` service:

1. loads the modules;
2. feeds the per-device calibration from the Android `nvdata` partition;
3. powers Wi-Fi on before NetworkManager and iwd start.

`nvdata` holds the `APCFG/APRDEB/WIFI` NVRAM record, including the MAC
address. The service sets the block device read-only and mounts it read-only.

The bootloader loads the Wi-Fi firmware itself from `connsys_wifi_<slot>`. The
drivers also read two stock configuration files from the Android vendor
partition (`/vendor/firmware`): `conninfra.cfg` and `connfem.cfg`. These files
are proprietary and are not shipped here. Provide them in one of two ways:

- **A firmware tree as a package.** Keep the stock Android 14 files laid out as
  `wifi/{SHA256SUMS,conninfra.cfg,connfem.cfg,...}` (and `bluetooth/...`). Pass
  that tree to the firmware package and allow that unfree package:

  ```nix
  hardware.t880.connectivity.firmwarePackage =
    androidPackages.devices.t880.firmware.override {
      # A directory with that layout, or a release archive:
      firmware-source = androidPackages.mkFirmwareArchive {
        name = "t880-firmware-source";
        url = "https://example.org/t880-firmware.tar.zst"; # root: wifi/, bluetooth/, SHA256SUMS
        hash = "sha256-…";
      };
    };
  ```

- **A directory on the device.** Copy the files to
  `hardware.t880.connectivity.firmwareDirectory` (default
  `/var/lib/android-devices/t880-firmware`). They are linked into `/lib/firmware`.

The service is skipped while no firmware is configured.

## Adding a connection

Credentials are not part of the configuration. To add a network at runtime:

```sh
nmcli device wifi connect <SSID> --ask
```

To keep the passphrase out of NetworkManager's profile, make the secret
agent-owned and supply it when you connect:

```sh
nmcli connection add type wifi ifname wlan0 con-name <name> ssid <SSID> \
  wifi-sec.key-mgmt wpa-psk wifi-sec.psk-flags 2
nmcli connection up <name> passwd-file <file>   # 802-11-wireless-security.psk:<passphrase>
```

iwd still writes the passphrase of every network it joins to `/var/lib/iwd`.
To keep it in RAM only, mount a tmpfs at `/var/lib/iwd`.

For SSH over Wi-Fi, let sshd listen on all addresses and open port 22 on
`wlan0`:

```nix
services.openssh.listenAddresses = lib.mkForce [ ];
networking.firewall.interfaces.wlan0.allowedTCPPorts = [ 22 ];
```

## Status and limits

- Station mode was verified on 5 GHz 802.11ax (2x2, 1201 Mbit/s link rate).
  Calibration runs once per boot, before Wi-Fi first powers on.
- The regulatory domain is the default world domain. TX power comes from the
  device's NVRAM.
- Without Bluetooth, pre-calibration runs for Wi-Fi only
  (`conninfra.t880_precal_wait_bt=0`).

## Bluetooth (experimental)

`hardware.t880.connectivity.bluetooth.enable = true;` adds the MediaTek
`bt_drv` driver.
- The controller registers with the kernel Bluetooth stack, so enable BlueZ
  with `hardware.bluetooth.enable`.
- Its address comes from the device's nvdata (`APCFG/APRDEB/BT_Addr`) at
  boot and is never stored in the configuration.
- Bluetooth registers before Wi-Fi powers on, so the stock Bluetooth and
  Wi-Fi pre-calibration runs. The firmware package must include the
  `bluetooth/` files (`BT_FW.cfg`).

The controller uses firmware-owned idle sleep and wakes for HCI traffic.
Turning it off in BlueZ powers the Bluetooth hardware off; turning it on
reopens it while Wi-Fi remains available.
Remove any custom `t880_no_sleep` modprobe setting when updating; the parameter
is no longer provided.

Tested: LE/BR scanning, repeated power cycles in BlueZ, L2CAP data (about
260 kB/s, l2ping 7-15 ms) with Wi-Fi running at the same time.

## Troubleshooting

- `journalctl -u t880-wifi` shows the bring-up. "missing ..." means a firmware
  file is not where the configuration expects it.
- `dmesg | grep -E "WIFI|wlan|conninfra"` shows the driver side. The drivers
  log only errors by default.
- The modules cannot be reloaded cleanly while running. Reboot after changing
  them.
