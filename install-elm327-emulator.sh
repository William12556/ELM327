#!/bin/bash
#
# install-elm327-emulator.sh
#
# Installs the ELM327 emulator with the Bluetooth RFCOMM bridge and registers
# a systemd service so the stack starts automatically at boot.
#
# Idempotent: stops the running service, uninstalls prior pip packages, and
# reinstalls from a clean state. Safe to re-run.
#
# Run on the target Pi (root or sudo):
#   bash install-elm327-emulator.sh
#
# After installation, the emulator service starts on boot and is also
# controllable manually:
#   systemctl status  elm327-emulator
#   systemctl start   elm327-emulator
#   systemctl stop    elm327-emulator
#   journalctl -u elm327-emulator -f
#

set -e

INSTALL_DIR=/opt/elm327
SERVICE_NAME=elm327-emulator
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use sudo only if not already root
if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

echo "==> Stopping any running ${SERVICE_NAME} service..."
${SUDO} systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
${SUDO} pkill -f 'python3 -m elm' 2>/dev/null || true
${SUDO} pkill -f 'bt-server.py'   2>/dev/null || true
sleep 1

echo "==> Installing system packages..."
${SUDO} apt-get update
${SUDO} apt-get install -y \
    python3 \
    python3-pip \
    bluez \
    bluez-tools \
    git

echo "==> Uninstalling prior Python packages (if present)..."
${SUDO} python3 -m pip uninstall -y --break-system-packages ELM327-emulator 2>/dev/null || true
${SUDO} python3 -m pip uninstall -y --break-system-packages obd             2>/dev/null || true

echo "==> Installing build dependencies (setuptools<81, wheel)..."
# ircama/ELM327-emulator's setup.py imports pkg_resources, which setuptools>=81
# no longer provides. Pin setuptools<81 system-wide and install the emulator
# with --no-build-isolation so the system setuptools is used at build time.
${SUDO} python3 -m pip install --break-system-packages 'setuptools<81' wheel

echo "==> Installing python-OBD..."
${SUDO} python3 -m pip install --break-system-packages \
    git+https://github.com/brendan-w/python-OBD.git

echo "==> Installing ELM327-emulator (no build isolation)..."
${SUDO} python3 -m pip install --break-system-packages --no-build-isolation \
    git+https://github.com/ircama/ELM327-emulator

echo "==> Installing runtime files to ${INSTALL_DIR}..."
${SUDO} mkdir -p "${INSTALL_DIR}"
${SUDO} cp "${SRC_DIR}/bt-server.py"                 "${INSTALL_DIR}/bt-server.py"
${SUDO} cp "${SRC_DIR}/start-elm327-emulator-bt.sh"  "${INSTALL_DIR}/start-elm327-emulator-bt.sh"
${SUDO} cp "${SRC_DIR}/start-elm327-emulator-tcp.sh" "${INSTALL_DIR}/start-elm327-emulator-tcp.sh"
${SUDO} chmod 755 "${INSTALL_DIR}/start-elm327-emulator-bt.sh"
${SUDO} chmod 755 "${INSTALL_DIR}/start-elm327-emulator-tcp.sh"
${SUDO} chmod 644 "${INSTALL_DIR}/bt-server.py"

echo "==> Installing bluetoothd --compat drop-in..."
${SUDO} mkdir -p /etc/systemd/system/bluetooth.service.d
${SUDO} cp "${SRC_DIR}/bluetoothd-compat.conf" \
           /etc/systemd/system/bluetooth.service.d/compat.conf

echo "==> Installing ${SERVICE_NAME}.service..."
${SUDO} cp "${SRC_DIR}/${SERVICE_NAME}.service" \
           "/etc/systemd/system/${SERVICE_NAME}.service"

echo "==> Reloading systemd and restarting bluetooth..."
${SUDO} systemctl daemon-reload
${SUDO} systemctl restart bluetooth
sleep 2

echo "==> Enabling and starting ${SERVICE_NAME}.service..."
${SUDO} systemctl enable "${SERVICE_NAME}.service"
${SUDO} systemctl restart "${SERVICE_NAME}.service"

echo
echo "Installation complete."
echo
echo "Status:"
${SUDO} systemctl status "${SERVICE_NAME}.service" --no-pager || true
echo
echo "Logs:"
echo "  journalctl -u ${SERVICE_NAME} -f"
echo "  tail -f ${INSTALL_DIR}/bt-server.log"
echo "  tail -f ${INSTALL_DIR}/elm.log"
echo
echo "Pair the GTach Pi against this host once; thereafter, GTach can connect on RFCOMM channel 1."
