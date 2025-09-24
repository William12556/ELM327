#!/bin/bash

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

# Start elm327 emulator in batch mode with proper daemon handling
rfcomm watch /dev/rfcomm0 1 python3 -m elm -P /dev/rfcomm0 -l -s car -b /opt/elm327/elm.out -d &
sleep 2

# Save the PID
PID=$!
echo $! > /opt/elm327/elm327.pid

echo "ELM327-emulator started in daemon mode background"
echo "The device should now be discoverable as 'ELM327-Emulator'"

# Show current status
echo "Current Bluetooth status:"
bluetoothctl show

# Show SP services
echo "Current SP services:"
sdptool browse local | grep -A 15 "Service Name: Serial Port"
