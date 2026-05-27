#!/bin/bash
#
# status-elm327-emulator.sh
#
# Checks the health of the ELM327 Bluetooth emulator stack and all
# dependent services. Reports pass/fail for each component.
# Exits 0 if all critical checks pass, 1 if any critical check fails.
#
# Usage:
#   bash /opt/elm327/status-elm327-emulator.sh
#
# Run on the emulator Pi directly or via ssh:
#   ssh root@ELM327-Emulator.local bash /opt/elm327/status-elm327-emulator.sh
#

ELM_TCP_PORT=35000
RFCOMM_CHANNEL=1
INSTALL_DIR=/opt/elm327
BT_NAME="ELM327-Emulator"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

overall=0

pass()  { printf "  ${GREEN}[PASS]${RESET} %s\n" "$*"; }
fail()  { printf "  ${RED}[FAIL]${RESET} %s\n" "$*"; overall=1; }
warn()  { printf "  ${YELLOW}[WARN]${RESET} %s\n" "$*"; }
section() { printf "\n%s\n%s\n" "$*" "$(printf '%.0s-' {1..50})"; }

# ── 1. systemd services ───────────────────────────────────────────────────────
section "1. systemd services"

for svc in bluetooth elm327-emulator; do
    if systemctl is-active --quiet "${svc}"; then
        pass "${svc}.service is active"
    else
        state=$(systemctl show -p ActiveState --value "${svc}" 2>/dev/null || echo "unknown")
        fail "${svc}.service is not active (state: ${state})"
    fi
    if systemctl is-enabled --quiet "${svc}" 2>/dev/null; then
        pass "${svc}.service is enabled (survives reboot)"
    else
        warn "${svc}.service is not enabled; will not start on reboot"
    fi
done

# ── 2. Bluetooth adapter ──────────────────────────────────────────────────────
section "2. Bluetooth adapter"

if hciconfig hci0 > /dev/null 2>&1; then
    pass "hci0 present"
    hci_flags=$(hciconfig hci0 | grep -o 'UP\|RUNNING\|PSCAN\|ISCAN' | tr '\n' ' ')
    if echo "${hci_flags}" | grep -q 'UP'; then
        pass "hci0 UP  (flags: ${hci_flags})"
    else
        fail "hci0 is DOWN"
    fi
    # Report adapter name
    adapter_name=$(hciconfig hci0 name 2>/dev/null | awk -F"'" '{print $2}')
    if [[ "${adapter_name}" == "${BT_NAME}" ]]; then
        pass "Adapter name: '${adapter_name}'"
    else
        warn "Adapter name is '${adapter_name}'; expected '${BT_NAME}'"
    fi
    # Report MAC address
    adapter_mac=$(hciconfig hci0 2>/dev/null | awk '/BD Address/{print $3}')
    if [[ -n "${adapter_mac}" ]]; then
        pass "Adapter MAC: ${adapter_mac}"
    fi
else
    fail "hci0 not found; no Bluetooth adapter detected"
fi

# ── 3. Python processes ───────────────────────────────────────────────────────
section "3. Running processes"

elm_pid=$(pgrep -f 'python3 -m elm' 2>/dev/null | head -1)
if [[ -n "${elm_pid}" ]]; then
    pass "ELM327 emulator running (PID ${elm_pid})"
else
    fail "ELM327 emulator (python3 -m elm) not running"
fi

bt_pid=$(pgrep -f 'bt-server.py' 2>/dev/null | head -1)
if [[ -n "${bt_pid}" ]]; then
    pass "bt-server.py running (PID ${bt_pid})"
else
    fail "bt-server.py not running"
fi

# ── 4. TCP backend ────────────────────────────────────────────────────────────
section "4. ELM327 TCP backend (port ${ELM_TCP_PORT})"

if (exec 3<>"/dev/tcp/127.0.0.1/${ELM_TCP_PORT}") 2>/dev/null; then
    exec 3<&- 3>&-
    pass "TCP port ${ELM_TCP_PORT} accepting connections"
else
    fail "TCP port ${ELM_TCP_PORT} not responding"
fi

# ── 5. RFCOMM / Bluetooth socket ─────────────────────────────────────────────
section "5. RFCOMM channel ${RFCOMM_CHANNEL}"

# bt-server.py holds a socket on AF_BLUETOOTH; check via /proc/net if available
if grep -qsE 'AF_BLUETOOTH|rfcomm' /proc/net/unix 2>/dev/null; then
    pass "RFCOMM socket present in /proc/net/unix"
else
    # Fallback: check the process is alive (already done above) and the port
    # is bound via ss
    if ss -x 2>/dev/null | grep -qi rfcomm; then
        pass "RFCOMM socket visible via ss"
    elif [[ -n "${bt_pid}" ]]; then
        warn "Cannot confirm RFCOMM socket directly; bt-server.py process is alive"
    else
        fail "RFCOMM socket not detectable and bt-server.py not running"
    fi
fi

# ── 6. SDP record (informational) ────────────────────────────────────────────
section "6. SDP Serial Port Profile record (informational)"

if sdptool browse local 2>/dev/null | grep -qi 'Serial Port'; then
    pass "SPP service record present in local SDP"
else
    warn "SPP service record not found via sdptool; GTach hardcodes channel ${RFCOMM_CHANNEL} and does not require SDP"
fi

# ── 7. Paired devices ────────────────────────────────────────────────────────
section "7. Paired Bluetooth devices"

paired=$(bluetoothctl devices Paired 2>/dev/null)
if [[ -n "${paired}" ]]; then
    pass "Paired devices:"
    while IFS= read -r line; do
        printf "    %s\n" "${line}"
    done <<< "${paired}"
else
    warn "No paired devices; GTach will not be able to connect until pairing is completed"
fi

# ── 8. Log tail ───────────────────────────────────────────────────────────────
section "8. Recent log activity"

for logfile in "${INSTALL_DIR}/bt-server.log" "${INSTALL_DIR}/elm.log"; do
    if [[ -f "${logfile}" ]]; then
        printf "\n  --- last 5 lines of %s ---\n" "${logfile}"
        tail -5 "${logfile}" | sed 's/^/    /'
    else
        warn "${logfile} not found (service may not have started yet)"
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n%s\n" "$(printf '%.0s=' {1..50})"
if [[ ${overall} -eq 0 ]]; then
    printf "${GREEN}All critical checks passed.${RESET}\n\n"
else
    printf "${RED}One or more critical checks failed. Review output above.${RESET}\n\n"
fi

exit ${overall}
