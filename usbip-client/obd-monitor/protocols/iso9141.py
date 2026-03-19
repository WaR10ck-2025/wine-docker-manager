"""
Direkte ISO 9141-2 (K-Line) Implementierung via pyserial.

Fallback wenn ELM327 nicht antwortet — für den echten Autocom CDP+ (FTDI-Bridge).

Technisches Detail:
  Der CDP+ FTDI-Chip ist eine transparente USB-UART Bridge. Durch Bit-Banging
  über break_condition kann das 5-Baud Init-Byte direkt gesendet werden.
"""
import glob
import logging
import time
from typing import Optional

import serial

from .base import DTC, OBDProtocol, OBDReading

log = logging.getLogger(__name__)

# ISO 9141-2 Konstanten
BAUD_OBD     = 10400
ADDR_INIT    = 0x33   # Initalisierungs-Adresse (ISO 9141-2 §6.2)
ADDR_TESTER  = 0xF1   # Tester-Adresse
ADDR_ECU     = 0x10   # ECU Funktions-Adresse (Broadcast)

# OBD2 Frame Header: [68 6A F1] = Phys. Adresse, Ziel=ECU-Broadcast, Quelle=Tester
HEADER = bytes([0x68, 0x6A, ADDR_TESTER])


def _checksum(data: bytes) -> int:
    return sum(data) & 0xFF


def _find_port() -> Optional[str]:
    """Findet den FTDI CDP+ Port automatisch via sysfs."""
    # Zuerst: FTDI 0403:d6da via sysfs identifizieren
    for path in sorted(glob.glob("/dev/ttyUSB*")):
        name = path.split("/")[-1]
        for uevent_path in [
            f"/sys/bus/usb-serial/devices/{name}/../uevent",
            f"/sys/class/tty/{name}/device/../uevent",
        ]:
            try:
                with open(uevent_path) as f:
                    content = f.read()
                    if "403/d6da" in content or "0403/d6da" in content:
                        log.info(f"FTDI CDP+ (0403:d6da) gefunden: {path}")
                        return path
            except OSError:
                continue

    # Fallback: erster verfügbarer ttyUSB Port
    candidates = sorted(glob.glob("/dev/ttyUSB*"))
    if candidates:
        log.info(f"Port Fallback (erster ttyUSB): {candidates[0]}")
        return candidates[0]

    return None


def _send_5baud_address(ser: serial.Serial, address: int = ADDR_INIT) -> None:
    """
    Sendet ein Byte bei ~5 Baud durch Bit-Banging via BREAK-Condition.

    Jedes Bit dauert 200ms (= 1/5 Sekunde = 5 Baud).
    Sequenz: Start-Bit (LOW) + 8 Datenbits LSB-first + Stop-Bit (HIGH)

    break_condition=True  → TxD LOW  (BREAK / 0-Bit)
    break_condition=False → TxD HIGH (Idle  / 1-Bit)
    """
    log.debug(f"5-Baud Init: Sende 0x{address:02X} ({address:08b}) auf {ser.port}...")

    # Start-Bit: LOW (200ms)
    ser.break_condition = True
    time.sleep(0.2)

    # 8 Datenbits LSB-first
    for i in range(8):
        bit = (address >> i) & 1
        ser.break_condition = (bit == 0)  # LOW für 0-Bit, HIGH für 1-Bit
        time.sleep(0.2)

    # Stop-Bit: HIGH (idle, 200ms)
    ser.break_condition = False
    time.sleep(0.2)

    log.debug("5-Baud Init: Adress-Byte gesendet")


class ISO9141Protocol(OBDProtocol):
    """
    ISO 9141-2 Protokoll via direktem UART-Zugriff auf den FTDI CDP+.

    Init-Sequenz (ISO 9141-2 §6.3.1):
      1. Adress-Byte 0x33 bei 5 Baud senden
      2. Sync-Byte 0x55 empfangen
      3. Keyword-Bytes W1, W2 empfangen
      4. ~W2 (invertiert) zurückschicken (< 25ms!)
      5. Bestätigung 0xCC empfangen
      → Session offen, OBD2 Frames möglich
    """

    def __init__(self):
        self._ser: Optional[serial.Serial] = None
        self._port: Optional[str] = None
        self._connected = False

    def connect(self, port: Optional[str] = None) -> bool:
        self._port = port or _find_port()
        if not self._port:
            log.error("Kein serieller Port gefunden")
            return False
        try:
            return self._init_session()
        except Exception as e:
            log.error(f"ISO 9141-2 Connect fehlgeschlagen: {e}")
            if self._ser and self._ser.is_open:
                self._ser.close()
            return False

    def _init_session(self) -> bool:
        """Führt die vollständige ISO 9141-2 5-Baud Slow-Init Sequenz durch."""
        log.info(f"ISO 9141-2 Init auf {self._port} ({BAUD_OBD} Baud)...")

        self._ser = serial.Serial(
            self._port,
            baudrate=BAUD_OBD,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=3,
        )
        self._ser.reset_input_buffer()

        # 1. Adress-Byte bei 5 Baud senden
        _send_5baud_address(self._ser, ADDR_INIT)

        # 2. Echo-Bytes verwerfen, auf Sync-Byte 0x55 warten
        time.sleep(0.05)
        self._ser.reset_input_buffer()

        sync = self._ser.read(1)
        if not sync or sync[0] != 0x55:
            log.error(f"Kein Sync-Byte 0x55: empfangen={sync.hex() if sync else 'timeout'}")
            self._ser.close()
            return False
        log.debug("Sync 0x55 empfangen ✓")

        # 3. Keyword-Bytes W1, W2 lesen
        keywords = self._ser.read(2)
        if len(keywords) < 2:
            log.error(f"Keyword-Bytes fehlen: nur {len(keywords)} Bytes empfangen")
            self._ser.close()
            return False
        w1, w2 = keywords[0], keywords[1]
        log.debug(f"Keywords: W1=0x{w1:02X} W2=0x{w2:02X}")

        # 4. ~W2 (invertiertes W2) sofort zurückschicken (< 25ms!)
        inverted_w2 = (~w2) & 0xFF
        self._ser.write(bytes([inverted_w2]))
        log.debug(f"~W2 = 0x{inverted_w2:02X} gesendet")

        # 5. Bestätigungs-Byte 0xCC lesen (optional — manche ECUs senden es nicht)
        self._ser.timeout = 0.5
        confirm = self._ser.read(1)
        self._ser.timeout = 2.0
        if confirm and confirm[0] == 0xCC:
            log.debug("Bestätigung 0xCC empfangen ✓")
        else:
            log.debug(f"Bestätigung fehlt: {confirm.hex() if confirm else 'timeout'} (wird ignoriert)")

        self._connected = True
        log.info("ISO 9141-2 Session geöffnet ✓")
        return True

    def _send_request(self, mode: int, pid: int) -> Optional[bytes]:
        """
        Sendet einen OBD2 Mode-1 Request und liest die Antwort.
        Frame: [68 6A F1] [Mode] [PID] [Checksum]
        """
        if not self._ser or not self._connected:
            return None

        frame = HEADER + bytes([mode, pid])
        frame += bytes([_checksum(frame)])

        try:
            self._ser.reset_input_buffer()
            self._ser.write(frame)
            time.sleep(0.05)

            # Antwort lesen: bis zu 20 Bytes
            response = self._ser.read(20)
            if not response:
                return None

            # Echo-Bytes (eigene gesendete Bytes) überspringen
            if response[:len(frame)] == frame:
                response = response[len(frame):]

            # Response-Header [48 6B xx] überspringen (falls vorhanden)
            if len(response) >= 3 and response[0] == 0x48:
                response = response[3:]

            return response if response else None

        except serial.SerialException as e:
            log.error(f"Serial-Fehler bei Mode 0x{mode:02X} PID 0x{pid:02X}: {e}")
            self._connected = False
            return None

    def _decode_pid(self, pid: int, data: bytes) -> Optional[float]:
        """Dekodiert OBD2 PID-Antworten in physikalische Werte."""
        if not data:
            return None

        a = data[0] if len(data) > 0 else 0
        b = data[1] if len(data) > 1 else 0

        decoders = {
            0x0C: lambda: ((a * 256) + b) / 4,        # RPM
            0x0D: lambda: float(a),                     # Speed km/h
            0x05: lambda: float(a) - 40,                # Coolant Temp °C
            0x11: lambda: (a / 255) * 100,              # Throttle %
            0x04: lambda: (a / 255) * 100,              # Engine Load %
            0x06: lambda: (a / 128 - 1) * 100,          # Short Fuel Trim %
            0x07: lambda: (a / 128 - 1) * 100,          # Long Fuel Trim %
            0x42: lambda: ((a * 256) + b) / 1000,       # Battery Voltage V
        }

        decoder = decoders.get(pid)
        if decoder:
            try:
                return round(decoder(), 2)
            except Exception:
                return None
        return None

    def _query_pid(self, pid: int) -> Optional[float]:
        """Fragt einen einzelnen OBD2 PID ab und dekodiert den Wert."""
        response = self._send_request(0x01, pid)
        if not response or len(response) < 3:
            return None

        # Erwartete Antwort: [41] [PID] [Daten...]
        if response[0] == 0x41 and response[1] == pid:
            return self._decode_pid(pid, response[2:])
        return None

    def read_data(self) -> OBDReading:
        if not self._connected:
            return OBDReading()
        return OBDReading(
            rpm=self._query_pid(0x0C),
            speed=self._query_pid(0x0D),
            coolant_temp=self._query_pid(0x05),
            throttle=self._query_pid(0x11),
            engine_load=self._query_pid(0x04),
            short_fuel_trim=self._query_pid(0x06),
            long_fuel_trim=self._query_pid(0x07),
            battery_voltage=self._query_pid(0x42),
        )

    def read_dtcs(self) -> list[DTC]:
        """Mode 03: Gespeicherte Fehlercodes lesen."""
        if not self._ser or not self._connected:
            return []
        try:
            frame = bytes([0x68, 0x6A, 0xF1, 0x03])
            frame += bytes([_checksum(frame)])

            self._ser.reset_input_buffer()
            self._ser.write(frame)
            time.sleep(0.5)

            response = self._ser.read(64)
            dtcs = []

            # DTCs dekodieren: je 2 Bytes pro Code
            i = 0
            while i + 1 < len(response):
                b1, b2 = response[i], response[i + 1]
                if b1 == 0x00 and b2 == 0x00:
                    break
                # DTC-Typ aus oberen 2 Bits von Byte 1
                prefix = {0: "P", 1: "C", 2: "B", 3: "U"}[(b1 >> 6) & 0x03]
                code = f"{prefix}{(b1 & 0x3F):X}{b2:02X}"
                dtcs.append(DTC(code=code))
                i += 2

            return dtcs
        except Exception as e:
            log.error(f"DTC-Lesen fehlgeschlagen: {e}")
            return []

    def clear_dtcs(self) -> bool:
        """Mode 04: Gespeicherte Fehlercodes löschen."""
        if not self._ser or not self._connected:
            return False
        try:
            frame = bytes([0x68, 0x6A, 0xF1, 0x04])
            frame += bytes([_checksum(frame)])
            self._ser.write(frame)
            time.sleep(0.5)
            return True
        except Exception:
            return False

    def disconnect(self):
        self._connected = False
        if self._ser and self._ser.is_open:
            self._ser.close()
        self._ser = None

    def is_connected(self) -> bool:
        return self._connected and self._ser is not None and self._ser.is_open

    @property
    def protocol_name(self) -> str:
        return "iso9141"
