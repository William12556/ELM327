#!/bin/bash

# =============================================================================
# Usage
# =============================================================================
#
# Run this script on the Raspberry Pi to start the ELM327 emulator.
#
# Prerequisites:
#   - Run as root or with sudo
#   - Bluetooth service must be available (bluetoothd)
#   - python3-elm package must be installed
#
# Steps:
#   1. SSH into the Pi
#   2. Run: sudo bash /opt/elm327/start-elm327-emulator.sh
#   3. The script runs rfcomm watch in the foreground — use screen or tmux
#      to keep it running after SSH disconnect:
#        screen -S elm327 sudo bash /opt/elm327/start-elm327-emulator.sh
#   4. Pair the client device (Mac) via Bluetooth settings
#   5. Start GTach on the client
#
# Notes:
#   - rfcomm watch runs in the foreground and spawns elm on each connection
#   - The emulator device name is set to 'ELM327-Emulator'
#   - SPP is registered on RFCOMM channel 1
#   - Logs are written to /opt/elm327/elm.log
#   - To stop: Ctrl+C (or kill the screen/tmux session)
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
    #datefmt: '%H:%M:%S'
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
        mode: 'w' # default is a which means append
        
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

# First ensure the Bluetooth service is running and configured
echo "Restart Bluetooth service"
sudo service bluetooth restart
sleep 2

# Set name using multiple methods to ensure it takes effect
echo "Setting Bluetooth name..."
sudo btmgmt name "ELM327-Emulator"
sudo hciconfig hci0 name 'ELM327-Emulator'
sleep 2

# Release any existing connections
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

# Add the Serial Port Profile
echo "Add the Serial Port Profile"
sdptool add --channel=1 SP
sleep 2

# Set baud rate on rfcomm0 to match client expectation (38400)
stty -F /dev/rfcomm0 38400

# Start elm327 emulator - rfcomm watch runs in foreground, spawning elm on each connection
echo "ELM327-emulator waiting for connections (foreground - use screen or tmux)"
rfcomm watch /dev/rfcomm0 1 bash -c 'stty -F /dev/rfcomm0 38400 && python3 -m elm -P /dev/rfcomm0 -l -s car -b /opt/elm327/elm.out -d'
echo "The device should now be discoverable as 'ELM327-Emulator'"

# Show current status
echo "Current Bluetooth status:"
bluetoothctl show

# Show SP services
echo "Current SP services:"
sdptool browse local | grep -A 15 "Service Name: Serial Port"
