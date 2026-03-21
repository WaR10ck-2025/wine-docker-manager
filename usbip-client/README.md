# USB/IP Client — GL.iNet OBD2 Setup

Dieses Verzeichnis enthält alle Skripte und Konfigurationen für das
**USB/IP-basierte OBD2-Diagnose-Setup** mit GL.iNet-Routern als USB/IP-Server.

```
GL.iNet Router (USB/IP-Server)
  └── USB: OBD2-Adapter eingesteckt
  └── Port 3240: USB/IP → exportiert Adapter ins Netz
  └── Port 8765: FastAPI OBD2-Service (Live-Daten, DTC)

Umbrel-Server / Windows-PC (USB/IP-Client)
  └── usbip attach → Adapter lokal verfügbar
  └── [Linux]   python-obd / obd_service.py direkt
  └── [Windows] VIDA 2014D / vdash / Hersteller-Software
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

| Verzeichnis | Adapter | Empfehlung |
|---|---|---|
| [adapters/](adapters/) | Alle 4 Adapter — Vergleich + Auswahl | → Vergleichsmatrix |
| [adapters/autocom-cdp-plus/](adapters/autocom-cdp-plus/) | Autocom CDP+ (FTDI) | ✅ Standard OBD2 + Linux-nativ |
| [adapters/volvo-vida-dice/](adapters/volvo-vida-dice/) | Volvo VIDA DiCE (SETEK) | Original, teuer, VM nötig |
| [adapters/mvci-pro-plus/](adapters/mvci-pro-plus/) | Xhorse MVCI PRO+ (J2534) | VAG/Toyota gut, Volvo eingeschränkt |
| [adapters/godiag-gd101/](adapters/godiag-gd101/) | GODIAG GD101 (FTDI J2534) | ★ **Empfohlen für Volvo Tiefdiagnose** |

### Adapter-Kurzübersicht

| Adapter | Linux-Treiber | python-OBD | Volvo Tiefdiagnose | Preis |
|---|---|---|---|---|
| Autocom CDP+ | ✅ `ftdi_sio` | ✅ direkt | ❌ nur OBD2 | ~€50–150 |
| VIDA DiCE | ❌ VM-only | ❌ | ✅ Vollzugriff | ~€150–300 |
| MVCI PRO+ | ❌ VM-only | ❌ | ⚠️ unzuverlässig | ~€80–120 |
| GODIAG GD101 | ⚠️ FTDI (partial) | ❌ | ✅ VIDA/vdash | ~€30–60 |

---

## Quickstart

### Bestehendes Setup (GL-BE3600 + CDP+)

```bash
# Auf Router deployen
cd gl-inet-be3600/
./ssh-manager.sh setup

# Status prüfen
./ssh-manager.sh status
curl http://192.168.10.194:8765/obd/status
```

### Neues Gerät einrichten (GL-E5800 / GL-BE10000)

```bash
# GL-E5800
cd gl-inet-e5800/
./ssh-manager.sh setup         # Interaktiv durch alle Phasen

# GL-BE10000 (Prototype)
cd gl-inet-be10000/
./ssh-manager.sh setup
```

### Adapter wechseln (z.B. CDP+ → GODIAG GD101)

```bash
# adapter.conf auf Router kopieren
scp adapters/godiag-gd101/adapter.conf root@192.168.10.194:/etc/obd-adapter.conf

# usbipd neu starten (liest neue Config)
ssh root@192.168.10.194 "/etc/init.d/usbipd restart"

# Status prüfen
ssh root@192.168.10.194 "obd-ctl adapter"
```

---

## Netzwerk-Topologie

```
Heimnetz (192.168.10.0/24)
│
├── Umbrel-Server     192.168.10.147   (USB/IP-Client + Docker OBD2-Frontend)
│
├── GL-BE3600 WiFi    192.168.10.194   (Slate 7     — vorhanden)
├── GL-E5800  WiFi    192.168.10.195   (Mudi 7      — optional)
└── GL-BE10000 WiFi   192.168.10.196   (Slate 7 Pro — Prototype)
       │
       └── USB: OBD2-Adapter (CDP+ / VIDA DiCE / GD101)
             └── Port 3240: USB/IP exportiert Adapter
```

---

## Fallback: NanoPi R5C

Das ursprüngliche Setup basierte auf einem NanoPi R5C. Die Migrations-Dokumentation
ist in den einzelnen Geräte-Verzeichnissen erhalten (besonders `gl-inet-be3600/`).

---

## Verwandte Dokumentation

- [adapters/README.md](adapters/README.md) — Vollständiger Adapter-Vergleich (4 Adapters)
- [adapters/godiag-gd101/vdash-setup.md](adapters/godiag-gd101/vdash-setup.md) — vdash Volvo-Tiefdiagnose Guide
- [adapters/volvo-vida-dice/vida-vm-setup.md](adapters/volvo-vida-dice/vida-vm-setup.md) — VIDA 2014D via Windows-VM
- [gl-inet-e5800/README.md](gl-inet-e5800/README.md) — Mudi 7 Setup (5G, eMMC)
- [gl-inet-be10000/README.md](gl-inet-be10000/README.md) — Slate 7 Pro (Prototype)
