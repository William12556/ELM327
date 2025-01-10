#!/bin/bash

# Exit on error
set -e

echo "Installing ELM327-emulator and dependencies..."

# Update system
sudo apt-get update
sudo apt-get -y upgrade

# Install required packages
sudo apt-get install -y \
    python3 \
    python3-pip \
    bluez \
    git

# Upgrade pip system-wide
sudo python3 -m pip install --upgrade pip --break-system-packages

# Install python-OBD from GitHub system-wide
sudo python3 -m pip install --upgrade git+https://github.com/brendan-w/python-OBD.git --break-system-packages

# Install ELM327-emulator from GitHub system-wide
sudo python3 -m pip install git+https://github.com/ircama/ELM327-emulator --break-system-packages

# Configure Bluetooth
sudo service bluetooth restart

# Create RFCOMM device
sudo mknod -m 666 /dev/rfcomm0 c 216 0
sudo chown $USER /dev/rfcomm0

# Add SP profile
sdptool add --channel=1 SP

# Create directory for log configuration
sudo mkdir -p /etc/elm327-emulator

# Create basic logging configuration system-wide
sudo tee /etc/elm327-emulator/elm.yaml << 'EOL'
version: 1
disable_existing_loggers: true

formatters:
    standard:
        format: '%(asctime)s [%(levelname)s] %(message)s'
        datefmt: '%Y-%m-%d %H:%M:%S'

handlers:
    console:
        class: logging.StreamHandler
        level: INFO
        formatter: standard
        stream: ext://sys.stdout

    file:
        class: logging.handlers.RotatingFileHandler
        level: INFO
        formatter: standard
        filename: /var/log/elm327-emulator/elm.log
        maxBytes: 1048576
        backupCount: 2

loggers:
    '':
        level: INFO
        handlers: [console, file]
        propagate: no
EOL

# Create log directory with appropriate permissions
sudo mkdir -p /var/log/elm327-emulator
sudo chown $USER:$USER /var/log/elm327-emulator

# Set environment variable for log config
echo 'export ELM_LOG_CFG=/etc/elm327-emulator/elm.yaml' | sudo tee -a /etc/profile.d/elm327-emulator.sh

echo "Installation complete!"
echo "You can now use the start script to run ELM327-emulator"
echo "Please log out and back in, or run 'source /etc/profile.d/elm327-emulator.sh' to use the emulator"
