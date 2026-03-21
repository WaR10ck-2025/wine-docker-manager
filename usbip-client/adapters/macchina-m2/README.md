# Macchina M2 / A0 — Open Hardware J2534 + WiFi (Pfad B)

## Übersicht

Die **Macchina M2** und **A0** sind Open-Hardware OBD2-Adapter auf ESP32-Basis
mit vollständigem J2534-Treiber (Rust) und SocketCAN-Bridge.

| Eigenschaft | M2 | A0 |
|---|---|---|
| Basis | Arduino Due + ESP32 | ESP32 standalone |
| Verbindung | WiFi + BT + USB | WiFi + BT + USB |
| J2534-Treiber | ✅ Macchina-J2534 (Rust) | ✅ |
| Linux-Support | ✅ experimentell | ✅ |
| SocketCAN | ✅ via OpenVehicleDiag | ✅ |
| Preis | ~€100–130 | ~€80–100 |
| Formfaktor | Groß (Arduino Shield) | Kompakt |
| Status | Production | Production |

---

## Architektur: Pfad B — WiFi-Bridge

Identisch zu WiCAN Pro — Router bridget WiFi-Client ins LAN:

```
Auto → Macchina M2/A0 (OBD2) → Router (WiFi-Bridge) → [LAN] → Server
                                                                 ↓
                                                  Macchina-J2534 (Rust)
                                                  OpenVehicleDiag
                                                  python-can SocketCAN
```

---

## Linux-Setup (Macchina-J2534 Rust-Treiber)

```bash
# Rust installieren (falls noch nicht vorhanden)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Macchina-J2534 klonen und bauen
git clone https://github.com/rnd-ash/Macchina-J2534
cd Macchina-J2534
cargo build --release

# libudev nötig
sudo apt-get install libudev-dev
```

### OpenVehicleDiag (SocketCAN + UDS, v1.0.0+)

```bash
# OpenVehicleDiag — Rust, Raspberry Pi fähig, SocketCAN
git clone https://github.com/rnd-ash/OpenVehicleDiag
cd OpenVehicleDiag
cargo build --release

# Starten mit Macchina als SocketCAN-Source
./target/release/ovd_app --adapter macchina
```

### python-can via SocketCAN

```python
import can

# Nach SocketCAN-Bridge mit Macchina:
bus = can.interface.Bus(channel='can0', interface='socketcan')
msg = bus.recv(timeout=5.0)
print(f"Frame: {msg}")
```

---

## Vergleich: Macchina M2 vs. WiCAN Pro

| Merkmal | WiCAN Pro | Macchina M2 |
|---|---|---|
| Preis | ~€50–80 | ~€100–150 |
| J2534-Treiber | Custom DLL (Windows) / SocketCAN | Rust (Linux) |
| Linux-Stabilität | ✅ Production | ⚠️ Experimentell |
| Open Hardware | ⚠️ Closed HW | ✅ Vollständig |
| Volvo UDS | ✅ via udsoncan | ✅ via OpenVehicleDiag |
| Einrichtungsaufwand | Gering | Hoch (Rust Build) |

**Empfehlung:** WiCAN Pro für einfacheres Setup, Macchina M2/A0 für maximale
Open-Source-Kontrolle und tiefere J2534-Anpassungen.

---

## Router-Bridge-Konfiguration

Identisch zur WiCAN Pro Anleitung:
→ [../wican-pro/router-bridge-setup.md](../wican-pro/router-bridge-setup.md)

DHCP-Reservation für Macchina: `192.168.10.201` (nach WiCAN Pro .200)

---

## Links

- Macchina-J2534 GitHub: https://github.com/rnd-ash/Macchina-J2534
- OpenVehicleDiag: https://github.com/rnd-ash/OpenVehicleDiag
- Macchina Forum: https://forum.macchina.cc/
- Macchina Shop: https://www.macchina.cc/
