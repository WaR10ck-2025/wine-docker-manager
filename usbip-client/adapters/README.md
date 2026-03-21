# USB-Adapter Auswahl — OBD2 + Volvo Tiefdiagnose

Dieses Verzeichnis abstrahiert die Adapter-Auswahl für das OBD2-Projekt.
Es gibt zwei Architektur-Pfade je nach Adapter-Typ:

---

## Zwei-Pfad-Architektur

### Pfad A — USB/IP (USB-Adapter am Router)

```
Auto → USB-Adapter → GL.iNet Router (USB-Host + usbipd) → [LAN] → Server
  CDP+ / VIDA DiCE       usbipd exportiert Adapter             usbip attach
  MVCI PRO+ / GD101      /etc/obd-adapter.conf → VID:PID       /dev/ttyUSB0
                                                                python-obd / VIDA
```

Adapter-Config auf Router kopieren:
```bash
scp adapters/<adapter>/adapter.conf root@192.168.10.194:/etc/obd-adapter.conf
ssh root@192.168.10.194 "/etc/init.d/usbipd restart"
```

### Pfad B — WiFi-Bridge (WiFi-Adapter via Router)

```
Auto → WiFi-Adapter → GL.iNet Router (WiFi AP + Bridge) → [LAN] → Server
  WiCAN Pro            Bridge: WiFi → br-lan (automatisch)      SocketCAN TCP
  Vgate iCar 2         DHCP-Reservation → feste IP              python-can
  Macchina M2/A0       Keine Treiber auf Router nötig!          udsoncan / obd TCP
```

Router-Bridge einrichten:
```bash
# Einmalig: DHCP-Reservation für WiFi-Adapter
ssh root@192.168.10.194 "
uci add dhcp host
uci set dhcp.@host[-1].mac='<Adapter-MAC>'
uci set dhcp.@host[-1].ip='192.168.10.200'
uci commit dhcp && /etc/init.d/dnsmasq restart
"
```

---

## Adapter-Vergleich (alle 8 Adapter)

| Adapter | Pfad | USB | WiFi | J2534 | Linux | Volvo VIDA | Preis | Urteil |
|---|---|---|---|---|---|---|---|---|
| **Autocom CDP+** | A | ✅ | ❌ | ❌ ISO9141 | ✅ ftdi_sio | ❌ | €50–150 | ✅ Standard OBD2 |
| **Volvo VIDA DiCE** | A | ✅ | ❌ | J2534+D2 | ❌ VM | ✅ nativ | €150–300 | ⚠️ Teuer, VM |
| **MVCI PRO+** (Xhorse) | A | ✅ | ❌ | J2534 | ❌ VM | ⚠️ | €80–120 | ⚠️ VAG/Toyota |
| **GODIAG GD101** | A | ✅ | ❌ | J2534 | ⚠️ ftdi | ✅ | €30–60 | ✅ Volvo |
| **Vgate iCar 2 WiFi** | B | ❌ | ✅ | ❌ ELM327 | ✅ TCP | ❌ | €20–40 | ⚠️ Günstig, kein J2534 |
| **WiCAN Pro** | B | ✅ | ✅ | ✅ | ✅ SocketCAN | ⚠️ UDS | €50–80 | ★★ WiFi+J2534+Linux |
| **Macchina M2/A0** | B | ✅ | ✅ | ✅ Rust | ✅ exp. | ⚠️ UDS | €100–150 | ★ Open HW |
| **TOPDON RLink** | — | ✅ | ❌/✅ | ✅ | ❌ | ❌ | €400–1200 | ❌ Nicht empfohlen |

> **MVCI PRO+ + Volvo VIDA:** Kein Volvo-Treiber → unzuverlässig. GD101 bevorzugen.

---

## Empfehlungen nach Use-Case

| Use-Case | Empfohlener Adapter | Pfad |
|---|---|---|
| Standard OBD2 (Linux-nativ, Multi-Brand) | **Autocom CDP+** | A: USB/IP |
| Volvo Tiefdiagnose (VIDA / vdash) | **GODIAG GD101** | A: USB/IP → Windows |
| Günstig + kabellos (Standard OBD2) | **Vgate iCar 2 WiFi** | B: WiFi-Bridge |
| Kabellos + J2534 + Linux | **WiCAN Pro** ★★ | B: WiFi-Bridge |
| Open Hardware + J2534 + WiFi | **Macchina M2/A0** | B: WiFi-Bridge |

---

## IP-Adressen-Konvention

| Gerät / Adapter | IP |
|---|---|
| GL-BE3600 (WiFi) | 192.168.10.194 |
| GL-E5800 (WiFi) | 192.168.10.195 |
| GL-BE10000 (WiFi) | 192.168.10.196 |
| WiCAN Pro (DHCP-Reservation) | 192.168.10.200 |
| Vgate iCar 2 / Macchina M2 | 192.168.10.201 |

---

## Server-seitige Verbindung

### Pfad A — python-obd via usbipd

```python
import obd
conn = obd.OBD("/dev/ttyUSB0")          # Nach usbip attach
print(conn.status())
```

### Pfad B — WiCAN Pro via SocketCAN

```python
import can
import udsoncan
from udsoncan.connections import PythonIsoTpConnection
import isotp

bus = can.interface.Bus(
    interface='socketcand', channel='can0',
    host='192.168.10.200', port=3333
)
addr = isotp.Address(isotp.AddressingMode.Normal_11bits, txid=0x7E0, rxid=0x7E8)
stack = isotp.CanStack(bus=bus, address=addr)
conn = PythonIsoTpConnection(stack)
with udsoncan.Client(conn, request_timeout=2) as client:
    print(client.read_data_by_identifier(udsoncan.DataIdentifier.VIN))
```

### Pfad B — Vgate iCar 2 via TCP/ELM327

```python
import obd
conn = obd.OBD("192.168.10.201", portstr="35000")
print(conn.query(obd.commands.COOLANT_TEMP))
```

---

## Adapter-Wechsel (Pfad A)

```bash
# Adapter-Config wechseln
scp adapters/godiag-gd101/adapter.conf root@192.168.10.194:/etc/obd-adapter.conf
ssh root@192.168.10.194 "/etc/init.d/usbipd restart && obd-ctl adapter"
```

---

## Verzeichnisstruktur

```
adapters/
├── README.md                          # Diese Datei
│
├── ── Pfad A: USB/IP ──────────────────────────────────────
├── autocom-cdp-plus/                  # Standard OBD2 (Linux-nativ)
│   ├── README.md
│   ├── adapter.conf
│   └── bind-cdp.sh
├── volvo-vida-dice/                   # Volvo VIDA DiCE (Windows-only)
│   ├── README.md
│   ├── adapter.conf
│   ├── bind-dice.sh
│   └── vida-vm-setup.md
├── mvci-pro-plus/                     # Xhorse MVCI PRO+ (VAG/Toyota)
│   ├── README.md
│   ├── adapter.conf
│   └── bind-mvci.sh
├── godiag-gd101/                      # ★ Empfohlen für Volvo (VIDA/vdash)
│   ├── README.md
│   ├── adapter.conf
│   ├── bind-gd101.sh
│   └── vdash-setup.md
│
├── ── Pfad B: WiFi-Bridge ─────────────────────────────────
├── wican-pro/                         # ★★ WiFi + J2534 + Linux
│   ├── README.md
│   ├── adapter.conf
│   └── router-bridge-setup.md        # GL.iNet als WiFi-Bridge konfigurieren
├── vgate-icar2-wifi/                  # Günstig, ELM327, kein J2534
│   ├── README.md
│   ├── adapter.conf
│   └── wifi-obd-setup.md
├── macchina-m2/                       # Open Hardware, J2534 Rust
│   ├── README.md
│   └── adapter.conf
│
└── ── Nicht empfohlen ─────────────────────────────────────
    └── topdon-rlink/                  # Teuer, Windows-only
        ├── README.md
        └── adapter.conf
```
