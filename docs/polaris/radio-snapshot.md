# Polaris radio calibration snapshot

[中文](radio-snapshot.zh.md) · [Polaris](README.md) · [Modem services](../modem.md)

`hardware.polaris.radio.snapshotDirectory` must point at a read-only snapshot of
the phone's own modem calibration data. `modem-rmtfs.service` serves it with
`rmtfs -s -r -o`; that same service starts MPSS. With no snapshot directory the
modem services are left out entirely, and Wi-Fi has no firmware service to talk
to (see [why](#why-wi-fi-needs-the-snapshot)).

## Required files

MPSS asks RMTFS for its EFS partitions by absolute path; `rmtfs -o` answers each
request with the basename inside the snapshot directory. Copy the GPT partitions
to those **file names**, which are not the partition labels:

| Partition label | Snapshot file | Size on polaris |
| --- | --- | --- |
| `modemst1` | `modem_fs1` | 8 MiB |
| `modemst2` | `modem_fs2` | 8 MiB |
| `fsg` | `modem_fsg` | 8 MiB |
| `fsc` | `modem_fsc` | 256 KiB |

Create the snapshot on the phone, as root, from the partitions the phone shipped
with:

```sh
d=/var/lib/polaris-radio-snapshot
mkdir -p "$d"
for pair in "modemst1 modem_fs1" "modemst2 modem_fs2" "fsg modem_fsg" "fsc modem_fsc"; do
  set -- $pair
  dd if="/dev/disk/by-partlabel/$1" of="$d/$2" bs=1M status=none
done
cd "$d" && sha256sum modem_fs1 modem_fs2 modem_fsg modem_fsc > SHA256SUMS
```

`modem-rmtfs.service` only requires that `SHA256SUMS` exists; it does not verify
the file contents. Keep a copy of the checksums and of the files outside the
phone so the same snapshot can be restored after reinstalling.

Configure the directory in the installed system configuration:

```nix
hardware.polaris.radio = {
  identityFile = "/var/lib/polaris-radio-identity/wifi-address";
  snapshotDirectory = "/var/lib/polaris-radio-snapshot";
};
```

RMTFS opens the snapshot read-only (`rmtfs -r`); calibration writes from MPSS are
kept in RAM and discarded, so the files stay byte-identical to the partitions.

## Why Wi-Fi needs the snapshot

`ath10k_snoc` does not talk to the WCN3990 alone. Its QMI handle uses
`AF_QIPCRTR`, and the WLFW service it looks up is published by MPSS, not by the
Wi-Fi chip:

```
ath10k_snoc_probe() → ath10k_qmi_init() → qmi_add_lookup(WLFW)
                     … waits for a QRTR server, which only exists once MPSS runs
                     → ath10k_qmi_event_server_arrive() → wlan0
```

`rmtfs -s` starts MPSS only after its own QRTR service is registered, and MPSS
cannot finish initialisation without the EFS files above. A missing file
therefore shows up as a Wi-Fi failure, not as a modem failure: the probe of
`18800000.wifi` succeeds, `wlan0` is never created, and ath10k prints nothing at
all, even with `ath10k_core.debug_mask=0xffff`.

## Troubleshooting

`rmtfs` logs every path it cannot open, naming both the file it looked for and
the path MPSS requested:

```
[storage] failed to open '.../modem_fs1' (requested '/boot/modem_fs1'): No such file or directory
[storage] failed to open '.../modem_fsg' (requested '/boot/modem_fsg'): No such file or directory
```

That log line is the only direct hint: `rmtfsVerbose` defaults to `false` on
polaris, so successful requests are not logged. With a missing or misnamed file
MPSS still starts and then dies roughly 40 seconds later, restarting on its own:

```
qcom-q6v5-mss 4080000.remoteproc: fatal error without message
remoteproc remoteproc0: crash detected in 4080000.remoteproc: type fatal error
```

Check the chain in this order:

```sh
cat /sys/class/remoteproc/remoteproc0/state   # running, and staying running
qrtr-lookup | grep -i wlfw                    # WLFW service published
ls /sys/class/net/wlan0                       # interface created
```

`wlan0` appears about ten seconds after `modem-rmtfs` starts. `polaris-wifi-address`
writes a systemd-networkd `.link` rule, so udev applies the factory address when
the interface is created; if the modem never comes up the rule never gets a
chance to apply and the interface would use a random address.
