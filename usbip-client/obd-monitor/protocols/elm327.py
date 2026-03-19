"""
ELM327-Protokoll-Adapter (nutzt python-obd Bibliothek).

Wird als erstes versucht — manche CDP+ Klone haben ELM327-Firmware.
Bei Misserfolg: Fallback auf iso9141.py
"""
import logging
import time
from typing import Optional

import serial

from .base import DTC, OBDProtocol, OBDReading

log = logging.getLogger(__name__)


def probe(port: str, timeout: float = 2.0) -> bool:
    """
    Prüft ob das Gerät auf ELM327 AT-Commands reagiert.
    Gibt True zurück wenn ELM327-Response erkannt wird.
    """
    try:
        with serial.Serial(port, 38400, timeout=timeout) as ser:
            ser.reset_input_buffer()
            ser.write(b"ATZ\r")
            time.sleep(timeout)
            response = ser.read(200).decode(errors="replace")
            found = "ELM327" in response or "ELM" in response
            if found:
                log.info(f"ELM327 erkannt auf {port}")
            return found
    except Exception as e:
        log.debug(f"ELM327 probe fehlgeschlagen: {e}")
        return False


class ELM327Protocol(OBDProtocol):
    """OBD2 via ELM327 (python-obd Bibliothek)."""

    def __init__(self):
        self._conn = None

    def connect(self, port: str) -> bool:
        try:
            import obd
            self._conn = obd.OBD(port, fast=False, timeout=5)
            return self._conn.is_connected()
        except Exception as e:
            log.error(f"ELM327 connect fehlgeschlagen: {e}")
            return False

    def _query(self, cmd) -> Optional[float]:
        try:
            import obd
            r = self._conn.query(cmd)
            if r.value is None:
                return None
            # python-obd gibt Pint-Quantities zurück
            val = r.value
            return float(val.magnitude) if hasattr(val, "magnitude") else float(val)
        except Exception:
            return None

    def read_data(self) -> OBDReading:
        if not self._conn:
            return OBDReading()
        import obd
        return OBDReading(
            rpm=self._query(obd.commands.RPM),
            speed=self._query(obd.commands.SPEED),
            coolant_temp=self._query(obd.commands.COOLANT_TEMP),
            throttle=self._query(obd.commands.THROTTLE_POS),
            engine_load=self._query(obd.commands.ENGINE_LOAD),
            short_fuel_trim=self._query(obd.commands.SHORT_FUEL_TRIM_1),
            long_fuel_trim=self._query(obd.commands.LONG_FUEL_TRIM_1),
        )

    def read_dtcs(self) -> list[DTC]:
        if not self._conn:
            return []
        try:
            import obd
            r = self._conn.query(obd.commands.GET_DTC)
            if not r.value:
                return []
            return [DTC(code=d[0], description=d[1] or "") for d in r.value]
        except Exception:
            return []

    def clear_dtcs(self) -> bool:
        if not self._conn:
            return False
        try:
            import obd
            self._conn.query(obd.commands.CLEAR_DTC)
            return True
        except Exception:
            return False

    def disconnect(self):
        if self._conn:
            self._conn.close()
            self._conn = None

    def is_connected(self) -> bool:
        return self._conn is not None and self._conn.is_connected()

    @property
    def protocol_name(self) -> str:
        return "elm327"
