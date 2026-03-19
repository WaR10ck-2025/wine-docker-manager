"""
Abstrakte Basisklasse und PID-Definitionen für OBD2-Protokolle.
"""
import time
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class OBDReading:
    rpm: Optional[float] = None
    speed: Optional[float] = None
    coolant_temp: Optional[float] = None
    throttle: Optional[float] = None
    engine_load: Optional[float] = None
    short_fuel_trim: Optional[float] = None
    long_fuel_trim: Optional[float] = None
    battery_voltage: Optional[float] = None
    timestamp_ms: int = field(default_factory=lambda: int(time.time() * 1000))


@dataclass
class DTC:
    code: str
    description: str = ""


class OBDProtocol:
    """Abstrakte Basisklasse für OBD2-Protokoll-Adapter."""

    def connect(self, port: str) -> bool:
        raise NotImplementedError

    def read_data(self) -> OBDReading:
        raise NotImplementedError

    def read_dtcs(self) -> list[DTC]:
        raise NotImplementedError

    def clear_dtcs(self) -> bool:
        raise NotImplementedError

    def disconnect(self):
        raise NotImplementedError

    def is_connected(self) -> bool:
        raise NotImplementedError

    @property
    def protocol_name(self) -> str:
        raise NotImplementedError
