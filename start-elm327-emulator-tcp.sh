#!/bin/bash

# =============================================================================
# Usage
# =============================================================================
#
# Starts the ELM327 emulator in TCP mode on the Raspberry Pi.
# Use for macOS development with GTach --transport tcp.
#
# Prerequisites:
#   - Run as root or with sudo
#   - Bluetooth service must be available (bluetoothd)
#   - python3-elm package must be installed
#
# Steps:
#   1. SSH into the Pi
#   2. Run: sudo bash /opt/elm327/start-elm327-emulator-tcp.sh
#   3. Start GTach on the Mac: python -m gtach --macos --transport tcp
#
# Notes:
#   - Emulator runs as a background daemon on TCP port 35000
#   - Logs are written to /opt/elm327/nohup.out
#   - To stop: pkill -f 'python3 -m elm'
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

# Start emulator in TCP daemon mode
echo "Starting ELM327 emulator in TCP mode on port 35000..."
cd /opt/elm327 && nohup python3 -m elm -s car -l -n 35000 &
sleep 1
echo "ELM327 emulator started. TCP port 35000."
echo "To stop: pkill -f 'python3 -m elm'"
