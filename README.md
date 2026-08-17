# ELM327 Bluetooth Emulator Scripts

Linux installation and runtime scripts for [ELM327-emulator](https://github.com/ircama/ELM327-emulator) an ELM327 OBD-II emulator that presents
itself over Bluetooth SPP (RFCOMM).

## Architecture

```
GTach (RFCOMM)  <-->  bt-server.py  <-->  ircama ELM327 emulator (TCP 35000)
```

The ircama ELM327 emulator listens on TCP port 35000. A Bluetooth bridge
(`bt-server.py`) binds RFCOMM channel 1 and relays data bidirectionally to
the emulator's TCP socket.

## Files

| File | Purpose |
|---|---|
| `install-elm327-emulator.sh` | Idempotent installer: packages, scripts, systemd unit |
| `start-elm327-emulator-bt.sh` | Starts emulator + Bluetooth bridge (used by systemd unit and for manual runs) |
| `start-elm327-emulator-tcp.sh` | Starts emulator in TCP-only mode (no Bluetooth) |
| `bt-server.py` | RFCOMM-to-TCP bridge daemon |
| `elm327-emulator.service` | systemd unit for boot-time startup |
| `status-elm327-emulator.sh` | Health check: reports status of all dependent services and components |

## Installation

On the target Raspberry Pi (root or sudo):

```bash
git clone https://github.com/William12556/ELM327.git
cd ELM327
bash install-elm327-emulator.sh
```

The installer:

- Stops any running service and uninstalls any prior pip packages.
- Installs `bluez`, `bluez-tools`, `python-OBD`, and `ELM327-emulator`.
  - Pins `setuptools<81` so the emulator's legacy `setup.py` can build.
- Copies runtime scripts to `/opt/elm327/`.
- Installs and enables `elm327-emulator.service`.
- Runs `status-elm327-emulator.sh` on completion.

After installation the service starts automatically on every boot.
The installer is idempotent: re-running it cleans up prior state and reinstalls.

## Operation

### Service control

```bash
systemctl status  elm327-emulator
systemctl start   elm327-emulator
systemctl stop    elm327-emulator
systemctl restart elm327-emulator
```

### Status check

```bash
bash /opt/elm327/status-elm327-emulator.sh
```

Reports pass/fail/warn for each component in the stack:

1. systemd service state (`bluetooth`, `elm327-emulator`) and enabled status
2. Bluetooth adapter presence, UP/RUNNING flags, name, and MAC
3. Running processes (`python3 -m elm`, `bt-server.py`)
4. TCP port 35000 accepting connections
5. RFCOMM channel 1 socket
6. SDP Serial Port Profile record (informational)
7. Paired Bluetooth devices
8. Last 5 lines of `bt-server.log` and `elm.log`

Exit code 0 = all critical checks passed. Exit code 1 = one or more critical checks failed.

Run remotely from the Mac:

```bash
ssh root@ELM327-Emulator.local bash /opt/elm327/status-elm327-emulator.sh
```

### Logs

```bash
journalctl -u elm327-emulator -f         # systemd log (startup, errors)
tail -f /opt/elm327/bt-server.log        # RFCOMM bridge activity
tail -f /opt/elm327/elm.log              # ELM327 emulator command trace
```

### Pairing GTach

A Bluetooth pairing handshake is required once between the GTach Pi and the
emulator Pi. From the GTach Pi:

```bash
bluetoothctl
[bluetooth]# scan on
# wait for ELM327-Emulator to appear
[bluetooth]# pair  <MAC>
[bluetooth]# trust <MAC>
[bluetooth]# quit
```

Thereafter, GTach connects on RFCOMM channel 1 without prompting.

### Manual start (without systemd)

```bash
systemctl stop elm327-emulator
/opt/elm327/start-elm327-emulator-bt.sh
```

`Ctrl+C` shuts the bridge and emulator down cleanly.

### TCP-only mode (macOS development)

For non-Bluetooth testing from the development Mac:

```bash
systemctl stop elm327-emulator
bash /opt/elm327/start-elm327-emulator-tcp.sh
```

## Dependencies

- [python-OBD](https://github.com/brendan-w/python-OBD)
- [ELM327-emulator](https://github.com/ircama/ELM327-emulator)
- bluez 5.x

## Notes

- The bridge binds with `BDADDR_ANY`, so it adopts whichever Bluetooth
  adapter is active.
- The bridge waits up to 30 s for the TCP backend before opening the RFCOMM
  listener; if the emulator fails to start, the service exits and systemd
  retries after 5 s.
- `sdptool` is invoked at runtime to advertise an SDP record for the SPP
  service. This is deprecated in bluez 5.x and will typically warn on stock
  Debian Bookworm; the failure is non-fatal. GTach hardcodes RFCOMM channel 1
  and does not require the SDP record.

## Version History

| Version | Date | Description |
|---|---|---|
| 2.2 | 2026-05-26 | Added `status-elm327-emulator.sh`; installer now runs status check on completion |
| 2.1 | 2026-05-26 | Removed `bluetoothd --compat` drop-in; installer cleans up prior compat.conf |
| 2.0 | 2026-05-26 | Boot-time automation via systemd; hardened `bt-server.py` and `start-elm327-emulator-bt.sh` |
| 1.1 | 2026-04-01 | Added Usage section; documented manual start procedure |
| 1.0 | 2025 | Initial release |

## Copyright

Copyright (c) 2026 William Watson. MIT License.
