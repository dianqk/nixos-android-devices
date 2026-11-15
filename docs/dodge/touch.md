# Dodge touch and display wake

[中文](touch.zh.md)

To keep touches from waking a blank display:

```nix
hardware.dodge.touch.wakeDisplay = false;
```

The default is `true`. With `false`, the touchscreen follows its DRM panel,
releases active contacts and enters controller deep sleep with the interrupt
masked while the panel is off. Panel wake restores normal sensing before
reports resume. Keyboard, mouse and power-key handling are unchanged.

Read `/sys/bus/platform/devices/synaptics_tcm_hbp.0/panel_state` to inspect panel
following, controller sleep, interrupt state, transition counts and the last
command error. This setting controls display wake; it does not enable system
suspend or touch gestures during suspend.
