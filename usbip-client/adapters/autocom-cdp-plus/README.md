# Autocom CDP+ — OBD2 Adapter (Standard)

## Übersicht

Der **Autocom CDP+ (Multi-Diag)** ist der primäre Adapter dieses Projekts.

| Eigenschaft         | Wert                                      |
|---------------------|-------------------------------------------|
| USB VID:PID         | `0403:d6da`                               |
| Chipset             | FTDI FT232R                               |
| Linux-Treiber       | ✅ `ftdi_sio` (Kernel built-in)           |
| Protokoll           | ISO 9141-2 / K-Line (seriell)             |
| python-obd          | ✅ Direkt via `pyserial`                  |
| FastAPI OBD2        | ✅ Direkt (`obd_service.py`)              |
| Multi-Marken        | ✅ Alle OBD2-Fahrzeuge (ab ~1996)         |
| Volvo Tiefdiagnose  | ❌ Nur Standard-OBD2 PIDs                 |

## Warum CDP+ für dieses Projekt

1. **Linux-nativ** → kein Windows-VM nötig, läuft direkt auf dem GL.iNet Router
2. **python-obd Integration** → `from obd import OBD; obd.connect('/dev/ttyUSB0')`
3. **FastAPI direkt** → `obd_service.py` schreibt Live-Daten auf Port 8765
4. **Multi-Marken** → Suzuki Wagon R+ 2004 + alle OBD2-Fahrzeuge
5. **USB/IP Standard** → FTDI wird wie jedes andere USB-Serial-Gerät exportiert

## Verwendung

```bash
# Auf GL.iNet Router deployen
cp adapter.conf /etc/obd-adapter.conf
/etc/init.d/usbipd restart

# Auf Windows (usbipd-win):
usbipd list
usbipd bind --busid X-X
usbipd attach --wsl --busid X-X

# Verify
obd-ctl adapter
obd-ctl bind
```

## Python-Integration (auf dem Router)

```python
import obd
connection = obd.OBD('/dev/ttyUSB0')  # CDP+ erscheint als ttyUSB0

rpm = connection.query(obd.commands.RPM)
speed = connection.query(obd.commands.SPEED)
print(f"RPM: {rpm.value}, Speed: {speed.value}")
```

## Limitierungen

- Nur Standard OBD2 PIDs (Mode 01, 03, 04, 09)
- Keine herstellerspezifischen Codes (VAG, Volvo, etc.)
- Kein J2534 Passthru-Protokoll
- Für Volvo Tiefdiagnose: GODIAG GD101 verwenden
