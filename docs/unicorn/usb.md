# Unicorn USB2

[中文](usb.zh.md) · [Device guide](README.md)

Unicorn uses firmware-negotiated Type-C roles, a USB2 DWC3 controller and an
external PTN3222-compatible repeater. NCM is the default device mode, with an
optional ACM login console. MTP and internet sharing require explicit configuration.
MTP exports only the configured directories. See [USB mode configuration](../usb-signaller.md)
for options and switching commands, and [additional USB modes](usb-gadgets.md)
for HIDRAW, native multitouch, image-backed storage and UVC.

The USB manager serializes mode changes and follows firmware role negotiation.
`set_mode` queues a request; query `get_status` for the actual mode and errors.
`bound` reports gadget binding, while `enumerated` requires a configured UDC.
A failed transition cleans up its resources; disconnects and firmware restarts
invalidate the previous connection state. Host mode requests a data role only;
charging-only mode unbinds the gadget without changing the power role.

The `usb-modes`, `usb-manager` and `usb-tethering` checks cover configuration,
mode transitions and sharing policy. `unicorn-usb-kernel` checks kernel options,
driver objects and the DTB. Physical peripheral testing remains separate.

Host data role does not establish VBUS supply. Unpowered peripheral operation,
USB3, native DisplayPort and analogue Type-C audio remain unverified. Measure
VBUS voltage, current and loaded operation to establish power capability.
See [charging](charging.md) for authentication and power telemetry, and the
[Chinese hardware notes](usb.zh.md) for board provenance and implementation details.
