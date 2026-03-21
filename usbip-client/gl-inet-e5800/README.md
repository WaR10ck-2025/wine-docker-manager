# GL.iNet GL-E5800 (Mudi 7) — OBD2 + USB/IP Migrations-Guide

## Hardware-Übersicht

| Merkmal        | Spezifikation                            |
|----------------|------------------------------------------|
| SoC            | Qualcomm Dragonwing MBB Gen 3 (X72)     |
| CPU            | Quad-Core @2.2 GHz (ARM64)              |
| RAM            | 2 GB LPDDR4X                            |
| Flash          | **8 GB eMMC** (kein USB-Stick nötig!)   |
| USB            | 1× USB 3.1 + 1× USB-C (OTG, 10 Gbps)   |
| Display        | Touchscreen (Auflösung via FB-Test)     |
| Konnektivität  | WiFi 7 tri-band (2.4/5/6 GHz) + 5G NR  |
| Akku           | 5380 mAh, ≥8h Laufzeit, USB PD 30W     |
| OpenWrt        | GL.iNet (OpenWrt-basiert)               |
| IP WiFi        | 192.168.10.195 (Ziel-Setup)             |
| IP Ethernet    | 192.168.10.192                          |

**Vorteile gegenüber GL-BE3600:**
- 8 GB eMMC → Python-venv direkt auf Flash (kein USB-Stick nötig)
- Doppelt so viel RAM → uvicorn stabiler, mehr Worker möglich
- 5G NR → mobiler Internet-Uplink ohne WiFi-Client
- Akku → komplett kabellose Fahrzeugdiagnose

---

## Vorbereitung

```bash
# Lokal (Windows WSL / Linux)
cd usbip-client/gl-inet-e5800/

# Router-IP nach GL.iNet-Default (vor WiFi-Setup): 192.168.8.1
# SSH-Passwort: goodlife (Standard GL.iNet)
./ssh-manager.sh setup
```

---

## Phasen der Einrichtung

### Phase 1: OBD2-Service (sofort nutzbar)

```bash
# Direkt auf dem Router als root
scp install_obd_openwrt.sh root@192.168.8.1:/tmp/
ssh root@192.168.8.1 "sh /tmp/install_obd_openwrt.sh"
```

**Unterschied zu GL-BE3600:**
- Python-Pakete werden in `/opt/obd-venv/` installiert (8 GB eMMC ausreichend)
- Kein USB-Stick erforderlich
- `uvicorn` läuft direkt aus dem venv: `/opt/obd-venv/bin/uvicorn`

### Phase 2: Display-Service

```bash
scp -r obd-display/ root@192.168.8.1:/tmp/obd-display/
ssh root@192.168.8.1 "sh /tmp/obd-display/install_display.sh"
```

**Display-Auflösung (vor Einrichtung auslesen):**
```bash
ssh root@192.168.8.1 "cat /sys/class/graphics/fb0/virtual_size"
# Ausgabe z.B.: 240,320 → DISPLAY_W=240, DISPLAY_H=320
```
Display-Auflösung via ENV-Override anpassen (bis Hardware-Test):
```bash
ssh root@192.168.8.1 "FB_WIDTH=240 FB_HEIGHT=320 python3 /opt/obd-monitor/display_service.py"
```

### Phase 3: USB/IP-Module (Custom-Build)

```bash
# Auf Linux-Build-Rechner:
cd sdk-build/
chmod +x build_usbip_modules.sh
./build_usbip_modules.sh
# → Erzeugt kmod-usbip_*.ipk + kmod-usbip-host_*.ipk
```

```bash
# Module auf Router übertragen und installieren
scp kmod-usbip*.ipk root@192.168.8.1:/tmp/
ssh root@192.168.8.1 "opkg install /tmp/kmod-usbip*.ipk"
ssh root@192.168.8.1 "/etc/init.d/usbipd start"
```

### Phase 4: WiFi-Client + 5G konfigurieren

```bash
./ssh-manager.sh setup-wifi "SSID" "Passwort"
./ssh-manager.sh setup-ip 192.168.10.195 192.168.10.192
```

**5G-Modem aktivieren** (nach SIM-Einlegen):
```bash
ssh root@192.168.8.1 "uci set network.modem.proto=dhcp; uci commit; /etc/init.d/network restart"
```

### Phase 5: SSH-Key einrichten (empfohlen)

```bash
./ssh-manager.sh setup-key
./ssh-manager.sh -k ~/.ssh/id_rsa status
```

### Phase 6: VPN (optional)

```bash
# Tailscale
./setup-vpn.sh --tailscale -t <AUTH-KEY> --subnet

# WireGuard
./setup-vpn.sh -c mein-vpn.conf
```

### Phase 7: Alles prüfen

```bash
./ssh-manager.sh status
curl http://192.168.10.195:8765/obd/status
```

---

## Geräte-Unterschiede: E5800 vs. BE3600

| Aspekt            | GL-BE3600                    | GL-E5800                      |
|-------------------|------------------------------|-------------------------------|
| Python-Pakete     | USB-Stick `/mnt/usb/obd-pkgs`| venv `/opt/obd-venv`          |
| init.d Command    | `PYTHONPATH=... uvicorn`     | `/opt/obd-venv/bin/uvicorn`   |
| Display           | 76×284px (fest)              | ENV-konfigurierbar             |
| gl_screen Daemon  | ✅ Vorhanden                 | ⚠️ Ggf. nicht vorhanden       |
| 5G Uplink         | ❌                           | ✅ Via SIM/eSIM               |
| Akku              | ❌                           | ✅ 5380 mAh                   |
| SDK-Profil        | `config-wlan-ap-5.4.yml`     | X72-spezifisch (TBD)          |

---

## Service-Verwaltung

```bash
# Status
./ssh-manager.sh status

# Neustart
./ssh-manager.sh restart obd
./ssh-manager.sh restart display
./ssh-manager.sh restart usbipd

# Logs
./ssh-manager.sh logs 100
./ssh-manager.sh follow

# OBD2 Live-Daten
./ssh-manager.sh obd
```

---

## USB-Adapter

Den aktuell verwendeten Adapter auswählen:

```bash
# Autocom CDP+ (Standard)
scp ../adapters/autocom-cdp-plus/adapter.conf root@192.168.8.1:/etc/obd-adapter.conf

# GODIAG GD101 (für Volvo-Tiefdiagnose)
scp ../adapters/godiag-gd101/adapter.conf root@192.168.8.1:/etc/obd-adapter.conf

# Adapter anwenden
./ssh-manager.sh restart usbipd
```

---

## Wiederherstellung

```bash
# Soft-Restore (nur OBD2/USB-IP entfernen)
./ssh-manager.sh restore

# WiFi zurücksetzen
./ssh-manager.sh restore wifi

# Werksreset (WARNUNG: alle Daten gelöscht)
./ssh-manager.sh restore full
```

---

## Troubleshooting

| Problem | Ursache | Lösung |
|---------|---------|--------|
| `venv not found` | Python3 nicht installiert | `opkg install python3` |
| Port 8765 nicht offen | Service nicht gestartet | `logread \| grep obd` |
| Framebuffer leer | `gl_screen` läuft noch | `rc.d stop gl_screen` oder ENV-check |
| 5G keine Verbindung | SIM nicht erkannt | `cat /proc/net/dev \| grep wwan` |
| USB-Adapter nicht gebunden | Falscher VID:PID | `/etc/obd-adapter.conf` prüfen |

---

## Verwandte Verzeichnisse

- [../gl-inet-be3600/](../gl-inet-be3600/) — GL-BE3600 (Slate 7) — **Fallback**
- [../gl-inet-be10000/](../gl-inet-be10000/) — GL-BE10000 (Slate 7 Pro)
- [../adapters/](../adapters/) — USB-Adapter (CDP+, DiCE, GODIAG GD101)
- [../nanopi-r5c/](../nanopi-r5c/) — NanoPi R5C — **Original-Setup**
