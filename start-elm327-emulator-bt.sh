#!/bin/bash

# =============================================================================
# Usage
# =============================================================================
#
# Starts the ELM327 emulator in Bluetooth SPP (RFCOMM) mode on the Raspberry Pi.
# Use for Bluetooth SPP testing and Pi production environment validation.
#
# Prerequisites:
#   - Run as root or with sudo
#   - Bluetooth service must be available (bluetoothd)
#   - python3-elm package must be installed
#   - Client device must be paired after this script starts
#
# Steps:
#   1. SSH into the Pi
#   2. Run: sudo bash /opt/elm327/start-elm327-emulator-bt.sh
#   3. Pair the client device via Bluetooth settings
#   4. Start GTach on the Pi with --transport rfcomm
#
# Notes:
#   - rfcomm watch runs in the foreground — use tmux to persist after SSH disconnect:
#       tmux new -s elm327
#       sudo bash /opt/elm327/start-elm327-emulator-bt.sh
#   - SPP is registered on RFCOMM channel 1
#   - Emulator logs written to /opt/elm327/elm.log
#   - To stop: Ctrl+C
#
# =============================================================================

# Exit on error
set -e

export ELM_LOG_CFG=/opt/elm327/elm.yaml

cat > /opt/elm327/elm.yaml << 'EOL'
version: 1
disable_existing_loggers: False

formatters:
  compact:
    format: "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
  spaced:
    format: '%(asctime)s  %(name)-10s %(funcName)-15s %(levelname)-8s %(message)s'

handlers:
    file:
        class: logging.handlers.RotatingFileHandler
        formatter: spaced
        filename: /opt/elm327/elm.log
        level: DEBUG
        encoding: utf8
        maxBytes: 1000000
        backupCount: 2
        mode: 'w'

    console:
        class: logging.StreamHandler
        level: INFO
        formatter: compact
        stream: ext://sys.stdout

root:
    level: DEBUG
    handlers:
        - console
        - file
EOL

# Ensure Bluetooth service is running
echo "Restart Bluetooth service"
sudo service bluetooth restart
sleep 2

# Set Bluetooth device name
echo "Setting Bluetooth name..."
sudo btmgmt name "ELM327-Emulator"
sudo hciconfig hci0 name 'ELM327-Emulator'
sleep 2

# Release any existing RFCOMM connections
echo "Release any existing rfcomm connections"
sudo rfcomm release 0 2>/dev/null || true
sleep 2

# Ensure rfcomm device exists
echo "Ensure rfcomm device exists"
if [ ! -e /dev/rfcomm0 ]; then
    sudo mknod -m 666 /dev/rfcomm0 c 216 0
    sudo chown root:dialout /dev/rfcomm0
fi
sleep 2

# Register Serial Port Profile on channel 1
echo "Add the Serial Port Profile"
sdptool add --channel=1 SP
sleep 2

# Start emulator via rfcomm watch (foreground — spawns elm on each connection)
echo "ELM327-emulator waiting for connections..."
rfcomm watch /dev/rfcomm0 1 /opt/elm327/elm-start.sh
