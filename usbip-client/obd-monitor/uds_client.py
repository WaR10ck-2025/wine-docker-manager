#!/opt/obd-monitor-venv/bin/python3
"""
UDS-Client (Stufe T1) — liest DIDs vom UDS-Simulator auf LXC 214 ueber socketcand.

Topologie:
    LXC 212 (obd-test, .212)  ──(TCP:28700)──▶  LXC 214 (udssim, .214)
        uds_client.py                                socketcand ◀─▶ vcan0
                                                     uds_server.py

CAN-IDs (normal 11-bit, mirror zwischen Client und Server):
    Client txid = 0x7E0   → Server rxid
    Client rxid = 0x7E8   ← Server txid

Service $22 ReadDataByIdentifier, gelesene DIDs:
    0xF190 VIN  |  0xF195 SW-Version  |  0xF18C Serial  |  0xF40C Voltage
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


def fixed_codec(length: int) -> DidCodec:
    """Passthrough-Codec mit fester Laenge. udsoncan-Parser braucht __len__ zwingend."""
    class _C(DidCodec):
        def encode(self, val): return val if isinstance(val, bytes) else bytes(val)
        def decode(self, payload): return bytes(payload)
        def __len__(self): return length
    return _C()


DIDS = [
    (0xF190, "VIN",     17, "ascii"),
    (0xF195, "SW",       9, "ascii"),
    (0xF18C, "Serial",  15, "ascii"),
    (0xF40C, "Voltage",  2, "voltage"),
]


def format_did(kind: str, raw: bytes) -> str:
    if kind == "ascii":
        return raw.decode("ascii", errors="replace").rstrip("\x00")
    if kind == "voltage":
        if len(raw) != 2:
            return f"<raw:{raw.hex()}>"
        return f"{struct.unpack('>H', raw)[0] / 1000:.3f} V"
    return raw.hex()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--host",    default="192.168.10.214", help="socketcand-Host (LXC 214)")
    p.add_argument("--port",    default=28700, type=int,   help="socketcand-TCP-Port")
    p.add_argument("--channel", default="vcan0",           help="CAN-Channel im Server-Namespace")
    p.add_argument("--txid",    default=0x7E0, type=lambda x: int(x, 0), help="Client->Server CAN-ID")
    p.add_argument("--rxid",    default=0x7E8, type=lambda x: int(x, 0), help="Server->Client CAN-ID")
    p.add_argument("--timeout", default=3.0, type=float,   help="UDS-Response-Timeout (s)")
    p.add_argument("--debug",   action="store_true")
    args = p.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.debug else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )

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
    }

    rows = []
    try:
        with Client(conn, request_timeout=args.timeout, config=config) as client:
            for did, label, _length, kind in DIDS:
                try:
                    resp = client.read_data_by_identifier(did)
                    raw = resp.service_data.values[did]
                    rows.append((label, format_did(kind, raw)))
                    log.debug(f"DID 0x{did:04X} ({label}) raw={raw.hex()}")
                except Exception as e:
                    rows.append((label, f"<FAIL: {e}>"))
                    log.error(f"DID 0x{did:04X} ({label}) fehlgeschlagen: {e}")
    finally:
        bus.shutdown()

    print()
    print(f"UDS-Lesen via {args.host}:{args.port} ({args.channel})")
    print("─" * 55)
    for label, val in rows:
        print(f"  {label:<10}: {val}")
    print()

    failed = sum(1 for _, v in rows if v.startswith("<FAIL"))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
