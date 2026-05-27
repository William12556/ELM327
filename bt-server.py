#!/usr/bin/env python3
"""
bt-server.py - Bluetooth SPP RFCOMM to TCP bridge.

Accepts RFCOMM client connections on channel 1 and relays data bidirectionally
to the ircama ELM327 emulator running on TCP localhost:35000.

Architecture:
    GTach (RFCOMM) <-> bt-server.py <-> elm (TCP 127.0.0.1:35000)

Behaviour:
    - Binds AF_BLUETOOTH/SOCK_STREAM/BTPROTO_RFCOMM on channel 1, BDADDR_ANY.
    - Per-connection failures are logged and isolated; the listener stays up.
    - Logs to /opt/elm327/bt-server.log (rotating) and stdout.
    - Graceful shutdown on SIGINT / SIGTERM.

Note:
    TCP backend readiness is verified by start-elm327-emulator-bt.sh before
    this process is launched. No probe connection is made here; the ircama
    ELM327 emulator terminates on bare probe connections that send no data.

Requirements:
    - Python 3 standard library only.
    - Must run as root (AF_BLUETOOTH bind).
    - bluetoothd running; adapter up.
    - ELM327 emulator listening on TCP 127.0.0.1:35000.
"""

import logging
import os
import signal
import socket
import sys
import threading
from logging.handlers import RotatingFileHandler

RFCOMM_CHANNEL = 1
BDADDR_ANY = "00:00:00:00:00:00"
ELM_TCP_HOST = "127.0.0.1"
ELM_TCP_PORT = 35000
BUFFER_SIZE = 1024
LOG_PATH = "/opt/elm327/bt-server.log"
ACCEPT_TIMEOUT_SEC = 1.0

logger = logging.getLogger("bt-server")
_shutdown = threading.Event()


def setup_logging() -> None:
    logger.setLevel(logging.DEBUG)
    fmt = logging.Formatter(
        "%(asctime)s %(levelname)-7s %(message)s", "%Y-%m-%d %H:%M:%S"
    )
    try:
        fh = RotatingFileHandler(LOG_PATH, maxBytes=1_000_000, backupCount=2, mode="a")
        fh.setLevel(logging.DEBUG)
        fh.setFormatter(fmt)
        logger.addHandler(fh)
    except OSError as e:
        print(f"Warning: cannot open log file {LOG_PATH}: {e}", file=sys.stderr)
    sh = logging.StreamHandler(sys.stdout)
    sh.setLevel(logging.INFO)
    sh.setFormatter(fmt)
    logger.addHandler(sh)


def relay(src: socket.socket, dst: socket.socket, label: str) -> None:
    """Relay data src -> dst until either side closes."""
    try:
        while not _shutdown.is_set():
            data = src.recv(BUFFER_SIZE)
            if not data:
                logger.debug("%s: peer closed", label)
                break
            dst.sendall(data)
    except OSError as e:
        logger.debug("%s: %s", label, e)
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def handle_client(client_sock: socket.socket, client_addr) -> None:
    """Bridge one RFCOMM client to one TCP backend connection."""
    logger.info("BT client connected: %s", client_addr)
    tcp_sock = None
    try:
        tcp_sock = socket.create_connection((ELM_TCP_HOST, ELM_TCP_PORT), timeout=5.0)
        tcp_sock.settimeout(None)
        logger.info("Bridged %s <-> %s:%d", client_addr, ELM_TCP_HOST, ELM_TCP_PORT)
        t1 = threading.Thread(target=relay, args=(client_sock, tcp_sock, "BT->TCP"), daemon=True)
        t2 = threading.Thread(target=relay, args=(tcp_sock, client_sock, "TCP->BT"), daemon=True)
        t1.start()
        t2.start()
        t1.join()
        t2.join()
    except OSError as e:
        logger.error("Bridge failure for %s: %s", client_addr, e)
    finally:
        if tcp_sock is not None:
            try:
                tcp_sock.close()
            except OSError:
                pass
        try:
            client_sock.close()
        except OSError:
            pass
        logger.info("BT client disconnected: %s", client_addr)


def _signal_handler(signum, _frame) -> None:
    logger.info("Signal %d received, initiating shutdown", signum)
    _shutdown.set()


def main() -> int:
    setup_logging()
    signal.signal(signal.SIGTERM, _signal_handler)
    signal.signal(signal.SIGINT, _signal_handler)

    if os.geteuid() != 0:
        logger.warning("Not running as root; AF_BLUETOOTH bind will likely fail")

    logger.info("Connecting RFCOMM channel %d to TCP %s:%d",
                RFCOMM_CHANNEL, ELM_TCP_HOST, ELM_TCP_PORT)

    try:
        server_sock = socket.socket(
            socket.AF_BLUETOOTH, socket.SOCK_STREAM, socket.BTPROTO_RFCOMM
        )
    except (AttributeError, OSError) as e:
        logger.error("AF_BLUETOOTH unavailable: %s", e)
        return 1

    server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server_sock.bind((BDADDR_ANY, RFCOMM_CHANNEL))
    except OSError as e:
        logger.error("Bind to RFCOMM channel %d failed: %s", RFCOMM_CHANNEL, e)
        server_sock.close()
        return 1
    server_sock.listen(1)
    server_sock.settimeout(ACCEPT_TIMEOUT_SEC)
    logger.info("Listening on RFCOMM channel %d (BDADDR_ANY)", RFCOMM_CHANNEL)

    try:
        while not _shutdown.is_set():
            try:
                client_sock, client_addr = server_sock.accept()
            except socket.timeout:
                continue
            except OSError as e:
                if _shutdown.is_set():
                    break
                logger.error("accept() failed: %s", e)
                continue
            handle_client(client_sock, client_addr)
    finally:
        try:
            server_sock.close()
        except OSError:
            pass
        logger.info("Shutdown complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
