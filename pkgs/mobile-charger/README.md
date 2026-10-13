# Mobile charging display

`mobile-charger` runs in a dedicated RAM-only charging initramfs. It uses
the Linux VT/fbcon console, evdev,
and explicit power-supply providers supplied by the board configuration.

The centered interface sizes its bitmap console font from visible framebuffer
pixels and physical panel dimensions, fitting at least 40×32 cells. Invalid
physical metadata falls back to pixel geometry. Board configuration can override
physical dimensions or font width (height is twice the width). Polaris uses
24×48 pixels on its 1080×2160, 68×136 mm panel (45×45 cells); Asphalt retains
an explicit 32×64 font on its 1600×2560 panel (50×40 cells). It reuses and scales the kernel font without font
files or a rendering library; only changed character spans are written. It shows a
large battery percentage, state, and USB input voltage/current/power. Power
is calculated from input-side voltage and current; battery `power_now`, PD
contract limits, and nominal charger ratings are not displayed as input power.
Unknown readings use placeholders. Input current and calculated power require a
valid input voltage; in particular, a driver returning zero voltage/current at
Full does not imply zero consumption. Charging status/health can come from a
separate provider from battery capacity. The program never writes charge limits,
charging-enable controls, or battery bypass settings.

- Short power press toggles the framebuffer console output and backlight.
- A two-second hold requests an ordinary reboot to the firmware boot path.
- The screen automatically turns off after 20 seconds without interaction.
- A separate process monitors external power even during a display stall.
  Five seconds of confirmed removal powers off; restoring power cancels the
  pending shutdown. Startup zero readings remain unknown until either monitor
  has observed online power; this readiness latch is shared between processes.
- Missing supply state or essential display/input hardware for 30 seconds
  causes power-off. Startup keys already held are ignored until released.

Running the controller requires the exact kernel argument
`android_charger=1`; it is not intended as a desktop application. It assumes
the charging initramfs mounts no persistent filesystems and has a PID1
supervisor that powers off if the controller fails.

Build and generate a preview on the initiating host:

```sh
nix build .#mobile-charger-host
mkdir -p tmp/preview
result/bin/mobile-charger --preview tmp/preview/charger.txt charging
```

Append optional `COLUMNS ROWS` to preview a different grid, for example
`--preview tmp/preview/polaris.txt charging 45 45`.

Preview scenarios are `charging`, `full`, and `unknown`; their numbers are
illustrative. Text output uses the same cell layout as the device; `#` cells are solid white
blocks on the physical screen.

The native build runs controller/telemetry tests and real event-queue tests
for delayed short presses, long holds, and evdev synchronization loss.
Actual framebuffer panel power, firmware telemetry, restart, and unplug behavior
also require board-level hardware verification. Screen blanking does not
claim that system suspend or Android-equivalent charging policy is enabled.
