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

# ── Seed2Key-Algo-Registry (synchron zu udssim/uds_server.py) ───────────────
KEY_MASK_DEFAULT = 0xDEADBEEF

def _algo_xor_deadbeef(seed: bytes) -> bytes:
    return (int.from_bytes(seed, "big") ^ KEY_MASK_DEFAULT).to_bytes(4, "big")

def _algo_volvo_vcc_mock(seed: bytes) -> bytes:
    s = int.from_bytes(seed, "big") & 0xFFFFFFFF
    rotated = ((s << 1) | (s >> 31)) & 0xFFFFFFFF
    return (rotated ^ 0xA5A55A5A).to_bytes(4, "big")

def _algo_vag_kw1281_mock(seed: bytes) -> bytes:
    s = int.from_bytes(seed, "big")
    k = (s * 0x1337 + 0xCAFE) & 0xFFFFFFFF
    return k.to_bytes(4, "big")

SEED2KEY_ALGOS = {
    "xor_deadbeef":   _algo_xor_deadbeef,
    "volvo_vcc_mock": _algo_volvo_vcc_mock,
    "vag_kw1281_mock": _algo_vag_kw1281_mock,
}

# Backward-compat: alter KEY_MASK-Name bleibt importierbar.
KEY_MASK = KEY_MASK_DEFAULT


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


def unlock_security(client: Client, algo_name: str = "xor_deadbeef") -> None:
    """$10 03 Extended Session → $27 01 Request Seed → Algo-Key → $27 02 Send Key."""
    compute = SEED2KEY_ALGOS[algo_name]
    log.info("Session → Extended ($10 03)")
    client.change_session(0x03)

    log.info("Request Seed ($27 01)")
    resp = client.request_seed(0x01)
    seed = bytes(resp.service_data.seed)
    log.info(f"Seed:  {seed.hex()}")

    key = compute(seed)
    log.info(f"Key:   {key.hex()}  (via algo={algo_name})")

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


def do_write(client: Client, did: int, new_value: bytes, algo_name: str = "xor_deadbeef") -> tuple[str, str]:
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
    unlock_security(client, algo_name)

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


ADAPTER_PROFILES = {
    # LXC-UDS-Simulator (Lab-Default, T1+T2)
    "udssim":    {"host": "192.168.10.214", "port": 28700, "channel": "vcan0",
                  "txid": 0x7E0, "rxid": 0x7E8, "stmin": 0, "blocksize": 0},
    # WiCAN Pro am GL.iNet Router, SocketCAN-TCP auf Port 3333 (Pfad B, echtes Auto)
    "wican-pro": {"host": "192.168.10.200", "port": 3333, "channel": "can0",
                  "txid": 0x7E0, "rxid": 0x7E8, "stmin": 0, "blocksize": 0},
    # Generisches TCP-Profil — alles explizit via CLI setzen
    "tcp":       {"host": "",                "port": 3333, "channel": "can0",
                  "txid": 0x7E0, "rxid": 0x7E8, "stmin": 0, "blocksize": 0},
}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--adapter", default="udssim", choices=sorted(ADAPTER_PROFILES),
                   help="Adapter-Profil. udssim=LXC Lab, wican-pro=WiCAN Pro am Router, tcp=generisch")
    p.add_argument("--host",    default=None,       help="Override: socketcand-Host (Profil-default)")
    p.add_argument("--port",    default=None, type=int, help="Override: socketcand-TCP-Port")
    p.add_argument("--channel", default=None,       help="Override: CAN-Channel")
    p.add_argument("--txid",    default=None, type=lambda x: int(x, 0), help="Override: Client->Server CAN-ID")
    p.add_argument("--rxid",    default=None, type=lambda x: int(x, 0), help="Override: Server->Client CAN-ID")
    p.add_argument("--timeout", default=3.0, type=float, help="UDS-Response-Timeout (s)")
    p.add_argument("--seed-algo", default="xor_deadbeef", choices=sorted(SEED2KEY_ALGOS),
                   help="Seed->Key-Algo (muss zum Server-Setup passen). Default: xor_deadbeef")
    p.add_argument("--write",   action="append", default=[],
                   help="DID=VALUE (ASCII) oder DID=hex:XXXX. Mehrfach moeglich.")
    p.add_argument("--debug",   action="store_true")
    args = p.parse_args()

    # Profil laden + CLI-Overrides anwenden
    profile = dict(ADAPTER_PROFILES[args.adapter])
    for k in ("host", "port", "channel", "txid", "rxid"):
        v = getattr(args, k)
        if v is not None:
            profile[k] = v
    if not profile["host"]:
        p.error(f"--adapter={args.adapter} hat keinen Default-Host; --host erforderlich")

    logging.basicConfig(
        level=logging.DEBUG if args.debug else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )

    writes = [parse_write_arg(w) for w in args.write]
    compute_key = SEED2KEY_ALGOS[args.seed_algo]

    log.info("Adapter: %s → socketcand://%s:%d/%s (algo=%s)",
             args.adapter, profile["host"], profile["port"], profile["channel"], args.seed_algo)
    bus = can.Bus(
        interface="socketcand",
        host=profile["host"],
        port=profile["port"],
        channel=profile["channel"],
    )

    addr = isotp.Address(
        addressing_mode=isotp.AddressingMode.Normal_11bits,
        rxid=profile["rxid"],
        txid=profile["txid"],
    )
    stack = isotp.CanStack(
        bus=bus, address=addr,
        params={"stmin": profile["stmin"], "blocksize": profile["blocksize"]},
    )
    conn = PythonIsoTpConnection(stack)

    config = {
        "exception_on_negative_response": True,
        "exception_on_invalid_response":  True,
        "exception_on_unexpected_response": True,
        "data_identifiers": {did: fixed_codec(length) for did, _, length, _ in DIDS},
        "security_algo": lambda level, seed, params: compute_key(bytes(seed)),
    }

    exit_code = 0
    try:
        with Client(conn, request_timeout=args.timeout, config=config) as client:
            if writes:
                # WRITE-MODE
                results = []
                for did, new_val in writes:
                    try:
                        old_s, new_s = do_write(client, did, new_val, args.seed_algo)
                        results.append((did, True, old_s, new_s, None))
                    except Exception as e:
                        results.append((did, False, None, None, str(e)))
                        log.error(f"Write DID 0x{did:04X} fehlgeschlagen: {e}")
                        exit_code = 1

                print()
                print(f"UDS-Write via {profile['host']}:{profile['port']} ({profile['channel']}, {args.adapter})")
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
                print(f"UDS-Lesen via {profile['host']}:{profile['port']} ({profile['channel']}, {args.adapter})")
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
