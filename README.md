# ELM327 Bluetooth Emulator Scripts

Installation and startup scripts for ELM327 OBD-II Bluetooth emulator.

## Purpose

Provides automated setup and execution of an ELM327 emulator that presents as a Bluetooth device for OBD-II diagnostic applications.

## Scripts

### install-elm327-emulator.sh

Installs system dependencies, Python packages, and configures Bluetooth services and logging.

### start-elm327-emulator.sh

Launches the emulator as 'ELM327-Emulator' Bluetooth device on `/dev/rfcomm0`.

## Dependencies

- [python-OBD](https://github.com/brendan-w/python-OBD) - Python OBD-II interface
- [ELM327-emulator](https://github.com/ircama/ELM327-emulator) - ELM327 protocol emulator

## Copyright

Copyright (c) 2025 William Watson. This work is licensed under the MIT License.
