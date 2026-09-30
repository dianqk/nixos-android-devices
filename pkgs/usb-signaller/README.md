# usb-signaller package

For configuration, connection and updates, see [USB networking](../../docs/usb-signaller.md).

## Local packaging changes

Upstream source: <https://codeberg.org/DylanVanAssche/usb-signaller/src/tag/v0.4.2>.
The package retains upstream source and adds a documented local patch for:

- stable USB serial/MAC/interface names supplied by the NixOS module;
- explicit controller/role-switch selection and ownership of only
  `usb-signaller-*` gadgets;
- configured mode advertisement, serialized transitions and failure reporting;
- initial `none` role handling and failed-start retry through systemd.

Executable paths are substituted with Nix store paths. Two upstream unit tests
use existing `/` and `.` instead of assuming `/sys` and `/home` exist inside the
build sandbox. Network configuration uses native networkd instead of upstream's
NetworkManager/unudhcpd helper scripts. The upstream unrestricted D-Bus policy is
replaced by query access for all users and mode changes for root.

Configfs reconfiguration still disconnects USB. The package does not promise
rollback to the old gadget after every failure or automatic recovery from a
failed kernel boot; retain standard generations and independent RAM recovery.
