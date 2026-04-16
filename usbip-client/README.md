# USB/IP Client — GL.iNet OBD2 Setup

Dieses Verzeichnis enthält alle Skripte und Konfigurationen für das
**OBD2-Diagnose-Setup** mit GL.iNet-Routern als zentralem Hub.

Der Router übernimmt dabei eine **Doppelrolle**:
- **Pfad A:** USB/IP-Server — exportiert USB-Adapter ins Netz
- **Pfad B:** WiFi-Bridge — routet WiFi-native OBD2-Adapter ins LAN

---

## Gesamt-Architektur

```
╔══════════════════════════════════════════════════════════════════╗
║  Auto / OBD2-Port                                                ║
║                                                                   ║
║  ┌─────────────┐  USB   ┌──────────────────────────┐            ║
║  │ CDP+ / GD101│ ──────▶│                          │  LAN        ║
║  │ VIDA DiCE   │        │   GL.iNet Router          │ ─────────▶ Proxmox LXC 212
║  │ MVCI PRO+   │        │                          │  192.168.10.212
║  └─────────────┘        │  ┌─────────────────────┐ │
║                         │  │  usbipd (Pfad A)    │ │
║  ┌─────────────┐  WiFi  │  │  WiFi AP (Pfad B)   │ │
║  │  WiCAN Pro  │ ──────▶│  │  Bridge: WiFi → LAN │ │
║  │  Vgate iCar2│        │  └─────────────────────┘ │
║  │  Macchina   │        └──────────────────────────┘
║  └─────────────┘
╚══════════════════════════════════════════════════════════════════╝

Proxmox LXC 212 (obd-monitor) verbindet sich via:
  Pfad A → usbip attach → /dev/ttyUSB0 → python-obd (serial) / VIDA
  Pfad B → TCP direkt  → 192.168.10.200 → python-can / udsoncan / obd TCP
  Lab   → socket://192.168.10.213:35000 → ELM327-emulator (LXC 213, Stufe 0)
```

### Pfad A — USB/IP (USB-Adapter direkt am Router)
```
Auto → USB-Adapter → Router (USB-Host + usbipd) → LAN → Server
```

### Pfad B — WiFi-Bridge (WiFi-Adapter, kein Treiber auf Router)
```
Auto → WiFi-Adapter → Router (WiFi AP + Bridge) → LAN → Server
```

---

## Geräte-Tabs (Router-Modelle)

| Verzeichnis | Gerät | Status | Besonderheiten |
|---|---|---|---|
| [gl-inet-be3600/](gl-inet-be3600/) | GL-BE3600 (Slate 7) | ✅ Vorhanden | WiFi 7, USB-Stick für Python-Pkgs, Touchscreen |
| [gl-inet-e5800/](gl-inet-e5800/) | GL-E5800 (Mudi 7) | 🛒 Kaufbar | 5G NR, 8 GB eMMC (kein USB-Stick), Akku |
| [gl-inet-be10000/](gl-inet-be10000/) | GL-BE10000 (Slate 7 Pro) | 🔬 Prototype | WiFi 7 BE10000, 2.8" Display (320×240) |

### Geräte-Vergleich

| Merkmal | GL-BE3600 | GL-E5800 | GL-BE10000 |
|---|---|---|---|
| SoC | IPQ5332 (4× A55) | Qualcomm X72 (4× @2.2 GHz) | TBD (Prototype) |
| RAM | 1 GB DDR4 | 2 GB LPDDR4X | TBD |
| Storage | 512 MB NAND | 8 GB eMMC | TBD |
| USB | 1× USB 3.0 | 1× USB 3.1 + USB-C OTG | TBD |
| Display | 76×284 Touchscreen | Touchscreen (TBD) | 2.8" 320×240 Querformat |
| 5G Modem | ❌ | ✅ (Dragonwing X72) | ❌ |
| Akku | ❌ | ✅ 5380 mAh (≥8h) | ❌ |
| Python-Pkgs | USB-Stick nötig | eMMC direkt (venv) | eMMC direkt (venv) |
| OBD2-IP | 192.168.10.194 | 192.168.10.195 | 192.168.10.196 |

---

## Adapter-Tab

| Verzeichnis | Adapter | Pfad | Empfehlung |
|---|---|---|---|
| [adapters/](adapters/) | Alle Adapter — Vergleich + Auswahl | — | → Vergleichsmatrix |
| [adapters/autocom-cdp-plus/](adapters/autocom-cdp-plus/) | Autocom CDP+ (FTDI) | A | ✅ Standard OBD2 + Linux |
| [adapters/volvo-vida-dice/](adapters/volvo-vida-dice/) | Volvo VIDA DiCE (SETEK) | A | ⚠️ Original, teuer, VM |
| [adapters/mvci-pro-plus/](adapters/mvci-pro-plus/) | Xhorse MVCI PRO+ (J2534) | A | ⚠️ VAG/Toyota |
| [adapters/godiag-gd101/](adapters/godiag-gd101/) | GODIAG GD101 (FTDI J2534) | A | ★ Volvo Tiefdiagnose |
| [adapters/wican-pro/](adapters/wican-pro/) | WiCAN Pro (ESP32-C3) | B | ★★ WiFi+J2534+Linux |
| [adapters/vgate-icar2-wifi/](adapters/vgate-icar2-wifi/) | Vgate iCar 2 (ELM327) | B | ⚠️ Günstig, kein J2534 |
| [adapters/macchina-m2/](adapters/macchina-m2/) | Macchina M2/A0 (Open HW) | B | ★ J2534+WiFi Open Source |
| [adapters/topdon-rlink/](adapters/topdon-rlink/) | TOPDON RLink J2534/Lite/X7 | — | ❌ Nicht empfohlen |

---

## Quickstart

### Bestehendes Setup (GL-BE3600 + CDP+, Pfad A)

```bash
cd gl-inet-be3600/
./ssh-manager.sh setup
curl http://192.168.10.194:8765/obd/status
```

### Neuer WiFi-Adapter (WiCAN Pro, Pfad B)

```bash
# 1. WiCAN Pro in Router-WiFi einbuchen
#    → adapters/wican-pro/router-bridge-setup.md

# 2. DHCP-Reservation setzen
ssh root@192.168.10.194 "
uci add dhcp host
uci set dhcp.@host[-1].mac='<WiCAN-MAC>'
uci set dhcp.@host[-1].ip='192.168.10.200'
uci commit dhcp && /etc/init.d/dnsmasq restart
"

# 3. Verbindung testen (Proxmox LXC 212)
python3 -c "
import can
bus = can.Bus(interface='socketcand', channel='can0',
              host='192.168.10.200', port=3333)
print('WiCAN Pro OK:', bus.channel_info)
bus.shutdown()
"
```

### Adapter wechseln (Pfad A)

```bash
# Neue adapter.conf auf Router
scp adapters/godiag-gd101/adapter.conf root@192.168.10.194:/etc/obd-adapter.conf
ssh root@192.168.10.194 "/etc/init.d/usbipd restart && obd-ctl adapter"
```

---

## Netzwerk-Topologie

```
Heimnetz (192.168.10.0/24)
│
├── Proxmox LXC 212   192.168.10.212   (obd-monitor: USB/IP-Client + python-obd + Rich-Dashboard)
├── Proxmox LXC 213   192.168.10.213   (obd-sim: ELM327-emulator auf :35000, Lab/Stufe 0)
│
├── GL-BE3600 WiFi    192.168.10.194   (Slate 7      — Router + USB/IP-Server)
├── GL-E5800  WiFi    192.168.10.195   (Mudi 7       — Router + 5G + USB/IP)
├── GL-BE10000 WiFi   192.168.10.196   (Slate 7 Pro  — Prototype)
│       │
│       └── Pfad A: USB-Adapter (CDP+/GD101/DiCE) → usbipd Export
│
├── WiCAN Pro WiFi    192.168.10.200   (Pfad B — WiFi-native J2534)
└── Vgate / Macchina  192.168.10.201   (Pfad B — WiFi-native ELM327/J2534)
```

---

## Verwandte Dokumentation

- [adapters/README.md](adapters/README.md) — Vollständiger Adapter-Vergleich (8 Adapter, Zwei-Pfad-Architektur)
- [adapters/wican-pro/router-bridge-setup.md](adapters/wican-pro/router-bridge-setup.md) — GL.iNet als WiFi-Bridge konfigurieren
- [adapters/godiag-gd101/vdash-setup.md](adapters/godiag-gd101/vdash-setup.md) — vdash Volvo-Tiefdiagnose Guide
- [adapters/volvo-vida-dice/vida-vm-setup.md](adapters/volvo-vida-dice/vida-vm-setup.md) — VIDA 2014D via Windows-VM
- [gl-inet-e5800/README.md](gl-inet-e5800/README.md) — Mudi 7 Setup (5G, eMMC)
- [gl-inet-be10000/README.md](gl-inet-be10000/README.md) — Slate 7 Pro (Prototype)
