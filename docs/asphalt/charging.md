# Y700 2023: off-mode charging

[Device guide](README.md) · [中文](charging.zh.md)

The Asphalt module enables `androidDevices.charger.enable` by default. On a
cable-only boot, the ABL `androidboot.mode=charger` token selects
`EFI/android-devices/charger.efi` on the ESP. This dedicated Linux/initramfs runs
in RAM without mounting the system root or starting a desktop. An ordinary
power-key boot enters systemd-boot, including when USB is connected.

## Build and update

```sh
nix build .#devices.asphalt.charger --out-link result-charger
```

For a custom configuration, use the `charger` output from `lib.mkArtifacts`.
Initial boot files include the image; `nixos-rebuild boot` replaces it atomically
on the ESP. Install the boot files **before** updating U-Boot in `boot_b` through
the [installation workflow](../u-boot-install.md). Normal system updates do not
flash firmware. Preserve Android A, super and independent RAM recovery.

Disabling `androidDevices.charger.enable` stops building/updating the image; it
does not remove an installed image or change firmware dispatch. Change the
firmware policy before removing the file. A missing or returning charger payload
requests shutdown; if shutdown fails, the manual menu remains without automatic
NixOS startup. Both charging and normal EFI boot retain B-slot confirmation checks.

## Controls and readings

- Short power-key press: toggle the display; idle timeout is 20 seconds.
- Hold power for two seconds: reboot through the normal chain into systemd-boot.
- Confirmed loss of external power for five seconds: shut down. Restored power
  cancels shutdown; an independent monitor handles display stalls.

The portrait 1600×2560 VT interface shows battery percentage, a fill gauge,
charging status and USB input voltage/current/power. Display readings refresh
every five seconds while visible and immediately after waking. Power detection
continues every second and on events while the screen is off. Initial zero
readings remain unknown until online power is observed; unresolved startup
powers off after 30 seconds.

USB input power is voltage multiplied by current, not net battery charging power
or a negotiated maximum. Unavailable readings remain placeholders. No current,
voltage, bypass or input-suspend controls are written; zero battery current at
full charge does not establish stock bypass mode.

## Diagnostics and limits

Set `androidDevices.charger.diagnostics = true` for read-only kernel/controller
logs over USB ACM. It provides no shell or USB kernel console and defaults off.
See the [charging controller reference](../../pkgs/mobile-charger/README.md).

Cable entry, display controls, disconnection handling and return to NixOS have
been observed with a USB host attached. This does not establish compatibility
with every charger or hardware confirmation of a previously unconfirmed B slot.
Existing ADSP firmware handles charging; Android thermal-policy parity,
low-SOC fast charging and sustained power behavior remain unverified.
Display-off disables backlight and scanout; system suspend is not implemented.
Transient line corruption during normal Linux console takeover is a known issue
with no established cause.
