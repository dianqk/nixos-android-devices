# Unicorn wired charging

The optional Xiaomi authentication service, independent Unicorn battmgr property
map and input telemetry collector are implemented. Host tests and an ARM64 driver
object build passed. Hardware authentication, charge pump operation, fallback and
the 120W peak remain unverified. Protocol success does not establish input power.

## Enable and collect evidence

Add this to the normal Unicorn system configuration:

```nix
services.xiaomi-mipps-auth.enable = true;
```

The default is disabled; recovery never runs the service. Existing ADSP firmware
and its thermal protections remain in control. The daemon handles a charger
already present at boot, cable changes, ADSP generations and lost authentication
flags. Failed attempts use bounded retry intervals. Ordinary PD and computer USB
connections receive no positive Xiaomi authentication result or data role swap.

On the stock kit, requesting the host data role exposed Xiaomi SVID `2717`,
adapter ID `a565`, and allowed one complete digest authentication. Enable this
discovery explicitly when connected to a known Xiaomi charger:

```nix
services.xiaomi-mipps-auth.allowDataRoleSwap = true;
```

For one attempt, stop the background service and run
`sudo unicorn-mipps-auth --allow-data-role-swap`. This option can interrupt USB
data and defaults off. It changes only the data role, never the power role; failed
discovery restores the previous device data role. A receipt from successful
digest verification avoids repeating the handshake on service restart for the
same partner/firmware session, while cleared firmware flags still require a new
handshake. Repeated gauge challenges on hardware have also returned the challenge
unchanged; those replies remain failures, never positive authentication evidence.

```sh
journalctl -u xiaomi-mipps-auth -b
sudo unicorn-mipps-auth --diagnose
sudo unicorn-mipps-auth --sample --duration 600 --interval 2 > unicorn-charging.csv
```

The last two commands are read-only. Install
`androidPackages.devices.unicorn.mipps-auth` separately to use them without the
service. CSV includes authentication, adapter capability, charge pumps, battery
SOC/temperature and USB voltage/current. `usb_input_watts` multiplies USB input
microvolts and microamps; it never substitutes battery power. Failed reads remain
`error:<errno>`. Firmware telemetry still needs an external meter that passes
Xiaomi negotiation through correctly.

Routine diagnostics mark unverified extended firmware nodes `not-probed`.
Use `--diagnose --extended` for investigation: an extended probe timed out on
hardware and can temporarily quarantine the shared authentication channel.
After a timeout, that snapshot skips further Xiaomi reads but still collects
standard USB/battery telemetry. Battery discovery prefers `qcom-battmgr-bat`.
Low input power at 100% SOC cannot establish peak charging capability.

## ABI and policy

The sources are Xiaomi's [stock driver](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/blob/fa4513e61931e11a59e3f177ae590d4e090d7229/drivers/power/supply/qti_battery_charger.c)
and [Unicorn configuration](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/blob/fa4513e61931e11a59e3f177ae590d4e090d7229/arch/arm64/configs/vendor/unicorn_GKI.config).

- USB type comes from `USB_ADAP_TYPE=7`. Xiaomi GET/SET use `0x50/0x51` with
  Unicorn property IDs, independently of sheng.
- Scalar requests/replies are 24 bytes; VDM frames are 32 bytes. Battery digest
  frames are 52 bytes, including a 32-byte digest, master gauge flag 0 and three
  zero padding bytes. Digest bytes remain unchanged; VDM words follow the stock
  per-word byte conversion.
- Stock enables `CONFIG_BQ_FUEL_GAUGE`, without `CONFIG_BQ_FG_2S`. This profile
  authenticates one master gauge. It reuses the keys, HMAC and VDM implementation
  from the [pinned open source authenticator](https://github.com/ianchb/xiaomi-mipps-auth/blob/9176efbdf276b874fc0a97912a914449a88155fb/xiaomi-mipps-auth).
  New sessions receive fresh challenges. Positive results require matching
  digests. An incompatible battery or adapter remains unauthenticated.
- Stock `FB_BLANK_STATE=0x57` means screen on=0, off=1. The daemon reads the
  internal DSI connector's actual DRM `dpms` state every two seconds, including
  during authentication. Unknown or ambiguous state is treated as screen on.
  Brightness and lock status are not used as substitutes.
- The stock userspace/thermal policy accompanying `SPORT_MODE=0x5a` is not
  reproduced. The daemon writes 0; the kernel rejects 1. There is no acceleration
  enable option, thermal bypass, fake temperature or raw current-limit interface.
- The ABI has no transaction IDs. A timed-out Xiaomi channel is quarantined until
  its late response drains or PDR establishes a new firmware session. If firmware
  never responds, cable reconnection alone cannot clear quarantine; subsequent
  diagnostics report EAGAIN.
- Authentication requires exactly one identifiable Type-C partner and a Xiaomi
  SVID. Discovery stays pending by default. Only the explicit option above probes
  an unknown-SVID PD connection with a host data role request; ordinary USB and
  known non-Xiaomi SVIDs are excluded.

## Hardware acceptance: pending

Use the original 120W adapter and cable. Compare this system with stock on the
same handset, at similar low SOC, battery/ambient temperature and display state.
Leave protections enabled. Treat 120W as a short peak, with no sustained-power
requirement.

| Scenario | Required evidence |
| --- | --- |
| Stock kit attached before boot | Logs, `authentic`, `pd_verifed`, adapter ID/SVID/PDO/APDO |
| Stock kit, screen on/off | DRM dpms, `fb_blank_state`, `sport_mode=0`, pump status, both input currents, temperatures and CSV |
| Cable reconnect and normal ADSP restart | Reauthentication after partner/generation changes; no result from the old session |
| Ordinary PD and computer USB | Normal fallback charging/data; no authentication or data role swap |
| Gauge/adapter verification failure | No positive result; normal charging fallback; never force success flags on hardware |
| 120W peak | Passthrough meter voltage/current, sample rate, peak duration and raw recording |
| Stock OS comparison | Same kit and meter, comparable SOC/temperature/screen state and input power curve |

Report gauge verification, adapter verification, pump operation, firmware input
peak and external meter peak separately. Capability fields and UI charging icons
cannot establish actual power.

## Host checks

The `unicorn-charging` flake check applies the full Unicorn queue to the pinned
kernel and runs actual C message paths with ASan/UBSan plus Python authentication
and retry tests. The `unicorn` evaluation check covers the default-off option,
enabled daemon and recovery exclusion. Hardware acceptance is a separate step.
