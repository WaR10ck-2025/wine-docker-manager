#!/opt/obd-monitor-venv/bin/python3
"""
UDS-Client (Stufe T1 + T2) — liest/schreibt DIDs am UDS-Simulator auf LXC 214.

Topologie:
    LXC 212 (obd-test, .212)  ──(TCP:28700)──▶  LXC 214 (udssim, .214)
        uds_client.py                                socketcand ◀─▶ vcan0
                                                     uds_server.py

CAN-IDs (normal 11-bit, mirror zwischen Client und Server):
    Client txid = 0x7E0   → Server rxid
    Client rxid = 0x7E8   ← Server txid

Modi:
    (default)           — liest alle DIDs aus der Registry ($22)
    --write DID=VALUE   — Session→Extended ($10 03), Security-Unlock ($27),
                          Write ($2E DID value), Re-Read ($22 DID) zur Verifikation
                          VALUE ist ASCII. Fuer raw hex: VALUE mit 'hex:'-Prefix.
                          Beispiele:
                              --write 0xF190=JS2NEWVIN99988776
                              --write 0xF40C=hex:2ee0
"""
import argparse
import logging
import struct
import sys

import can
import isotp
from udsoncan.client import Client
from udsoncan.connections import PythonIsoTpConnection
from udsoncan import DidCodec

log = logging.getLogger("uds-client")

KEY_MASK = 0xDEADBEEF


def fixed_codec(length: int) -> DidCodec:
    """Passthrough-Codec mit fester Laenge. udsoncan-Parser braucht __len__ zwingend.
    encode() akzeptiert str (ASCII) oder bytes; decode() liefert bytes."""
    class _C(DidCodec):
        def encode(self, val):
            if isinstance(val, bytes):
                return val
            if isinstance(val, str):
                return val.encode("ascii")
            return bytes(val)

        def decode(self, payload):
            return bytes(payload)

        def __len__(self):
            return length
    return _C()


DIDS = [
    (0xF190, "VIN",     17, "ascii"),
    (0xF195, "SW",       9, "ascii"),
    (0xF18C, "Serial",  15, "ascii"),
    (0xF40C, "Voltage",  2, "voltage"),
]
DID_BY_ID = {did: (label, length, kind) for did, label, length, kind in DIDS}


def format_did(kind: str, raw: bytes) -> str:
    if kind == "ascii":
        return raw.decode("ascii", errors="replace").rstrip("\x00")
    if kind == "voltage":
        if len(raw) != 2:
            return f"<raw:{raw.hex()}>"
        return f"{struct.unpack('>H', raw)[0] / 1000:.3f} V"
    return raw.hex()


def parse_write_arg(arg: str) -> tuple[int, bytes]:
    """'0xF190=JS2NEWVIN...' oder '0xF40C=hex:2ee0' → (did, payload_bytes)."""
    if "=" not in arg:
        raise ValueError(f"--write erwartet DID=VALUE, bekam: {arg}")
    did_str, val_str = arg.split("=", 1)
    did = int(did_str, 0)
    if val_str.startswith("hex:"):
        payload = bytes.fromhex(val_str[4:])
    else:
        payload = val_str.encode("ascii")
    return did, payload


def unlock_security(client: Client) -> None:
    """$10 03 Extended Session → $27 01 Request Seed → XOR-Key → $27 02 Send Key."""
    log.info("Session → Extended ($10 03)")
    client.change_session(0x03)

    log.info("Request Seed ($27 01)")
    resp = client.request_seed(0x01)
    seed = bytes(resp.service_data.seed)
    log.info(f"Seed:  {seed.hex()}")

    seed_int = int.from_bytes(seed, "big")
    key_int = seed_int ^ KEY_MASK
    key = key_int.to_bytes(4, "big")
    log.info(f"Key:   {key.hex()}  (= seed XOR 0x{KEY_MASK:08X})")

    log.info("Send Key ($27 02)")
    client.send_key(0x02, key)
    log.info("Security → Unlocked")


def read_all(client: Client) -> list[tuple[str, str]]:
    rows = []
    for did, label, _length, kind in DIDS:
        try:
            resp = client.read_data_by_identifier(did)
            raw = resp.service_data.values[did]
            rows.append((label, format_did(kind, raw)))
            log.debug(f"DID 0x{did:04X} ({label}) raw={raw.hex()}")
        except Exception as e:
            rows.append((label, f"<FAIL: {e}>"))
            log.error(f"DID 0x{did:04X} ({label}) fehlgeschlagen: {e}")
    return rows


def do_write(client: Client, did: int, new_value: bytes) -> tuple[str, str]:
    """Unlock → Write → Re-Read. Liefert (alt, neu) als lesbare Strings."""
    if did not in DID_BY_ID:
        raise ValueError(f"DID 0x{did:04X} nicht in Registry")
    label, length, kind = DID_BY_ID[did]
    if len(new_value) != length:
        raise ValueError(
            f"DID 0x{did:04X} ({label}) erwartet {length} bytes, bekam {len(new_value)}"
        )

    # Alten Wert lesen (ohne Unlock moeglich)
    log.info(f"Alt-Wert 0x{did:04X} ({label}) lesen...")
    old_raw = bytes(client.read_data_by_identifier(did).service_data.values[did])
    old_str = format_did(kind, old_raw)

    # Unlock-Flow
    unlock_security(client)

    # Write
    log.info(f"Write 0x{did:04X} = {new_value.hex()} ({len(new_value)} bytes)")
    client.write_data_by_identifier(did, new_value)

    # Re-Read zur Verifikation
    log.info(f"Re-Read 0x{did:04X}...")
    new_raw = bytes(client.read_data_by_identifier(did).service_data.values[did])
    new_str = format_did(kind, new_raw)

    if new_raw != new_value:
        raise RuntimeError(
            f"Re-Read-Mismatch: schrieb {new_value.hex()}, gelesen {new_raw.hex()}"
        )
    return old_str, new_str


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--host",    default="192.168.10.214", help="socketcand-Host (LXC 214)")
    p.add_argument("--port",    default=28700, type=int,   help="socketcand-TCP-Port")
    p.add_argument("--channel", default="vcan0",           help="CAN-Channel im Server-Namespace")
    p.add_argument("--txid",    default=0x7E0, type=lambda x: int(x, 0), help="Client->Server CAN-ID")
    p.add_argument("--rxid",    default=0x7E8, type=lambda x: int(x, 0), help="Server->Client CAN-ID")
    p.add_argument("--timeout", default=3.0, type=float,   help="UDS-Response-Timeout (s)")
    p.add_argument("--write",   action="append", default=[],
                   help="DID=VALUE (ASCII) oder DID=hex:XXXX. Mehrfach moeglich.")
    p.add_argument("--debug",   action="store_true")
    args = p.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.debug else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )

    writes = [parse_write_arg(w) for w in args.write]

    log.info(f"Connect: socketcand://{args.host}:{args.port}/{args.channel}")
    bus = can.Bus(
        interface="socketcand",
        host=args.host,
        port=args.port,
        channel=args.channel,
    )

    addr = isotp.Address(
        addressing_mode=isotp.AddressingMode.Normal_11bits,
        rxid=args.rxid,
        txid=args.txid,
    )
    stack = isotp.CanStack(bus=bus, address=addr)
    conn = PythonIsoTpConnection(stack)

    config = {
        "exception_on_negative_response": True,
        "exception_on_invalid_response":  True,
        "exception_on_unexpected_response": True,
        "data_identifiers": {did: fixed_codec(length) for did, _, length, _ in DIDS},
        "security_algo": lambda level, seed, params: (
            int.from_bytes(seed, "big") ^ KEY_MASK
        ).to_bytes(4, "big"),
    }

    exit_code = 0
    try:
        with Client(conn, request_timeout=args.timeout, config=config) as client:
            if writes:
                # WRITE-MODE
                results = []
                for did, new_val in writes:
                    try:
                        old_s, new_s = do_write(client, did, new_val)
                        results.append((did, True, old_s, new_s, None))
                    except Exception as e:
                        results.append((did, False, None, None, str(e)))
                        log.error(f"Write DID 0x{did:04X} fehlgeschlagen: {e}")
                        exit_code = 1

                print()
                print(f"UDS-Write via {args.host}:{args.port} ({args.channel})")
                print("─" * 70)
                for did, ok, old_s, new_s, err in results:
                    label = DID_BY_ID[did][0] if did in DID_BY_ID else "?"
                    if ok:
                        print(f"  ✓ 0x{did:04X} ({label}):")
                        print(f"      alt: {old_s}")
                        print(f"      neu: {new_s}")
                    else:
                        print(f"  ✗ 0x{did:04X} ({label}): {err}")
                print()
            else:
                # READ-ONLY-MODE (T1)
                rows = read_all(client)
                print()
                print(f"UDS-Lesen via {args.host}:{args.port} ({args.channel})")
                print("─" * 55)
                for label, val in rows:
                    print(f"  {label:<10}: {val}")
                print()
                failed = sum(1 for _, v in rows if v.startswith("<FAIL"))
                exit_code = 1 if failed else 0
    finally:
        bus.shutdown()

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
