# WiCAN Pro — ★★ WiFi + J2534 + Linux (Pfad B)

## Übersicht

Der **WiCAN Pro** (MeatPi Electronics, ESP32-C3) ist die einzige bekannte
Consumer-Hardware die alle drei Anforderungen gleichzeitig erfüllt:

| Anforderung | Status |
|---|---|
| WiFi-Verbindung (kabellos) | ✅ WiFi + BLE |
| J2534-Konformität | ✅ Custom J2534-DLL + SocketCAN |
| Linux-Support | ✅ SocketCAN nativ |

| Eigenschaft | Wert |
|---|---|
| Chipset | ESP32-C3 |
| Verbindung | WiFi 2.4G + BLE + USB |
| Protokoll | J2534-1, SocketCAN, ELM327, MQTT |
| Linux-Treiber | ✅ SocketCAN via TCP (kein Kernel-Modul nötig) |
| python-obd | ✅ via python-can + udsoncan |
| Volvo VIDA/vdash | ⚠️ Nicht direkt (kein Windows-J2534-DLL), UDS via udsoncan |
| USB/IP-fähig | ⚠️ Nicht nötig (WiFi-Bridge-Pfad) |
| Firmware | Open-Source (GitHub: meatpiHQ/wican-fw) |
| Home Assistant | ✅ Native Integration |
| Preis | ~€50–80 (AliExpress / Crowd Supply) |

---

## Architektur: Pfad B — WiFi-Bridge

```
[Pfad A: USB/IP — bestehend]
Auto → CDP+/GD101 (USB) → Router (usbipd) → [LAN] → Server (usbip attach)

[Pfad B: WiFi-Bridge — WiCAN Pro]
Auto → WiCAN Pro (OBD2) → Router (WiFi AP + Bridge) → [LAN] → Server (SocketCAN TCP)
                                      ↑
                            Router = transparenter Bridge
                            Keine Treiber auf Router nötig!
```

Der GL.iNet Router bridget alle WiFi-Clients automatisch ins LAN.
Der Umbrel-Server greift direkt auf die WiCAN Pro IP zu.

---

## Voraussetzungen

- WiCAN Pro (ESP32-C3-basiert)
- GL.iNet Router mit aktiviertem WiFi-AP (Standard-Config ausreichend)
- Umbrel-Server / Linux-PC mit `python-can` + `can-utils`
- Optional: `udsoncan` für UDS-Protokoll (Tiefdiagnose)

---

## Setup: Schritt für Schritt

### Schritt 1 — Router als Bridge konfigurieren

→ Vollständige Anleitung: [router-bridge-setup.md](router-bridge-setup.md)

**Kurzfassung:**
```bash
# DHCP-Reservation auf Router (WiCAN Pro bekommt feste IP)
# WiCAN Pro MAC-Adresse: im WiCAN Web-UI einsehen
ssh root@192.168.10.194 "
uci add dhcp host
uci set dhcp.@host[-1].mac='AA:BB:CC:DD:EE:FF'
uci set dhcp.@host[-1].ip='192.168.10.200'
uci set dhcp.@host[-1].name='wican-pro'
uci commit dhcp && /etc/init.d/dnsmasq restart
"
```

### Schritt 2 — WiCAN Pro konfigurieren (Web-UI)

```
1. WiCAN Pro einschalten → verbindet sich im AP-Mode (SSID: WiCAN_XXXX)
2. Browser → http://192.168.80.1
3. Settings → WiFi → Mode: Station
4. SSID: GL-BE3600-AP (oder Router-SSID)
   Password: <Router-WLAN-Passwort>
5. Settings → Protocol → SocketCAN: Enable
   Port: 3333
6. Save → Reboot
```

Nach dem Reboot erscheint WiCAN Pro im Router-DHCP und ist unter
`192.168.10.200` (oder DHCP-Reservation-IP) erreichbar.

### Schritt 3 — Linux-Server: SocketCAN verbinden

```bash
# can-utils installieren
sudo apt-get install can-utils

# SocketCAN via TCP verbinden (WiCAN Pro → slcan0)
sudo slcan_attach -o -s6 -t hw -S 3000000 /dev/ttyACM0 &
# ODER via TCP-Tunnel (empfohlen):
# WiCAN Pro unterstützt direkte SocketCAN TCP-Bridge
sudo ip link set can0 up type can bitrate 500000
```

```python
# python-can Test
import can
bus = can.interface.Bus(channel='can0', interface='socketcan')
msg = bus.recv(timeout=5.0)
print(f"CAN Frame: {msg}")
bus.shutdown()
```

### Schritt 4 — OBD2 via udsoncan (UDS-Protokoll)

```python
import can
import udsoncan
from udsoncan.connections import PythonIsoTpConnection
import isotp

# SocketCAN Bus
bus = can.interface.Bus(channel='can0', interface='socketcan')

# ISO-TP Layer (für UDS)
addr = isotp.Address(isotp.AddressingMode.Normal_11bits, txid=0x7E0, rxid=0x7E8)
stack = isotp.CanStack(bus=bus, address=addr, params={'stmin': 0, 'blocksize': 0})
conn = PythonIsoTpConnection(stack)

# UDS-Client
with udsoncan.Client(conn, request_timeout=2) as client:
    vin = client.read_data_by_identifier(udsoncan.DataIdentifier.VIN)
    print(f"VIN: {vin.service_data.values[udsoncan.DataIdentifier.VIN]}")
```

---

## Volvo-Diagnose mit WiCAN Pro

**Was möglich ist (via SocketCAN + udsoncan):**
- ✅ VIN-Abfrage
- ✅ DTC-Auslesen (UDS $19 03)
- ✅ Live-Daten (UDS $22 — Datenkennungen)
- ✅ ECU-Reset (UDS $11)

**Was NICHT möglich ist:**
- ❌ VIDA 2014D / vdash — benötigen Windows J2534-DLL
- ❌ Volvo-proprietäre D2/GGD-Protokolle (kein SocketCAN-Support)

**Für vollständige Volvo-Tiefdiagnose:**
→ **GODIAG GD101** über Pfad A (USB/IP → Windows VIDA/vdash)

---

## WiCAN Pro vs. CDP+ vs. GODIAG GD101

| Merkmal | CDP+ (Pfad A) | GODIAG GD101 (Pfad A) | WiCAN Pro (Pfad B) |
|---|---|---|---|
| Verbindung | USB → USB/IP | USB → USB/IP | WiFi direkt |
| Router nötig | ✅ USB-Host | ✅ USB-Host | ⚠️ Bridge only |
| Linux | ✅ ftdi_sio | ⚠️ partial | ✅ SocketCAN |
| python-obd | ✅ serial | ❌ | ✅ via can+udsoncan |
| Volvo VIDA | ❌ | ✅ | ❌ |
| Kabellos | ❌ | ❌ | ✅ |
| Preis | €50–150 | €30–60 | €50–80 |

---

## Troubleshooting

### WiCAN Pro nicht im Netz
```bash
# DHCP-Leases auf Router prüfen
ssh root@192.168.10.194 "cat /tmp/dhcp.leases | grep -i wican"

# WiCAN Web-UI direkt (AP-Mode): http://192.168.80.1
# Falls STA-Verbindung fehlschlägt → Router-MAC-Filter prüfen
```

### SocketCAN keine Frames
```bash
candump can0         # Rohe CAN-Frames anzeigen
cansend can0 7DF#0201050000000000  # OBD2 Mode 01 PID 05 (Kühlwasser)
```

### python-can ImportError
```bash
pip install python-can can-isotp udsoncan
```

---

## Links

- WiCAN Firmware: https://github.com/meatpiHQ/wican-fw
- WiCAN Crowd Supply: https://www.crowdsupply.com/meatpi-electronics/wican-pro
- PCMHacking Forum (WiCAN J2534): https://pcmhacking.net/forums/viewtopic.php?t=9147
- udsoncan: https://udsoncan.readthedocs.io/
