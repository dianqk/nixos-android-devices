# HIDRAW, native USB touch, disk images and UVC

These optional installed-system modes use the existing usb-signaller manager.
The startup default remains NCM with optional ACM. Modes are exclusive; switch
from a local terminal or LAN because switching disconnects USB data access.
ADB, keyboard/mouse emulation and a touch-control GUI are outside this feature.

## HIDRAW and native touch

Enable `androidDevices.usb.hidraw.enable` for active-seat HIDRAW ACLs and
`androidDevices.usb.signaller.hidTouch.enable` for the native touchscreen gadget.
Select `hid_touch_mode` through the existing D-Bus `set_mode` method.

`sudo usb-touch tap 16384 16384` presses/releases one contact. `usb-touch stream`
reads complete contact frames as JSON lines until EOF:

```json
{"contacts":[{"id":0,"x":1000,"y":2000},{"id":1,"x":6000,"y":7000}]}
{"contacts":[{"id":0,"x":2000,"y":3000}]}
{"contacts":[]}
```

IDs are 0–9; absolute X/Y coordinates are 0–32767, with a top-left origin.
Missing contacts are released at their last position. The same JSON-lines API
is available on `/run/usb-signaller/touch.sock`, a Unix stream socket returning
`{"ok":true}` or `{"ok":false,"error":"..."}` per request. Only one writer
session is admitted; disconnect and mode exit release all contacts. Permissions
follow the existing `controlGroup`, defaulting to root. Phone input events are
not captured or automatically forwarded; applications supply the frames.

## Optional mass storage

This mode is disabled by default. `usb-storage-image create PATH --size-mib 2048`
creates an independent FAT32 image without replacing existing files. Configure
`androidDevices.usb.signaller.massStorage = { enable = true; image = PATH;
readOnly = false; };` and select `mass_storage_mode`. Read-only is the default.

Only regular image files are accepted. Symlinks, block devices and local loop
attachments are rejected. The service holds an exclusive image lock until USB
unbind and closes the kernel backing file before releasing it. Do not mount or
modify the image locally while exported. Normal directory sharing still uses
MTP; no system partitions are exported or formatted.

## UVC

Enable `androidDevices.usb.signaller.uvc.enable` and select `uvc_mode`. The
default `uvc.source.type = "test"` outputs VGA 640×480 at 30 fps colour bars.
For capture, set `source = { type = "v4l2"; device = "/dev/v4l/by-id/..."; };`
or `{ type = "libcamera"; camera = "0"; };`, replacing identifiers as needed.
V4L2 must supply VGA30 YUYV. Libcamera supplies MJPEG, with software encoding
from YUV420 when necessary. Missing/unsupported sources fail explicitly;
there is no fallback to colour bars. A USB High-Speed link is required.
The feature does not repair camera sensor or ISP drivers.

Query D-Bus `get_status` for completion/errors: `set_mode` only queues a request.
Unexpected backend exit unbinds and cleans the gadget, preserving an error until
a new request or connection change. Readiness includes process identity; stale
files cannot imply health, and failed sources are not restarted in a loop.
Return to `developer_mode` to restore the management network.

## Checks

`usb-gadgets` exercises touch state/validation and real image creation/locking.
`usb-gadgets-vm` uses an isolated dummy_hcd to check touch enumeration, feature
reports, host evdev events, storage I/O/read-only policy and transition cleanup.
dummy_hcd has no isochronous endpoints; this does not validate USB video traffic.
The UVC package separately tests its actual colour-bar source and unsupported
formats. `unicorn-usb-kernel` compiles the selected AArch64 drivers.
Backend diagnostics are in
`journalctl -b -u 'usb-signaller*'`.
