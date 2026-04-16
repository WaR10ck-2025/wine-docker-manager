#!/opt/uds-sim/venv/bin/python3
"""
UDS Simulator — Stufe T1 + T2 auf vcan0.

Services:
  $10  DiagnosticSessionControl  (Default / Extended)
  $22  ReadDataByIdentifier      (T1)
  $27  SecurityAccess            (Request Seed / Send Key, XOR-Algo)
  $2E  WriteDataByIdentifier     (T2, writable DIDs mutieren das In-Memory-Dict)

State-Machine (single-client Lab, daher module-globale State):
  _session_extended : $10 03 gesetzt → $27 + $2E werden akzeptiert
  _security_unlocked: $27 02 mit korrektem Key → $2E wird akzeptiert
  _last_seed        : letzter $27 01 Seed, verfaellt nach $27 02
  _failed_attempts  : zaehlt falsche Keys, >= MAX_FAILED → NRC 0x36

Seed->Key:
  key = seed XOR 0xDEADBEEF  (Lab-Platzhalter; echter OEM-Algo erst T3)
"""
import logging
import secrets
import signal
import struct
import sys

import can
import isotp

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("uds-sim")

# ── DID-Registry (mutable, $2E schreibt rein) ──────────────────────────────
DIDS: dict[int, bytes] = {
    0xF190: b"JS2RE82S042111111",      # VIN (17 chars)
    0xF195: b"1.0.0-sim",              # System Supplier ECU SW Version (9)
    0xF18C: b"SN-UDSSIM-00001",        # ECU Serial Number (15)
    0xF40C: bytes([0x2E, 0x14]),       # Control Module Voltage (2 bytes, 0x2E14/1000 = 11.796V)
}
WRITABLE_DIDS = {0xF190, 0xF195, 0xF18C, 0xF40C}

# ── Services & NRCs (ISO 14229-1) ──────────────────────────────────────────
SID_SESSION  = 0x10
SID_READ     = 0x22
SID_SECURITY = 0x27
SID_WRITE    = 0x2E

NRC_SUB_FUNC_NOT_SUPPORTED   = 0x12
NRC_LEN                      = 0x13
NRC_COND_NOT_CORRECT         = 0x22
NRC_REQ_SEQ_ERROR            = 0x24
NRC_OUT_OF_RANGE             = 0x31
NRC_SEC_NOT_SATISFIED        = 0x33
NRC_INVALID_KEY              = 0x35
NRC_EXCEEDED_ATTEMPTS        = 0x36
NRC_SVC_NOT_SUPPORTED        = 0x11

# ── Security ───────────────────────────────────────────────────────────────
KEY_MASK = 0xDEADBEEF
MAX_FAILED = 3

# ── State ──────────────────────────────────────────────────────────────────
_session_extended = False
_security_unlocked = False
_failed_attempts = 0
_last_seed: bytes | None = None


def _reset_state():
    global _session_extended, _security_unlocked, _failed_attempts, _last_seed
    _session_extended = False
    _security_unlocked = False
    _failed_attempts = 0
    _last_seed = None


def neg(sid: int, nrc: int) -> bytes:
    return bytes([0x7F, sid, nrc])


def _handle_session(payload: bytes) -> bytes:
    global _session_extended
    if len(payload) != 2:
        return neg(SID_SESSION, NRC_LEN)
    sub = payload[1]
    # ISO 14229-1 (2013+): DSC-Response enthaelt P2/P2*-Timing-Block.
    # P2 = 50ms in 1ms-Resolution  (0x0032)
    # P2*= 5000ms in 10ms-Resolution (0x01F4)
    timing = bytes([0x00, 0x32, 0x01, 0xF4])
    if sub == 0x01:
        _reset_state()
        log.info("SESSION -> Default")
        return bytes([0x50, sub]) + timing
    if sub == 0x03:
        _session_extended = True
        log.info("SESSION -> Extended")
        return bytes([0x50, sub]) + timing
    return neg(SID_SESSION, NRC_SUB_FUNC_NOT_SUPPORTED)


def _handle_security(payload: bytes) -> bytes:
    global _last_seed, _security_unlocked, _failed_attempts
    if len(payload) < 2:
        return neg(SID_SECURITY, NRC_LEN)
    sub = payload[1]

    if not _session_extended:
        log.info(f"SEC sub=0x{sub:02X} abgelehnt: keine Extended-Session")
        return neg(SID_SECURITY, NRC_COND_NOT_CORRECT)

    if sub == 0x01:  # Request Seed Level 1
        if _security_unlocked:
            log.info("SEC Seed requested: bereits unlocked -> zero-seed")
            return bytes([0x67, sub]) + bytes(4)
        _last_seed = secrets.token_bytes(4)
        log.info(f"SEED generated: {_last_seed.hex()}")
        return bytes([0x67, sub]) + _last_seed

    if sub == 0x02:  # Send Key Level 2
        # Bereits unlocked: Send-Key no-op (ISO 14229 "already unlocked" Semantik).
        # Begleitet den zero-seed-Response oben; Clients schicken oft trotzdem einen Key.
        if _security_unlocked:
            log.info("SEC Send-Key akzeptiert: bereits unlocked (no-op)")
            return bytes([0x67, sub])
        if _last_seed is None:
            return neg(SID_SECURITY, NRC_REQ_SEQ_ERROR)
        key = payload[2:]
        if len(key) != 4:
            return neg(SID_SECURITY, NRC_LEN)
        seed_int = int.from_bytes(_last_seed, "big")
        expected = (seed_int ^ KEY_MASK).to_bytes(4, "big")
        if key == expected:
            _security_unlocked = True
            _failed_attempts = 0
            _last_seed = None
            log.info("SEC -> Unlocked")
            return bytes([0x67, sub])
        _failed_attempts += 1
        _last_seed = None  # seed verbraucht, neuer Request Seed noetig
        if _failed_attempts >= MAX_FAILED:
            log.warning(f"SEC key falsch ({_failed_attempts}/{MAX_FAILED}) -> NRC 0x36")
            return neg(SID_SECURITY, NRC_EXCEEDED_ATTEMPTS)
        log.warning(f"SEC key falsch ({_failed_attempts}/{MAX_FAILED}) -> NRC 0x35")
        return neg(SID_SECURITY, NRC_INVALID_KEY)

    return neg(SID_SECURITY, NRC_SUB_FUNC_NOT_SUPPORTED)


def _handle_read(payload: bytes) -> bytes:
    if len(payload) < 3 or (len(payload) - 1) % 2 != 0:
        return neg(SID_READ, NRC_LEN)
    resp = bytearray([0x62])
    for i in range(1, len(payload), 2):
        did = (payload[i] << 8) | payload[i + 1]
        if did not in DIDS:
            return neg(SID_READ, NRC_OUT_OF_RANGE)
        resp.extend(struct.pack(">H", did))
        resp.extend(DIDS[did])
    return bytes(resp)


def _handle_write(payload: bytes) -> bytes:
    if len(payload) < 4:
        return neg(SID_WRITE, NRC_LEN)
    if not (_session_extended and _security_unlocked):
        log.info("WRITE abgelehnt: session_extended=%s unlocked=%s",
                 _session_extended, _security_unlocked)
        return neg(SID_WRITE, NRC_SEC_NOT_SATISFIED)
    did = (payload[1] << 8) | payload[2]
    data = payload[3:]
    if did not in WRITABLE_DIDS:
        return neg(SID_WRITE, NRC_OUT_OF_RANGE)
    # Lab-Regel: neue Payload muss gleiche Laenge haben wie die alte
    if len(data) != len(DIDS[did]):
        log.warning(f"WRITE 0x{did:04X} Laenge falsch: {len(data)} != {len(DIDS[did])}")
        return neg(SID_WRITE, NRC_LEN)
    DIDS[did] = bytes(data)
    log.info(f"WRITE 0x{did:04X} = {data.hex()} ({len(data)} bytes)")
    return bytes([0x6E, payload[1], payload[2]])


def handle(payload: bytes) -> bytes:
    if not payload:
        return b""
    sid = payload[0]
    log.info(f"<- Req SID=0x{sid:02X} data={payload.hex()}")
    if sid == SID_SESSION:
        return _handle_session(payload)
    if sid == SID_READ:
        return _handle_read(payload)
    if sid == SID_SECURITY:
        return _handle_security(payload)
    if sid == SID_WRITE:
        return _handle_write(payload)
    return neg(sid, NRC_SVC_NOT_SUPPORTED)


def main():
    log.info("UDS-Simulator auf vcan0 startet (T1+T2)")
    log.info(f"DIDs: {[f'0x{d:04X}' for d in DIDS]} | writable: {[f'0x{d:04X}' for d in WRITABLE_DIDS]}")
    bus = can.Bus(interface="socketcan", channel="vcan0")
    addr = isotp.Address(
        addressing_mode=isotp.AddressingMode.Normal_11bits,
        rxid=0x7E0,
        txid=0x7E8,
    )
    stack = isotp.CanStack(bus=bus, address=addr)
    stack.start()

    def shutdown(*_):
        log.info("Shutdown")
        stack.stop()
        bus.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    log.info("Ready - rxid=0x7E0 txid=0x7E8")
    while True:
        req = stack.recv(block=True, timeout=1.0)
        if req is None:
            continue
        resp = handle(req)
        if resp:
            stack.send(resp)
            log.info(f"-> Resp data={resp.hex()}")


if __name__ == "__main__":
    main()
