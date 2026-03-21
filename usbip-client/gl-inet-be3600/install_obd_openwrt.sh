#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# OBD2 Monitor — OpenWrt Setup-Skript für GL.iNet GL-BE3600 (Slate 7)
#
# Installiert den OBD2-Service (HTTP API auf Port 8765) auf OpenWrt.
# Python-Pakete werden auf dem USB-Stick installiert (Flash zu klein).
#
# Auf dem GL-BE3600 als root ausführen:
#   scp install_obd_openwrt.sh root@192.168.8.1:/tmp/
#   ssh root@192.168.8.1 "sh /tmp/install_obd_openwrt.sh"
#
# Idempotent: mehrfach ausführbar ohne Schaden.
# ─────────────────────────────────────────────────────────────────────────────

set -e

INSTALL_DIR="/opt/obd-monitor"
USB_PKG_DIR="/mnt/usb/obd-pkgs"
USB_MOUNT="/mnt/usb"
INIT_SCRIPT="/etc/init.d/obd-monitor"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo "${GREEN}[obd]${NC} $1"; }
warning() { echo "${YELLOW}[obd]${NC} $1"; }
err()     { echo "${RED}[obd]${NC} $1"; exit 1; }

[ "$(id -u)" = "0" ] || err "Bitte als root ausführen"

info "OBD2 Monitor Setup — GL.iNet GL-BE3600 (OpenWrt)"
echo ""

# ── 1. USB-Stick prüfen und mounten ─────────────────────────────────────────
info "[1/6] USB-Stick prüfen..."

mkdir -p "$USB_MOUNT"

# Bereits gemountet?
if mount | grep -q "$USB_MOUNT"; then
    info "      USB-Stick bereits unter $USB_MOUNT gemountet"
else
    # Block-Device suchen (/dev/sda1, /dev/sdb1 etc.)
    USB_DEV=""
    for dev in /dev/sda1 /dev/sdb1 /dev/sdc1; do
        if [ -b "$dev" ]; then
            USB_DEV="$dev"
            break
        fi
    done

    if [ -z "$USB_DEV" ]; then
        err "Kein USB-Stick gefunden. Bitte USB-Stick einstecken und erneut ausführen."
    fi

    mount "$USB_DEV" "$USB_MOUNT" 2>/dev/null || {
        # Versuche mit explizitem Dateisystem
        mount -t vfat "$USB_DEV" "$USB_MOUNT" 2>/dev/null || \
        mount -t ext4 "$USB_DEV" "$USB_MOUNT" || \
        err "USB-Stick konnte nicht gemountet werden: $USB_DEV"
    }
    info "      Gemountet: $USB_DEV → $USB_MOUNT"
fi

# USB-Automount beim Boot einrichten (fstab)
if ! grep -q "$USB_MOUNT" /etc/config/fstab 2>/dev/null; then
    info "      Richte USB-Automount ein..."
    # block detect erzeugt fstab-Einträge basierend auf angesteckten Geräten
    block detect 2>/dev/null | uci import fstab 2>/dev/null || true
    # Mount-Point auf /mnt/usb setzen
    USB_UUID=$(block info 2>/dev/null | grep "$USB_DEV" | grep -o 'UUID="[^"]*"' | cut -d'"' -f2 || true)
    if [ -n "$USB_UUID" ]; then
        UCI_IDX=$(uci show fstab 2>/dev/null | grep "$USB_UUID" | grep -o 'fstab.@mount\[[0-9]*\]' | head -1 | grep -o '\[[0-9]*\]' | tr -d '[]' || true)
        if [ -n "$UCI_IDX" ]; then
            uci set "fstab.@mount[$UCI_IDX].target=$USB_MOUNT" 2>/dev/null || true
            uci set "fstab.@mount[$UCI_IDX].enabled=1" 2>/dev/null || true
            uci commit fstab 2>/dev/null || true
        fi
    fi
    /etc/init.d/fstab enable 2>/dev/null || true
    info "      Automount konfiguriert"
fi

# ── 2. opkg: Python3 installieren ───────────────────────────────────────────
info "[2/6] Installiere Python3 via opkg..."

opkg update -q 2>/dev/null || warning "opkg update fehlgeschlagen (offline?)"

# Python3 installieren (idempotent)
if ! command -v python3 > /dev/null 2>&1; then
    opkg install python3 python3-pip || err "Python3-Installation fehlgeschlagen"
    info "      python3 installiert ✓"
else
    info "      python3 bereits vorhanden: $(python3 --version 2>&1)"
fi

# pip sicherstellen
if ! python3 -m pip --version > /dev/null 2>&1; then
    opkg install python3-pip 2>/dev/null || \
    python3 -m ensurepip --upgrade 2>/dev/null || \
    warning "pip nicht verfügbar — wird über get-pip.py versucht"
    # Fallback: get-pip.py
    if ! python3 -m pip --version > /dev/null 2>&1; then
        wget -qO /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py && python3 /tmp/get-pip.py
    fi
fi
info "      pip verfügbar ✓"

# ── 3. Python-Pakete auf USB-Stick installieren ──────────────────────────────
info "[3/6] Installiere Python-Pakete auf $USB_PKG_DIR..."

mkdir -p "$USB_PKG_DIR"

# Prüfen ob Pakete schon installiert sind
if python3 -c "import sys; sys.path.insert(0,'$USB_PKG_DIR'); import fastapi, uvicorn, serial" 2>/dev/null; then
    info "      Pakete bereits installiert ✓"
else
    # --no-build-isolation verhindert Speicherprobleme bei kleinen Geräten
    python3 -m pip install \
        --target "$USB_PKG_DIR" \
        --no-compile \
        --quiet \
        "fastapi==0.115.0" \
        "uvicorn==0.30.6" \
        "pyserial==3.5" \
        "python-obd==0.7.1" \
        "anyio" \
        "starlette" \
        "sniffio" \
        "h11" \
        "click" \
        2>/dev/null || \
    python3 -m pip install \
        --target "$USB_PKG_DIR" \
        --no-compile \
        "fastapi" "uvicorn" "pyserial" "python-obd" || \
    err "pip install fehlgeschlagen. Prüfe: df -h $USB_MOUNT"

    info "      Pakete installiert ✓"
fi

# ── 4. OBD-Code installieren ─────────────────────────────────────────────────
info "[4/6] Kopiere OBD2-Monitor-Code nach $INSTALL_DIR..."

# Skript-Verzeichnis ermitteln (relativ zum gl-inet-be3600/-Ordner)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OBD_SRC=""

# Mögliche Quell-Pfade
for src in \
    "$SCRIPT_DIR/../obd-monitor" \
    "$(dirname "$SCRIPT_DIR")/obd-monitor" \
    "/tmp/obd-monitor"; do
    if [ -f "$src/obd_service.py" ]; then
        OBD_SRC="$src"
        break
    fi
done

mkdir -p "$INSTALL_DIR/protocols"

if [ -n "$OBD_SRC" ]; then
    cp "$OBD_SRC/obd_service.py"               "$INSTALL_DIR/"
    cp "$OBD_SRC/obd_monitor.py"               "$INSTALL_DIR/" 2>/dev/null || true
    cp "$OBD_SRC/protocols/__init__.py"        "$INSTALL_DIR/protocols/"
    cp "$OBD_SRC/protocols/base.py"            "$INSTALL_DIR/protocols/"
    cp "$OBD_SRC/protocols/elm327.py"          "$INSTALL_DIR/protocols/"
    cp "$OBD_SRC/protocols/iso9141.py"         "$INSTALL_DIR/protocols/"
    info "      Code kopiert von $OBD_SRC ✓"
else
    warning "OBD-Source nicht gefunden. Dateien manuell nach $INSTALL_DIR kopieren:"
    warning "  scp -r usbip-client/obd-monitor/ root@<router-ip>:/tmp/obd-monitor/"
    warning "  Dann dieses Skript erneut ausführen."
fi

# ── 5. init.d Service installieren ───────────────────────────────────────────
info "[5/6] Installiere OpenWrt init.d Service..."

# init.d-Skript aus gl-inet-be3600/ kopieren, falls vorhanden
if [ -f "$SCRIPT_DIR/obd-monitor" ]; then
    cp "$SCRIPT_DIR/obd-monitor" "$INIT_SCRIPT"
else
    # Inline erstellen (Fallback)
    cat > "$INIT_SCRIPT" << 'INITD'
#!/bin/sh /etc/rc.common
# OBD2 Monitor Service — GL.iNet GL-BE3600
# Generiert von install_obd_openwrt.sh

USE_PROCD=1
START=95
STOP=10

USB_PKG_DIR="/mnt/usb/obd-pkgs"
INSTALL_DIR="/opt/obd-monitor"

start_service() {
    procd_open_instance
    procd_set_param env PYTHONPATH="$USB_PKG_DIR"
    procd_set_param command /usr/bin/python3 -m uvicorn obd_service:app \
        --host 0.0.0.0 \
        --port 8765 \
        --workers 1 \
        --log-level warning
    procd_set_param dir "$INSTALL_DIR"
    procd_set_param respawn ${respawn_threshold:-3600} ${respawn_timeout:-5} ${respawn_retry:-5}
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
INITD
fi

chmod +x "$INIT_SCRIPT"
/etc/init.d/obd-monitor enable
info "      Service aktiviert ✓"

# ── 6. Service starten ───────────────────────────────────────────────────────
info "[6/6] Starte OBD2 Monitor..."

/etc/init.d/obd-monitor restart 2>/dev/null || /etc/init.d/obd-monitor start
sleep 3

# Prüfen ob Port offen ist
if netstat -tln 2>/dev/null | grep -q ':8765' || \
   ss -tln 2>/dev/null | grep -q ':8765'; then
    info "      OBD2 Service läuft auf Port 8765 ✓"
else
    warning "Port 8765 noch nicht offen. Service startet evtl. noch."
    warning "Log: logread | grep obd"
fi

# ── Zusammenfassung ───────────────────────────────────────────────────────────
WIFI_IP=$(ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 || true)
LAN_IP=$(ip addr show br-lan 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 || echo "192.168.8.1")

echo ""
info "═══════════════════════════════════════════════"
info "Setup abgeschlossen!"
info ""
info "GL-BE3600 LAN-IP:   ${LAN_IP}"
[ -n "$WIFI_IP" ] && info "GL-BE3600 WiFi-IP:  ${WIFI_IP}"
info "OBD2 Port:          8765"
info ""
info "Test:"
info "  curl http://${WIFI_IP:-${LAN_IP}}:8765/obd/status"
info ""
info "In docker-compose.yml setzen:"
info "  OBD_MONITOR_HOST: \"${WIFI_IP:-<wifi-ip-nach-setup>}\""
info ""
info "Logs:"
info "  logread | grep -i obd"
info "  logread -f"
info "═══════════════════════════════════════════════"
