# GL.iNet GL-BE3600 (Slate 7) — Migration vom NanoPi R5C

Dieses Verzeichnis enthält alle Skripte und Konfigurationen, um die bisherige
NanoPi R5C Funktionalität vollständig auf den **GL.iNet GL-BE3600 (Slate 7)** zu
migrieren.

## Was wird migriert?

| Funktion           | NanoPi R5C (vorher)       | GL-BE3600 (nachher)              |
|--------------------|---------------------------|----------------------------------|
| USB/IP-Server      | `usbipd` via apt + systemd | `usbipd` via custom kmod + init.d |
| OBD2-Service       | Python venv + systemd      | Python auf USB-Stick + procd     |
| WiFi-Client        | USB-Dongle (optional)      | Eingebaut (WiFi 7, BE3600)       |
| Netzwerk-IPs       | eth0: .193, wlan0: .194    | LAN: .193 (oder DHCP), WiFi: .194 |

---

## Voraussetzungen

- GL-BE3600 mit Standard GL.iNet Firmware (OpenWrt 23.05 basiert)
- SSH-Zugriff: `ssh root@192.168.8.1` (Standard GL.iNet LAN-IP)
- USB-Stick ≥2 GB am USB-3.0 Port des Routers
- Autocom CDP+ (FTDI 0403:d6da) am USB-3.0 Port

> **Hinweis:** USB-Stick und CDP+ teilen sich denselben USB-Port über einen
> USB-Hub. Ein USB-3.0-Hub wird empfohlen, damit beide Geräte gleichzeitig
> funktionieren.

---

## Phase 1: OBD2-Service migrieren (kein SDK-Build nötig)

```bash
# 1. Skript auf den Router kopieren
scp install_obd_openwrt.sh root@192.168.8.1:/tmp/

# 2. SSH einloggen und ausführen
ssh root@192.168.8.1
chmod +x /tmp/install_obd_openwrt.sh
/tmp/install_obd_openwrt.sh
```

Das Skript installiert automatisch:
- Python3 via opkg
- pip-Pakete auf USB-Stick (`/mnt/usb/obd-pkgs`)
- `obd_service.py` und Protokoll-Adapter nach `/opt/obd-monitor/`
- OpenWrt init.d Service (procd, Auto-Restart)

**Verifikation:**
```bash
curl http://192.168.8.1:8765/obd/status
# → {"connected": false, "protocol": null, "port": null, "error": "..."}
```

Danach in `docker-compose.yml` anpassen:
```yaml
OBD_MONITOR_HOST: "192.168.10.194"   # GL-BE3600 WiFi-IP (nach WiFi-Setup)
```

---

## Phase 2: USB/IP via Custom Firmware

> **Warnung:** Dieser Schritt erfordert das Kompilieren von Kernel-Modulen aus dem
> GL.iNet SDK. Dauer: ~30–90 Minuten (je nach Host-CPU).

### 2.1 SDK-Build auf dem Entwicklungs-PC (Linux empfohlen)

```bash
# Voraussetzungen installieren (Ubuntu/Debian)
sudo apt-get install -y build-essential libncurses5-dev python3 git rsync unzip

# SDK-Build-Skript ausführen
cd sdk-build/
chmod +x build_usbip_modules.sh
./build_usbip_modules.sh
```

Das Skript klont den GL.iNet glbuilder, konfiguriert die USB/IP-Module und
baut nur die Kernel-Module (kein vollständiges Firmware-Image).

**Erwartete Ausgabe:**
```
[OK] Klone gl-infra-builder...
[OK] Setup für GL-BE3600 (ipq53xx)...
[OK] Baue kmod-usbip und kmod-usbip-host...
[OK] IPK-Pakete bereit:
     build/packages/kmod-usbip_*.ipk
     build/packages/kmod-usbip-host_*.ipk
```

### 2.2 Module auf GL-BE3600 installieren

```bash
# IPK-Dateien übertragen
scp build/packages/kmod-usbip*.ipk root@192.168.8.1:/tmp/

# Auf dem Router installieren
ssh root@192.168.8.1
opkg install /tmp/kmod-usbip_*.ipk
opkg install /tmp/kmod-usbip-host_*.ipk

# usbipd + bind-Skript installieren
/tmp/install_usbipd_openwrt.sh
```

### 2.3 CDP+ einbinden

```bash
# Module laden
modprobe usbip-core
modprobe usbip-host

# Gerät prüfen
usbip list -l
# → busid 1-1 (0403:d6da) Autocom CDP+

# Gerät binden
usbip bind -b 1-1

# Service starten (auto-bind beim Start)
/etc/init.d/usbipd enable
/etc/init.d/usbipd start
```

**Verifikation vom Umbrel-Server:**
```bash
usbip list -r 192.168.10.194
# → 1-1: Future Technology Devices International, Ltd FT232 Serial (UART) IC
```

---

## Phase 3: WiFi als Client konfigurieren

Der GL-BE3600 muss sich mit dem Heimnetz verbinden, um vom Umbrel-Server aus
erreichbar zu sein.

### Option A: Über GL.iNet Admin-UI (empfohlen)
1. Browser: `http://192.168.8.1`
2. → Internet → Repeater
3. SSID: `HTP-1-2.4G`, Passwort: `test123456`
4. Statische IP setzen: `192.168.10.194`

### Option B: Via SSH + UCI
```bash
scp network-config/wireless root@192.168.8.1:/etc/config/wireless
scp network-config/network  root@192.168.8.1:/etc/config/network
ssh root@192.168.8.1 "wifi reload && /etc/init.d/network restart"
```

---

## Netzwerk-Topologie nach Migration

```
Umbrel-Server (192.168.10.147)
  └── LAN/WiFi-Netz (192.168.10.0/24)
         └── GL-BE3600 (Slate 7)
               ├── WiFi-Client: wlan0  → 192.168.10.194 (HTP-1-2.4G)
               ├── LAN-Port:   eth1   → 192.168.10.193 (optional, kein NanoPi mehr)
               ├── USB:        CDP+   → /dev/ttyUSB0
               ├── Port 3240:  USB/IP → Autocom CDP+ Export
               └── Port 8765:  FastAPI → OBD2 Live-Daten
```

---

---

## SSH-Management (Vollständige Fernsteuerung)

Alle Befehle werden **lokal** ausgeführt — der Router wird ausschließlich per SSH konfiguriert.

### Ersteinrichtung (einmalig)

```bash
chmod +x ssh-manager.sh setup-vpn.sh
./ssh-manager.sh setup
```

Das Skript führt interaktiv durch alle Phasen:
- SSH-Key einrichten (empfohlen)
- Dateien übertragen
- OBD2-Service + Display-Service installieren
- WiFi konfigurieren
- Statische IPs setzen
- Verifikation

### Steuerungsbefehle

```bash
# Verbindung (Standard-IP oder nach WiFi-Setup)
./ssh-manager.sh -h 192.168.10.194 status
./ssh-manager.sh -h 192.168.10.194 -k ~/.ssh/id_rsa status  # mit SSH-Key

# Services
./ssh-manager.sh restart all          # Alle Services neu starten
./ssh-manager.sh restart obd          # Nur OBD-Monitor
./ssh-manager.sh restart display      # Nur Touchscreen-Display
./ssh-manager.sh stop display         # Display-Service (gl_screen übernimmt)

# Monitoring
./ssh-manager.sh logs 100             # Letzte 100 Logzeilen
./ssh-manager.sh follow               # Live-Logs (STRG+C zum Beenden)
./ssh-manager.sh obd                  # OBD2 Live-Daten
./ssh-manager.sh bind                 # CDP+ binden
./ssh-manager.sh ip                   # Netzwerk-IPs

# Interaktiv
./ssh-manager.sh shell                # SSH-Shell öffnen
./ssh-manager.sh run "obd-ctl status" # Beliebigen Befehl ausführen
```

### obd-ctl (auf dem Router)

Nach dem `deploy` ist `obd-ctl` unter `/usr/local/bin/obd-ctl` verfügbar:

```bash
# Direkt auf dem Router (via SSH-Shell)
obd-ctl status
obd-ctl restart obd
obd-ctl logs 50
obd-ctl obd
obd-ctl dtcs
obd-ctl bind
obd-ctl display next

# Oder remote (einzeilig)
./ssh-manager.sh run "obd-ctl status"
./ssh-manager.sh run "obd-ctl display off"
```

### SSH-Key einrichten (ohne Passwort)

```bash
# SSH-Key generieren (falls noch nicht vorhanden)
ssh-keygen -t ed25519 -f ~/.ssh/gl-be3600 -C "GL-BE3600"

# Key auf Router einrichten
./ssh-manager.sh setup-key ~/.ssh/gl-be3600.pub

# Künftig ohne Passwort verbinden
./ssh-manager.sh -h 192.168.10.194 -k ~/.ssh/gl-be3600 status
```

---

## VPN (optional)

### Tailscale — empfohlen (kein eigener Server nötig)

```bash
# 1. Auth-Key holen: https://login.tailscale.com/admin/settings/keys
# 2. Tailscale installieren + einrichten
./setup-vpn.sh --tailscale -t tskey-auth-xxxx

# Mit Heimnetz-Zugang (Umbrel + Router über Tailnet erreichbar)
./setup-vpn.sh --tailscale -t tskey-auth-xxxx --subnet
```

**Nach der Einrichtung:**
```bash
# Router via Tailscale-IP erreichbar (100.x.x.x)
./ssh-manager.sh -h 100.x.x.x status
obd-ctl vpn status       # Tailscale Status
obd-ctl vpn peers        # Alle Tailnet-Geräte
obd-ctl vpn subnet       # Heimnetz exponieren (nach Admin-Freigabe)
```

> **Subnet Routing:** Im [Tailscale Admin-Panel](https://login.tailscale.com/admin/machines)
> → `gl-be3600-obd` → **Edit route settings** → `192.168.10.0/24` aktivieren.
> Danach ist der Umbrel-Server und die OBD2-API von überall via Tailnet erreichbar.

### WireGuard — bestehende Config importieren

```bash
./setup-vpn.sh -c ~/meine-vpn-config.conf
```

### WireGuard — Router als Server

```bash
./setup-vpn.sh --server
# Generiert Keys + Config, öffnet UDP/51820
```

---

## Troubleshooting

### OBD-Service startet nicht
```bash
logread | grep obd-monitor    # Service-Logs
ls /mnt/usb/obd-pkgs/        # pip-Pakete vorhanden?
python3 -c "import fastapi"  # Import-Test
```

### USB/IP: Kernel-Module nicht gefunden
```bash
lsmod | grep usbip            # Module geladen?
dmesg | grep -i usbip         # Kernel-Meldungen
ls /tmp/kmod-usbip*.ipk       # IPK-Dateien vorhanden?
```

### CDP+ nicht erkannt
```bash
lsusb                          # → 0403:d6da muss erscheinen
ls /dev/ttyUSB*                # → /dev/ttyUSB0 erwartet
dmesg | grep FTDI              # FTDI-Treiber geladen?
```

### Python-Pakete fehlen auf USB-Stick
```bash
df -h /mnt/usb                 # Freier Speicher?
ls /mnt/usb/obd-pkgs/          # Pakete vorhanden?
PYTHONPATH=/mnt/usb/obd-pkgs python3 -c "import fastapi, uvicorn, serial"
```
