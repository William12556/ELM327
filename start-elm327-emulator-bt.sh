#!/bin/bash
#
# start-elm327-emulator-bt.sh
#
# Starts the ELM327 emulator with a Bluetooth SPP (RFCOMM) bridge on the Pi.
# Suitable for both interactive use and systemd service execution.
#
# Architecture:
#   GTach (RFCOMM)  <->  bt-server.py  <->  elm (TCP 35000)
#
# Usage (interactive):
#   sudo bash /opt/elm327/start-elm327-emulator-bt.sh
#
# Usage (systemd):
#   See /etc/systemd/system/elm327-emulator.service
#
# NOTE: TCP backend readiness is checked via ss (socket listener state),
# not by opening a connection. The ircama ELM327 emulator terminates on
# bare connections that send no data.
#
# NOTE: ELM_LOG_CFG is intentionally not set. Applying a yaml log config
# causes the emulator to self-terminate during log handler initialisation.
# Emulator output is captured by systemd (journalctl -u elm327-emulator).
#

INSTALL_DIR=/opt/elm327
BT_NAME="ELM327-Emulator"
RFCOMM_CHANNEL=1
ELM_TCP_PORT=35000
TCP_READY_TIMEOUT=30

ELM_PID=""
BT_PID=""

log() { printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"; }

cleanup() {
    log "Stopping services..."
    if [[ -n "${BT_PID}" ]] && kill -0 "${BT_PID}" 2>/dev/null; then
        kill -TERM "${BT_PID}" 2>/dev/null || true
        wait "${BT_PID}" 2>/dev/null || true
    fi
    if [[ -n "${ELM_PID}" ]] && kill -0 "${ELM_PID}" 2>/dev/null; then
        kill -TERM "${ELM_PID}" 2>/dev/null || true
        wait "${ELM_PID}" 2>/dev/null || true
    fi
    pkill -f 'python3 -m elm' 2>/dev/null || true
    pkill -f 'bt-server.py' 2>/dev/null || true
    log "Stopped."
}
trap cleanup EXIT INT TERM

if [[ $EUID -ne 0 ]]; then
    log "ERROR: must run as root"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

# Stop any prior instances
log "Cleaning up previous instances..."
pkill -f 'python3 -m elm' 2>/dev/null || true
pkill -f 'bt-server.py' 2>/dev/null || true
rfcomm release 0 2>/dev/null || true
sleep 1

# Ensure bluetooth service is running
log "Ensuring bluetooth service is active..."
if ! systemctl is-active --quiet bluetooth; then
    systemctl start bluetooth || log "WARNING: failed to start bluetooth.service"
    sleep 2
fi

# Verify adapter
if ! hciconfig hci0 > /dev/null 2>&1; then
    log "ERROR: hci0 not found; is the adapter present?"
    exit 1
fi
hciconfig hci0 up 2>/dev/null || true

# Configure adapter identity and visibility
log "Configuring adapter (name=${BT_NAME})..."
btmgmt name "${BT_NAME}" "${BT_NAME}" >/dev/null 2>&1 || true
hciconfig hci0 name "${BT_NAME}" >/dev/null 2>&1 || true
btmgmt power on       >/dev/null 2>&1 || true
btmgmt connectable on >/dev/null 2>&1 || true
btmgmt pairable on    >/dev/null 2>&1 || true
btmgmt discov on      >/dev/null 2>&1 || true

# Register SDP Serial Port Profile (non-fatal)
if sdptool add --channel="${RFCOMM_CHANNEL}" SP >/dev/null 2>&1; then
    log "SDP Serial Port Profile registered on channel ${RFCOMM_CHANNEL}"
else
    log "WARNING: sdptool failed; SDP record not advertised (non-fatal for GTach)"
fi

# Launch ELM327 emulator (TCP 35000)
# ELM_LOG_CFG is deliberately unset; see file header note.
log "Starting ELM327 emulator on TCP port ${ELM_TCP_PORT}..."
cd "${INSTALL_DIR}"
python3 -m elm -s car -n "${ELM_TCP_PORT}" &
ELM_PID=$!
log "  ELM327 emulator PID: ${ELM_PID}"

# Wait for TCP port to appear in ss listener table.
# Do NOT use a live TCP connection probe: the ircama emulator terminates
# on connections that send no data.
log "Waiting for TCP backend to become ready (up to ${TCP_READY_TIMEOUT}s)..."
ready=0
for ((i = 0; i < TCP_READY_TIMEOUT; i++)); do
    if ss -tlnp 2>/dev/null | awk '{print $4}' | grep -q ":${ELM_TCP_PORT}$"; then
        ready=1
        break
    fi
    if ! kill -0 "${ELM_PID}" 2>/dev/null; then
        log "ERROR: ELM327 emulator exited prematurely"
        exit 1
    fi
    sleep 1
done

if [[ $ready -ne 1 ]]; then
    log "ERROR: TCP backend not ready after ${TCP_READY_TIMEOUT}s"
    exit 1
fi
log "TCP backend ready."

# Launch Bluetooth bridge
log "Starting Bluetooth bridge on RFCOMM channel ${RFCOMM_CHANNEL}..."
log "GTach can now connect via Bluetooth."
python3 "${INSTALL_DIR}/bt-server.py" &
BT_PID=$!
log "  bt-server.py PID: ${BT_PID}"

# Wait on bt-server; cleanup trap fires on exit
wait "${BT_PID}"
