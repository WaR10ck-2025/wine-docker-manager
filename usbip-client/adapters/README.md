# USB-Adapter Auswahl — OBD2 + Volvo Tiefdiagnose

Dieses Verzeichnis abstrahiert die Adapter-Auswahl für das USB/IP-Projekt.
Jeder Adapter hat eine eigene `adapter.conf` die in `/etc/obd-adapter.conf` auf
dem Router kopiert wird — dadurch wird VID:PID dynamisch geladen.

---

## Adapter-Vergleich

| Merkmal                  | Autocom CDP+        | Volvo VIDA DiCE     | MVCI PRO+ (Xhorse)  | GODIAG GD101        |
|--------------------------|---------------------|---------------------|---------------------|---------------------|
| USB VID:PID              | `0403:d6da`         | `17aa:d1ce`         | proprietär (Xhorse) | FTDI-basiert (var.) |
| Protokoll                | ISO 9141-2 / K-Line | J2534 + D2/GGD      | J2534 + D-PDU       | J2534               |
| Linux-Treiber            | ✅ `ftdi_sio`       | ❌ Windows-only     | ❌ Windows-only     | ⚠️ herstellerabhäng.|
| python-OBD direkt        | ✅ pyserial         | ❌                  | ❌                  | ❌                  |
| FastAPI OBD2-Service     | ✅ Direkt           | ❌                  | ❌                  | ❌                  |
| Volvo VIDA-kompatibel    | ❌                  | ✅ Nativ            | ⚠️ Gemischt*        | ✅ Bestätigt        |
| vdash-kompatibel         | ❌                  | ✅                  | ⚠️ unbekannt        | ✅                  |
| Volvo Tiefdiagnose       | ❌ Nur OBD2         | ✅ Vollzugriff      | ⚠️ Eingeschränkt    | ✅ Vollzugriff      |
| USB/IP-fähig             | ✅                  | ✅                  | ✅                  | ✅                  |
| Hauptstärke              | Multi-Brand OBD2    | Volvo only          | VAG/Toyota/Subaru   | Volvo VIDA/vdash    |
| Preis                    | ~€50-150            | ~€150-300           | ~€80-120            | ~€30-60             |

> **\* MVCI PRO+ + Volvo VIDA:** Xhorse liefert keinen Volvo-spezifischen Treiber → VIDA-Kompatibilität nicht garantiert.
> Für Volvo-Tiefdiagnose **GODIAG GD101 bevorzugen**.

---

## Empfehlungen

### Für dieses Projekt (OBD2 FastAPI + python-obd)
→ **Autocom CDP+** (Standard-Setup, Linux-nativ, Multi-Marken)

### Für Volvo-Tiefdiagnose (VIDA / vdash)
→ **GODIAG GD101** (günstig, VIDA/vdash bestätigt, FTDI-basiert)

### Bestehender MVCI PRO+
→ Gut für VAG/Toyota/Subaru, **nicht empfohlen für Volvo VIDA** (fehlender Treiber)

---

## Adapter-Wechsel

```bash
# 1. Adapter-Config auf den Router kopieren
scp adapters/<adapter>/adapter.conf root@192.168.10.194:/etc/obd-adapter.conf

# 2. usbipd neu starten (lädt neue VID:PID)
ssh root@192.168.10.194 "/etc/init.d/usbipd restart"

# 3. Verify
ssh root@192.168.10.194 "obd-ctl adapter"
```

---

## Integration-Strategie

```
GL.iNet Router
  └── USB: Adapter eingesteckt (CDP+ / DiCE / GD101)
  └── usbipd: exportiert Adapter (VID:PID aus /etc/obd-adapter.conf)

Windows-PC
  └── usbipd-win: importiert Adapter
  ├── [CDP+]   → obd_service.py (FastAPI) / CARS-Software
  ├── [DiCE]   → VIDA 2014D (Windows VM)
  ├── [MVCI]   → VAG ODIS / Toyota TIS (Windows VM)
  └── [GD101]  → VIDA 2014D / vdash (empfohlen für Volvo)
```

---

## Verzeichnisstruktur

```
adapters/
├── README.md                        # Diese Datei
├── autocom-cdp-plus/                # Standard-Adapter (Linux-nativ)
│   ├── README.md
│   ├── adapter.conf
│   └── bind-cdp.sh
├── volvo-vida-dice/                 # Volvo VIDA DiCE (Windows-only)
│   ├── README.md
│   ├── adapter.conf
│   ├── bind-dice.sh
│   └── vida-vm-setup.md
├── mvci-pro-plus/                   # Xhorse MVCI PRO+ (VAG/Toyota)
│   ├── README.md
│   ├── adapter.conf
│   └── bind-mvci.sh
└── godiag-gd101/                    # ★ Empfohlen für Volvo (VIDA/vdash)
    ├── README.md
    ├── adapter.conf
    ├── bind-gd101.sh
    └── vdash-setup.md
```
