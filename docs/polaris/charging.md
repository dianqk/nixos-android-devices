# Mi MIX 2S: off-mode charging

[Device guide](README.md) · [中文](charging.zh.md)

The Polaris module enables `androidDevices.charger.enable` by default. Build
`nix build .#devices.polaris.charger`, or use the `charger` output from
`lib.mkArtifacts configuration`. Install the normal boot files first: updates
atomically install `EFI/android-devices/charger.efi` on physical `system`, the
FAT ESP. Then update U-Boot in the non-A/B `boot` partition using the checked
[flashing workflow](../../pkgs/mobile-device/README.md#fastboot).
Keep the independent RAM recovery. Routine NixOS updates do not flash U-Boot.

Firmware dispatch matches the complete ABL `androidboot.mode=charger` token,
not USB connection state. Ordinary boots continue through systemd-boot. Missing
or returning charger payloads request shutdown, then remain in the manual menu
if shutdown fails. Disabling the image option does not remove an installed image
or firmware dispatch; change firmware policy before removing that file.

The dedicated kernel/initramfs runs entirely in RAM and mounts no persistent
filesystems. It reuses the [shared VT charging controller](../../pkgs/mobile-charger/README.md),
with PMI8998 power providers, power key, backlight and physical dimensions set
in the Polaris module. The 1080×2160, 68×136 mm panel uses 24×48 character cells:
large percentage, battery gauge, state and USB input voltage/current/power,
centered on black with white text. Short power presses toggle the display;
it turns off after 20 seconds. A two-second hold reboots to systemd-boot.
Five continuous seconds without external power requests shutdown; reconnection
cancels it. Visible telemetry updates every five seconds and pauses when dark;
supply safety remains active independently.

PMI8998 charges directly over SPMI; ADSP, CDSP, SLPI, MSS, WLAN, Bluetooth and IPA are disabled
only in the charging DT. The normal system retains its own device tree and
services. Capacity comes from `qcom-battery`; status/health and measured USB
input come from `pmi8998-charger`. The charger driver returns zero voltage and
current outside Charging, including Full: these are shown as unavailable,
not as zero input power. Battery net current and negotiated limits are not
substituted for input measurements.

The controller does not set charging current, voltage, bypass or input-suspend
policy. The existing mainline SMB2 driver retains its own defaults (including
1 A fast-charge battery current and USB-type input limits); this is not a claim
of stock Android fast-charge or thermal-policy parity. Display blanking does
not implement system suspend. Set `androidDevices.charger.diagnostics = true`
only for validation to expose read-only USB ACM logs, without a shell.

Validation: native controller/UI tests, both build-platform module evaluations
and shared U-Boot sandbox dispatch tests pass. Hardware checks confirm readable
text, short-press display toggling, automatic blanking, short unplug/reconnection
without reboot, sustained unplug shutdown, cable-only charging entry, and a long
press through systemd-boot into the Niri example. The installed production image
has USB diagnostics disabled. Connected-power shutdown supplies the ABL charger
token; ordinary software reboot does not.

Input voltage/current/power at a lower battery level still need hardware
validation: the tested near-full battery reports Full, where this driver does
not supply those measurements. A pre-existing WLED IRQ warning during display
initialization remains unresolved; successful blank/unblank tests do not verify
overvoltage fault handling. Cold power-key startup has not been tested separately
from the long-press reboot path.
