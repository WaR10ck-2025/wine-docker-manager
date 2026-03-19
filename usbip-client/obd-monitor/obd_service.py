#!/usr/bin/env python3
"""
OBD2 Micro-Service — FastAPI auf Port 8765

Läuft auf dem Mini-PC und stellt OBD-Daten als HTTP-API bereit.
Der Manager auf dem Umbrel-Server proxyt die Anfragen hierher.

Start:
  uvicorn obd_service:app --host 0.0.0.0 --port 8765
"""
import asyncio
import json
import logging
import threading
import time
from typing import AsyncGenerator, Optional

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

from protocols.base import DTC, OBDReading
from protocols.elm327 import ELM327Protocol, probe as elm327_probe
from protocols.iso9141 import ISO9141Protocol, _find_port

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(name)s: %(message)s")
log = logging.getLogger(__name__)

app = FastAPI(title="OBD2 Monitor Service", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Globaler Protokoll-State ─────────────────────────────────────────────────
_proto = None
_port: Optional[str] = None
_reading = OBDReading()
_error: Optional[str] = None
_lock = threading.Lock()


def _connect_once():
    """Verbindet beim Service-Start (läuft im Background-Thread)."""
    global _proto, _port, _error

    target = _find_port()
    if not target:
        _error = "Kein serieller Port gefunden (/dev/ttyUSB*)"
        log.error(_error)
        return

    _port = target

    # ELM327 zuerst probieren
    if elm327_probe(target):
        proto = ELM327Protocol()
        if proto.connect(target):
            with _lock:
                _proto = proto
            log.info(f"ELM327 verbunden auf {target}")
            return

    # ISO 9141-2 direkt
    proto = ISO9141Protocol()
    if proto.connect(target):
        with _lock:
            _proto = proto
        log.info(f"ISO 9141-2 verbunden auf {target}")
        return

    _error = f"Verbindung fehlgeschlagen auf {target} (ELM327 + ISO 9141-2)"
    log.error(_error)


def _poll_loop():
    """Liest OBD-Daten alle 500ms (Background-Thread)."""
    global _reading
    while True:
        with _lock:
            if _proto and _proto.is_connected():
                _reading = _proto.read_data()
        time.sleep(0.5)


# Beim Start des Services verbinden + Poll-Loop starten
threading.Thread(target=_connect_once, daemon=True).start()
threading.Thread(target=_poll_loop, daemon=True).start()


# ── Endpoints ────────────────────────────────────────────────────────────────

@app.get("/obd/status")
def obd_status():
    """Verbindungsstatus und Protokoll-Info."""
    with _lock:
        connected = _proto is not None and _proto.is_connected()
        protocol = _proto.protocol_name if _proto else None
    return {
        "connected": connected,
        "protocol": protocol,
        "port": _port,
        "error": _error if not connected else None,
    }


@app.get("/obd/data")
def obd_data():
    """Aktueller OBD2-Datensatz (Snapshot)."""
    r = _reading
    return {
        "rpm": r.rpm,
        "speed": r.speed,
        "coolant_temp": r.coolant_temp,
        "throttle": r.throttle,
        "engine_load": r.engine_load,
        "short_fuel_trim": r.short_fuel_trim,
        "long_fuel_trim": r.long_fuel_trim,
        "battery_voltage": r.battery_voltage,
        "timestamp_ms": r.timestamp_ms,
    }


@app.get("/obd/dtcs")
def obd_dtcs():
    """Gespeicherte Fehlercodes (DTCs) lesen."""
    with _lock:
        if _proto and _proto.is_connected():
            codes = _proto.read_dtcs()
        else:
            codes = []
    return {
        "codes": [{"code": d.code, "description": d.description} for d in codes],
        "count": len(codes),
    }


@app.post("/obd/clear-dtcs")
def obd_clear_dtcs():
    """Gespeicherte Fehlercodes löschen (Mode 04)."""
    with _lock:
        if not _proto or not _proto.is_connected():
            return {"success": False, "message": "Nicht verbunden"}
        success = _proto.clear_dtcs()
    return {
        "success": success,
        "message": "Fehlercodes gelöscht ✓" if success else "Löschen fehlgeschlagen",
    }


@app.get("/obd/stream")
async def obd_stream():
    """SSE-Stream: sendet OBD-Daten ~2x pro Sekunde."""
    async def generator() -> AsyncGenerator[str, None]:
        while True:
            r = _reading
            data = {
                "rpm": r.rpm,
                "speed": r.speed,
                "coolant_temp": r.coolant_temp,
                "throttle": r.throttle,
                "engine_load": r.engine_load,
                "short_fuel_trim": r.short_fuel_trim,
                "long_fuel_trim": r.long_fuel_trim,
                "battery_voltage": r.battery_voltage,
                "timestamp_ms": r.timestamp_ms,
            }
            yield f"data: {json.dumps(data)}\n\n"
            await asyncio.sleep(0.5)

    return StreamingResponse(generator(), media_type="text/event-stream")


@app.get("/health")
def health():
    return {"status": "ok"}
