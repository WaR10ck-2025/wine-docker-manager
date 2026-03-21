#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# OBD2 Monitor — OpenWrt Setup-Skript für GL.iNet GL-BE10000 (Slate 7 Pro)
#
# ⚠️ PROTOTYPE: Hardware noch nicht allgemein verfügbar.
#    Konfigurationswerte mit # TODO: verify on hardware markiert.
#
# Unterschied zu GL-BE3600: eMMC → Python-venv auf Flash (kein USB-Stick!)
# Unterschied zu GL-E5800:  Kein 5G Modem, 2.8" Display 320×240
#
# Auf dem GL-BE10000 als root ausführen:
#   scp install_obd_openwrt.sh root@192.168.10.196:/tmp/
#   ssh root@192.168.10.196 "sh /tmp/install_obd_openwrt.sh"
#
# Idempotent: mehrfach ausführbar ohne Schaden.
# ─────────────────────────────────────────────────────────────────────────────

set -e

INSTALL_DIR="/opt/obd-monitor"
VENV_DIR="/opt/obd-venv"
INIT_SCRIPT="/etc/init.d/obd-monitor"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo "${GREEN}[obd]${NC} $1"; }
warning() { echo "${YELLOW}[obd]${NC} $1"; }
err()     { echo "${RED}[obd]${NC} $1"; exit 1; }

[ "$(id -u)" = "0" ] || err "Bitte als root ausführen"

info "OBD2 Monitor Setup — GL.iNet GL-BE10000 (Slate 7 Pro — PROTOTYPE)"
info "HINWEIS: Hardware-Specs vorläufig — TODO: verify on hardware"
echo ""

# ── 1. Speicher prüfen (eMMC erwartet, TODO: verify on hardware) ──────────────
info "[1/6] Prüfe verfügbaren eMMC-Speicher..."

# TODO: verify on hardware — Storage-Typ und Kapazität prüfen
FREE_MB=$(df /opt 2>/dev/null | awk 'NR==2{printf "%d", $4/1024}' || echo 0)
if [ "$FREE_MB" -lt 200 ]; then
    warning "Weniger als 200 MB frei auf /opt (${FREE_MB} MB). Prüfe Speicher: df -h"
    warning "Falls eMMC zu klein: pip --target /mnt/usb/obd-pkgs als Fallback"
else
    info "      Freier Speicher: ${FREE_MB} MB ✓"
fi

mkdir -p "$VENV_DIR"

# ── 2. opkg: Python3 installieren ───────────────────────────────────────────
info "[2/6] Installiere Python3 via opkg..."

opkg update -q 2>/dev/null || warning "opkg update fehlgeschlagen (offline?)"

if ! command -v python3 > /dev/null 2>&1; then
    opkg install python3 python3-pip || err "Python3-Installation fehlgeschlagen"
    info "      python3 installiert ✓"
else
    info "      python3 bereits vorhanden: $(python3 --version 2>&1)"
fi

# ── 3. Python-venv auf eMMC erstellen ────────────────────────────────────────
info "[3/6] Erstelle Python-venv in $VENV_DIR..."

if [ -f "$VENV_DIR/bin/activate" ]; then
    info "      venv bereits vorhanden ✓"
else
    python3 -m venv "$VENV_DIR" 2>/dev/null || {
        opkg install python3-venv 2>/dev/null || true
        python3 -m venv "$VENV_DIR" || err "venv-Erstellung fehlgeschlagen"
    }
    info "      venv erstellt ✓"
fi

"$VENV_DIR/bin/pip" install --quiet --upgrade pip 2>/dev/null || true

if "$VENV_DIR/bin/python3" -c "import fastapi, uvicorn, serial" 2>/dev/null; then
    info "      Pakete bereits installiert ✓"
else
    info "      Installiere Python-Pakete ins venv..."
    "$VENV_DIR/bin/pip" install \
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
    "$VENV_DIR/bin/pip" install \
        --no-compile \
        "fastapi" "uvicorn" "pyserial" "python-obd" || \
    err "pip install fehlgeschlagen. Prüfe: df -h /opt"
    info "      Pakete installiert ✓"
fi

# ── 4. OBD-Code installieren ─────────────────────────────────────────────────
info "[4/6] Kopiere OBD2-Monitor-Code nach $INSTALL_DIR..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OBD_SRC=""

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

if [ -f "$SCRIPT_DIR/obd-monitor" ]; then
    cp "$SCRIPT_DIR/obd-monitor" "$INIT_SCRIPT"
else
    cat > "$INIT_SCRIPT" << 'INITD'
#!/bin/sh /etc/rc.common
# OBD2 Monitor Service — GL.iNet GL-BE10000 (Slate 7 Pro)
# Generiert von install_obd_openwrt.sh

USE_PROCD=1
START=95
STOP=10

VENV_DIR="/opt/obd-venv"
INSTALL_DIR="/opt/obd-monitor"

start_service() {
    procd_open_instance
    procd_set_param command "$VENV_DIR/bin/uvicorn" obd_service:app \
        --host 0.0.0.0 \
        --port 8765 \
        --workers 1 \
        --log-level warning
    procd_set_param dir "$INSTALL_DIR"
    procd_set_param respawn 3600 5 5
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

if netstat -tln 2>/dev/null | grep -q ':8765' || \
   ss -tln 2>/dev/null | grep -q ':8765'; then
    info "      OBD2 Service läuft auf Port 8765 ✓"
else
    warning "Port 8765 noch nicht offen. Service startet evtl. noch."
    warning "Log: logread | grep obd"
fi

# ── Zusammenfassung ───────────────────────────────────────────────────────────
WIFI_IP=$(ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 || true)
LAN_IP=$(ip addr show br-lan 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 || echo "192.168.10.191")

echo ""
info "═══════════════════════════════════════════════"
info "Setup abgeschlossen! [PROTOTYPE]"
info ""
info "GL-BE10000 LAN-IP:   ${LAN_IP}"
[ -n "$WIFI_IP" ] && info "GL-BE10000 WiFi-IP:  ${WIFI_IP}"
info "OBD2 Port:           8765"
info "Python-venv:         $VENV_DIR"
info ""
info "Test:"
info "  curl http://${WIFI_IP:-${LAN_IP}}:8765/obd/status"
info ""
info "In docker-compose.yml setzen:"
info "  OBD_MONITOR_HOST: \"${WIFI_IP:-<wifi-ip-nach-setup>}\""
info ""
info "TODO: verify on hardware — Prototype!"
info "Logs:"
info "  logread | grep -i obd"
info "═══════════════════════════════════════════════"
