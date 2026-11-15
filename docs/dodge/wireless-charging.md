# Wireless charging on Dodge

[中文](wireless-charging.zh.md)

The regular Dodge module now includes an automatic, constrained normal Qi/BPP
backend and a userspace voltage-care service. After installing and booting the
matching updated generation, attachment needs no diagnostic command or Android
warm initialization. Automatic charging after boot on an attached OAWV09 and
clean removal have now been observed. Cold replacement and the new automatic
ceiling/cooling holds still require hardware validation; earlier bounded
charging trials are distinguished below.

## Automatic charging and care policy

The board opts in with `qcom,automatic-bpp-charging` and the receiver's exact
40-byte `nuvolta,bpp-fod-parameters`. Linux requests normal input off before
checked board calibration, then requests a fixed 750mA input. It sends no
transmitter query, authentication, FCC, FV or voltage command. Firmware ACKs
confirm requests; the raw wireless GET8 response is not an applied-limit echo.

The kernel monitors fresh source, receiver and battery data about every second.
It requires normal BPP, direct path off, receiver output 4.5–6 V, no USB/CID/OTG,
healthy battery, 16–35 °C, plausible 3.0–4.4 V paired samples and at most 50 mV
imbalance. Restart after a veto requires 17–33 °C. Receiver output above 900 mA,
measured battery charging above 1.2 A, power faults or invalid telemetry remove
input. These are conservative limits for this support, not full stock JEITA.
Software polling and transport timeouts cannot guarantee an instantaneous
hardware cutoff.

At 4.35 V the kernel holds the battery while retaining wireless input for the
phone. It releases below 4.30 V after at least 30 seconds and three separated fresh
samples. At 4.40 V it removes input even with an owned battery hold. Measured
charging above 50 mA after a 5 second hold-settling grace also removes input. A
voltage hold does not report `Full`. Cooling behavior at the automatic ceiling
needs separate observation; receiver input availability does not establish it.

The opt-in `dodge-wireless-care.service` implements configurable lower care
ceilings without rebuilding the kernel. It is off by default:

```nix
hardware.dodge.wirelessCharging = {
  ceilingMicrovolts = 4350000;
  restartMicrovolts = 4300000;
};
```

Lower thresholds can be deployed as a normal userspace service change. Care
holds have a minimum 30 second duration, including an inherited hold after service
restart. An unreadable sample asserts a hold; stopping/crashing the service
leaves it asserted. `wirelessCharging.enable = true` enables this userspace
care service; the DT-enabled backend and kernel safety remain active either way.
SOC policy and charging to 100% are not implemented.

Stable files under `/sys/class/power_supply/qcom-battmgr-bat/` are:

- `wireless_care_hold`: root mode 0600, strict 0/1 requested care vote.
- `wireless_voltage_max`: fresh qualified maximum sample in µV; errors return no cached value.
- `wireless_charge_state`: input phase, three votes, ownership, pending/frozen state and error stage.

The `error` field can retain an earlier rejected qualification while `phase`
has returned to `ACTIVE`. Check current phase/ownership and measured battery
flow together rather than treating that historical value as a live failure.

Manual INHIBIT, CARE and kernel SAFETY are independent votes sharing one
physical battery permission acquired only from a confirmed 1. Manual `auto`
clears only MANUAL; CARE/SAFETY still prevent enabling. A foreign 0 is never
enabled. Temporary input vetoes retain requested manual/care intent. Clean
removal/replacement requalifies automatically. Suspend first removes input;
resume requalifies instead of blindly enabling it.

An ambiguous request or partial calibration quarantines operation rather than
retrying through a logical generation/reprobe. Calibration is checked again
in fresh snapshots to detect loss without a GPIO edge. An unresolved request
can prevent suspend. UNKNOWN is not a verified off state; investigate before
another trial. The development input trigger and GET05 query are disabled with
the automatic configuration.

## Verified behavior

Hardware validation on 2026-11-13 used an OPPO OAWV09 AIRVOOC 50W magnetic
charger, a magnetic case/ring and the pad's quiet/slow mode. The original
low-input problem also occurred in fast/default mode before that mode change.

| Capability | Result |
| --- | --- |
| Automatic startup on an attached pad | After boot, charging started without a diagnostic trigger; 31 samples over about 60 seconds remained active at 3.90–3.93W and +218–289mA battery current. |
| Pad removal | Input ownership cleared, with no unknown/frozen/pending battery state. Replacement was not observed before device access ended. |
| Userspace care service | The built normal policy script ran successfully against the live backend; natural ceiling/restart crossing remains untested. |
| Receiver detection and telemetry | Attachment, output availability, voltage and current are readable. |
| Basic Qi/BPP battery charging | A fixed 750mA input request produced about 3.9W receiver output and positive battery current. |
| Manual pause/resume while attached | `charge_behaviour` suppressed battery current to near zero; Auto restored charging without removing the phone. |
| Battery status reporting | Charging → Not charging → Charging followed measured flow; all 56 samples in the reporting trial matched current. |
| Earlier bounded request cleanup | In the earlier manual experiment, the 45-second deadline returned input to about 0.18W and restored Auto. Automatic input has no 45-second deadline. |

The earlier 750mA cycle measured 3.86–3.93W at the receiver and +179–266mA
battery current. A subsequent pause settled at −11 to +9mA. Receiver power is
not battery power: some powers the running phone. These are device telemetry,
not an external power-meter measurement. Permission readback, ONLINE and a
charging label alone do not establish actual charging.

## Unfinished support

| Capability | Remaining work |
| --- | --- |
| Cold/repeated attachment | Automatic boot on an attached OAWV09 and removal are verified; replacement/cold-receiver verification remains open. |
| Continuous charging | Persistent input is verified beyond the old 45-second limit; long sessions, actual guard crossings and broader pad coverage remain open. |
| Automatic 80% stop / 70% resume | Add policy over the verified manual control and measure actual cutoff/resume. |
| AIRVOOC/SVOOC or higher-power Qi | Linux authentication and protected fast-charge operation are not implemented or verified. |
| Remote fast/quiet/cooling-only pad modes | No verified software selector; battery pause is separate from the pad's mode. |
| Other Qi pads and complete charge cycles | Not yet validated by these OAWV09 trials. |

Higher-power, SOC and complete stock charging policy remain deferred. The observed 3.9W basic path is not a claim of
50W AIRVOOC, 10W Qi, a completed full-charge cycle or a deployed daily-use fix.
The existing normal boot generation also does not gain the development driver
until a matching system is deployed.

## First check after installation

Boot the matching updated generation, unplug USB and place Dodge on the pad.
Initial care reconciliation can hold the battery for about 30 seconds.

```sh
systemctl status dodge-wireless-care.service --no-pager
bat=/sys/class/power_supply/qcom-battmgr-bat
cat "$bat/wireless_charge_state"
cat "$bat/status" "$bat/current_now"
```

`ACTIVE` with `input_owned=1` and positive battery current confirms charging.
`BATTERY_HELD` is expected when a manual, care or safety vote inhibits the
battery; wireless input stays available. `INPUT_OFF_VETO` while off the pad or
with USB connected is expected. Voltage/temperature limits can also veto input.
Check removal and replacement, then confirm charging resumes automatically.

## Manual battery pause

Dodge exposes the guarded manual permission pause through
`/sys/class/power_supply/qcom-battmgr-bat/charge_behaviour`:

```sh
# Pause a supported normal wireless charging session.
echo inhibit-charge | sudo tee /sys/class/power_supply/qcom-battmgr-bat/charge_behaviour

# End that pause and restore the permission this session changed.
echo auto | sudo tee /sys/class/power_supply/qcom-battmgr-bat/charge_behaviour
```

With automatic mode, the stricter guards above apply. Manual acquisition requires a fresh attached BPP receiver with its direct path off,
receiver output between 4.5 and 6.0 V, no USB cable or OTG source, and a healthy
battery at 0–43 °C. The driver first requires the normal-path firmware permission
to be enabled, then disables it and verifies the result. Repeating a confirmed
pause revalidates it without repeating the disable command. This interface does
not control SVOOC or other direct charging paths, transmitter modes,
authentication, foreign-object detection or thermal protection settings.

`auto` without a driver-owned pause is a no-op. A permission already disabled
before acquisition belongs to another controller: acquisition fails and the
driver never enables it. With automatic mode, reading `charge_behaviour` reports an effective owned
battery hold from any of MANUAL, CARE or SAFETY; `wireless_charge_state` identifies
the reasons. Without automatic mode it reports the manual session. A foreign
disabled permission still reports `auto`, because Linux does not own it.
Battery status and current remain separate measurements.

Outside automatic mode the manual session ends when its source changes, USB is reported, the receiver
becomes unreadable, the device suspends, or the driver is removed. Cleanup can
restore an owned permission after detachment without requiring an I2C reply
from the receiver. Resume does not automatically start another pause. There is
no state-of-charge threshold automation. Automatic mode retains requested votes across temporary vetoes and suspend.

Every enable restoration requires fresh healthy battery and temperature
measurements and verified firmware readback. An unsafe runtime restoration
remains pending until conditions become safe. While restoration is unresolved,
reading the mode fails rather than reporting success. An owned pause whose
restoration cannot be verified prevents suspend.

An ambiguous request timeout retires the control channel for that firmware
service generation. Ownership is not transferred across a service restart,
and an unresolved session is not automatically restored through a new channel.
Driver removal and shutdown cannot wait indefinitely for safe conditions or a
lost service: they report explicitly if the original permission was **not**
restored. Ownership is lost on teardown; a later probe treats a remaining
disabled permission as foreign and never silently enables it. Repeated `auto`
writes cannot override this restriction.

The optional root-readable debugfs diagnostic
`/sys/kernel/debug/qcom-battmgr-dodge/normal_charge_enable` reports the live raw
normal-path gate (`0` or `1`). It is read-only and is not an aggregate charging
status or evidence that an inhibition belongs to this driver.

The same debugfs directory optionally provides root-readable
`normal_input_suspend`. Each read requests a fresh OEM gauge buffer and reports
its normal input suspend flag as `0` or `1`, independently of battery health
and the normal charging permission. Firmware replies with only the original
nine gauge fields remain supported; this diagnostic returns `ENODATA` when
the optional tenth field is absent. Malformed values and transport errors
return errors without reusing an earlier flag. This diagnostic has no setter
and does not establish why input is suspended or how much power is received.

`wireless_input_current_limit` in that debugfs directory is a root-readable,
read-only raw firmware response for the OEM wireless input limit property,
whose nominal units are microamps. It is not verified as an effective or
applied limit: firmware may return zero without reflecting a requested value.
It is separate from the USB input limit and does not measure receiver power
or establish the cause of low input. This raw diagnostic has no setter.

The root-readable, read-only `normal_charge_limits` diagnostic requests a fresh
pair of OEM battery properties. It reports `current_max_ua` from the nominal
FCC property and `voltage_max_raw` from the voltage-limit property. Both retain
the complete unsigned firmware value. The voltage response is intentionally
raw: the OEM setter uses millivolts multiplied by battery count, so this
diagnostic does not label it as microvolts. Firmware aggregation and effective
limit semantics remain unverified. Errors fail the read without publishing a
partial pair or reusing cached values. This interface has no setter.

## Explicit transmitter identification diagnostic

Automatic receiver operation remains passive. An optional root-only debugfs
interface can send one narrowly scoped vendor `GET_TX_ID` query in an attached
normal BPP session. It does not change pad mode, fan, authentication, charging
permission, output voltage, protection or power transfer policy. There is no
generic register/message writer and no startup or periodic query.

The directory is `/sys/kernel/debug/<i2c-device>/`, where `<i2c-device>` is the
receiver's parent device name, for example `8-0036`. `query_tx_id` is write-only
mode `0200` and accepts exactly `1` with an optional newline. `last_tx_id` is
read-only mode `0400`; reading it sends no command. Triggering is synchronous,
bounded by a two-second transaction deadline and fixed mailbox polling limits.
A busy Linux mutex rejects the trigger without consuming an attempt or writing
anything. Once an attempt starts, success or failure consumes that attachment's
attempt. No identical query is retried automatically.

The trigger requires fresh NU1669 identity, attached GPIO, BPP protocol `04`,
4.5–6.0 V output and both direct-path indications off. It sends exactly five
bytes `18 05 00 00 00`. It drains stale receive events, observes receive flag
BIT10 clear before execute, then requires a new BIT10 event and two consistent
six-byte replies beginning `5f 05`. Packet-send-success alone is insufficient.
Only BIT10 is acknowledged, through firmware object `28` with mask bytes
`00 04 00 00`; unrelated sticky bits are preserved. Newly observed fault bits,
lost unrelated evidence, malformed frames and ambiguous I2C/timeout outcomes
fail the attempt. Busy is never force-released.

The narrow acknowledgement interpretation follows the OEM mask interface and
still requires hardware verification. Firmware supplies no transaction ID, so
an already-attached first query can retain ambiguity with an earlier firmware
request. A physically observed detach and later reattach provides stronger
freshness evidence; boot, reprobe, suspend or a logical generation change alone
does not prove a receiver reset. A failed attempt remains quarantined until
that physical transition and successful fresh guards/event drain. An absence
that the driver did not observe cannot rearm the query.

The result reports `sequence`, captured `generation`, numeric `status`,
`physical_attach_verified`, `quarantined`, and initial/last raw event flags.
`reply` contains the six raw bytes only after successful reply acknowledgement
and while the attachment/generation remains current; otherwise it is
`unavailable`. These are vendor discovery bytes, not verification of an
OAWV09 model, authenticated identity, requested pad mode or charging effect.
After any failed attempt, inspect the diagnostic and preserve its evidence;
do not repeat the query to try to consume a late reply.

The same receiver debugfs directory provides root-readable `fod_shadow`
(mode `0400`). Each read samples existing INFO plus exactly `21a0..21ca`:
three command-shadow bytes followed by forty parameter-shadow bytes. It
reports `magcvr_shadow` from INFO offset `18`, `write_mode_shadow`,
`length_shadow`, `read_mode_shadow`, and `parameters_shadow`. These are raw
mailbox shadows, not confirmed active or applied FOD calibration, a live
magnetic-cover sensor reading, or proof that protection is enabled/disabled.
Even a table match, zero-filled block or unusual length does not establish
those semantics.

The diagnostic brackets two matching block reads with fresh identity,
presence and generation checks, rejecting torn, changed, suspended, stopped
or failed reads without cached/partial output. It sends no FOD read command,
write command, calibration, acknowledgement or transmitter query, and reads
no additional RAM ranges. Reading it does not clear query quarantine or
replace the physical detach/reattach requirement for another GET05 attempt.

## Checking battery and receiver status

```sh
bat=/sys/class/power_supply/qcom-battmgr-bat
for name in status current_now capacity temp charge_behaviour; do
  printf '%s=' "$name"; cat "$bat/$name"
done
rx=/sys/class/power_supply/nu1669-receiver
for name in present online voltage_now current_now; do
  printf 'receiver_%s=' "$name"; cat "$rx/$name"
done
```

Linux battery `current_now` is in microamps: positive flows into the battery,
negative flows out. Temperature is in tenths of a degree Celsius (`330` is
33°C), and capacity is percent. Receiver voltage/current are in microvolts and
microamps. Receiver PRESENT/ONLINE indicate attachment/output availability;
they do not establish battery charging. `charge_behaviour` describes Linux's
manual permission ownership, separately from actual status and current.

## Bounded normal input request experiment

For supervised development, `/sys/kernel/debug/qcom-battmgr-dodge/normal_input_probe`
is root write-only (`0200`). Exact `1` starts one fixed 750000µA wireless input
request; exact `0` requests cleanup, each with an optional newline. There is no
configurable current/duration, startup acquisition or resume acquisition. This
is a development test of normal BPP input and manual battery pause/resume,
not daily initialization or a charging fix. The 750mA cap and combined trial
require independent net-charging and pause/resume measurements. It
changes no BATT permission, FCC/FV, receiver, FOD, authentication or voltage
setting. The raw `wireless_input_current_limit` file remains read-only.

Start requires AUTO without a battery pause owner, fresh BATT permission1,
healthy temperature, stable normal BPP/direct-off receiver identity, no USB,
CID or OTG input, and AP OTG off. A valid start consumes the built-in driver's
boot-lifetime attempt before preflight I/O; later guard rejection still consumes
it. Busy local start locking, invalid input and modular builds issue no request.
Modular starts are disabled. Service restart, suspend and driver reprobe cannot
reset consumption. Reprobe also retains the boot-global possible-owner flag:
losing instance context never means an unknown firmware request disappeared.

The request owns possible state before SET750000, and accepts only a matched
opcode/property/result ACK. **GET8 is not a requested-limit readback:** the raw
diagnostic can remain zero while an input request changes receiver power.
Neither a zero response nor agreement with any request proves the original
or effective applied limit. Android's similarly named input-limit field comes
from GKI/MMS receiver-current telemetry and does not validate firmware GET8.
Receiver power and battery current must be measured independently during the
experiment and after cleanup.

A fixed absolute45-second software deadline is armed before SET. Periodic and
event-driven checks end the request on unhealthy/changed sources; generic WLS
notifications cause fresh validation rather than being called a detach.
Explicit `0`, deadline, suspend and teardown request SET0 cleanup without a
health or readable-receiver dependency. Successful cleanup reports only its
matched ACK. It does not claim original/effective restoration or return of
hardware power to baseline. The standard manual INHIBIT API is permitted only
while the same instance
owns a confirmed, healthy, unexpired input request with a successful start
ACK and matching service/receiver. UNKNOWN or orphaned input ownership remains
blocked. A gate already zero without a confirmed matching manual pause is
foreign and ends the input request; it is never silently enabled.

A confirmed manual pause can keep battery permission0 while the input request
remains active. AUTO restores only its owned battery permission1 and leaves a
valid input request active. Input expiry/cleanup still requests only SET0,
independently of a battery pause. The supervised trial must arrange separate
AUTO cleanup before the input deadline and inspect both ownership states.
Existing battery-session epoch invalidation is unchanged: notifications may
end a pause rather than being filtered to make the experiment succeed.

Ambiguous delivery, lost/malformed ACK or service-generation loss becomes
UNKNOWN. No identical retry or transfer to a new service is attempted: a late
SET750000 ACK cannot safely be used as evidence of SET0 cleanup. Suspend is
refused while cleanup remains unresolved; teardown reports UNKNOWN explicitly.
The watchdog is serialized software work, so scheduling delays or unavailable
firmware transport can prevent a timely cleanup request. It is not a guaranteed
physical cutoff. Do not repeat a failed trigger or treat a new boot as proof of
receiver reset or effective restoration.

Root-readable `normal_input_probe_status` (`0400`) reports phase, boot
consumption, possible/instance ownership, frozen state, stage, failure stage,
reason, error, start/cleanup ACK result, captured/current service generations,
receiver generation, deadline and remaining milliseconds. It also reports
`charge_owned`, `charge_pending`, `charge_frozen`, `charge_epoch` and
`charge_session_epoch` to diagnose the separate manual battery session.
ACK result0 means a
matched successful ACK; negative values mean an error or unavailable ACK,
not an effective limit measurement. `UNKNOWN_OWNER_UNAVAILABLE` preserves an
unresolved boot-global request after instance loss. Preserve that evidence
rather than attempting another request.

For a freshly qualified NU1669 BPP/direct-off 4.5–6V path without wired input,
Dodge battery `status` uses fresh gauge current: above +50000µA is `Charging`,
below −50000µA is `Discharging`, and the inclusive ±50000µA band is
`Not charging`. Only an explicit, freshly fetched firmware `Full` is retained
in that band; SOC alone never produces `Full`. Wired, absent or unqualified
receiver paths retain firmware status. Attached-provider, gauge and changing
source/service errors fail the read rather than showing cached status. The
validated gauge also refreshes `current_now`'s short cache for comparable
STATUS/current values in one uevent. This is reporting, not a charging setter;
policy inhibition and current settling need not be instantaneous.

Root-readable `normal_voltage_samples` (`0400`) in the battery-manager debugfs
directory requests one fresh existing OEM gauge reply and reports only
`word2_raw`, `word13_raw`, `declared_words` and `generation`. At least fourteen
declared words are required for this diagnostic; nine-word current/SOC/temp
responses remain supported and yield `ENODATA` only for the optional pair.
Malformed, missing, timed-out or changed-generation replies publish no cached
or partial pair. There is no setter, BCC request or whole-buffer dump.

Pinned normal-ADSP source suggests a maximum-voltage candidate at word2 with
microvolt scaling and a minimum-voltage candidate at word13 with millivolt
scaling. The file intentionally prints raw values: cell/extrema identity and
scaling remain unverified at runtime, and these are not standard `voltage_now`
or established full-charge/protection limits.
