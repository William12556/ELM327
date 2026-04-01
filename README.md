# ELM327 Bluetooth Emulator Scripts

Installation and startup scripts for ELM327 OBD-II Bluetooth emulator.

## Purpose

Provides automated setup and execution of an ELM327 emulator that presents as a Bluetooth device for OBD-II diagnostic applications.

## Scripts

### install-elm327-emulator.sh

Installs system dependencies, Python packages, and configures Bluetooth services and logging.

### start-elm327-emulator.sh

Launches the emulator as 'ELM327-Emulator' Bluetooth device on `/dev/rfcomm0`.

## Usage

The emulator is started manually. No boot-time service is configured.

```bash
sudo /path/to/start-elm327-emulator.sh
```

The script:
- Restarts the Bluetooth service
- Sets the Bluetooth device name to `ELM327-Emulator`
- Registers the Serial Port Profile (SPP) on channel 1
- Starts the emulator in the background via `rfcomm watch` on `/dev/rfcomm0`
- Writes a PID file to `/opt/elm327/elm327.pid`
- Logs to `/opt/elm327/elm.log`

**Note:** The script requires `sudo` for Bluetooth and `rfcomm` operations. Ensure the script is deployed to `/opt/elm327/` or adjust the path accordingly.

## Dependencies

- [python-OBD](https://github.com/brendan-w/python-OBD) - Python OBD-II interface (```https://github.com/brendan-w/python-OBD```)
- [ELM327-emulator](https://github.com/ircama/ELM327-emulator) - ELM327 protocol emulator (```https://github.com/ircama/ELM327-emulator```)

## Version History

| Version | Date | Description |
|---------|------|-------------|
| 1.1 | 2026-04-01 | Added Usage section; documented manual start procedure |
| 1.0 | 2025 | Initial release |

## Copyright

Copyright (c) 2026 William Watson. MIT License.
