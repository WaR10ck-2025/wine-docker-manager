#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# OBD2 Display — Installationsskript für GL.iNet GL-E5800 (Mudi 7)
#
# Unterschied zu GL-BE3600: Pillow wird ins venv installiert (kein USB-Stick)
#
# Ausführen auf dem Router:
#   scp -r obd-display/ root@192.168.8.1:/tmp/obd-display/
#   ssh root@192.168.8.1 "sh /tmp/obd-display/install_display.sh"
#
# Display-Auflösung vor Setup auslesen:
#   ssh root@192.168.8.1 "cat /sys/class/graphics/fb0/virtual_size"
#
# Idempotent: mehrfach ausführbar.
# ─────────────────────────────────────────────────────────────────────────────

set -e

VENV_DIR="/opt/obd-venv"
INSTALL_DIR="/opt/obd-monitor"
INIT_SCRIPT="/etc/init.d/obd-display"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo "${GREEN}[display]${NC} $1"; }
warning() { echo "${YELLOW}[display]${NC} $1"; }
err()     { echo "${RED}[display]${NC} $1"; exit 1; }

[ "$(id -u)" = "0" ] || err "Bitte als root ausführen"

info "OBD2 Display Setup — GL.iNet GL-E5800 (Mudi 7)"
echo ""

# ── 0. Display-Auflösung ermitteln ────────────────────────────────────────────
info "[0/5] Display-Auflösung auslesen..."

if [ -f /sys/class/graphics/fb0/virtual_size ]; then
    FB_SIZE=$(cat /sys/class/graphics/fb0/virtual_size)
    FB_W=$(echo "$FB_SIZE" | cut -d',' -f1)
    FB_H=$(echo "$FB_SIZE" | cut -d',' -f2)
    info "      Framebuffer: ${FB_W}×${FB_H}px (aus /sys/class/graphics/fb0/virtual_size)"
    info "      Wird als FB_WIDTH=${FB_W} FB_HEIGHT=${FB_H} in init.d gesetzt"
else
    FB_W=240
    FB_H=320
    warning "Framebuffer-Größe nicht lesbar → Standardwert ${FB_W}×${FB_H}"
    warning "Manuell anpassen: /etc/init.d/obd-display (FB_WIDTH/FB_HEIGHT)"
fi

# ── 1. Voraussetzungen prüfen ─────────────────────────────────────────────────
info "[1/5] Prüfe Voraussetzungen..."

if [ ! -e /dev/fb0 ]; then
    err "/dev/fb0 nicht gefunden. Kein Framebuffer auf diesem Gerät?"
fi
info "      /dev/fb0 gefunden ✓"

if [ ! -f "$INSTALL_DIR/obd_service.py" ]; then
    err "obd-monitor nicht installiert. Bitte erst install_obd_openwrt.sh ausführen."
fi
info "      obd-monitor gefunden ✓"

if [ ! -f "$VENV_DIR/bin/python3" ]; then
    err "venv nicht gefunden ($VENV_DIR). install_obd_openwrt.sh erst ausführen."
fi
info "      venv gefunden: $VENV_DIR ✓"

# ── 2. Pillow ins venv installieren ──────────────────────────────────────────
info "[2/5] Installiere Pillow ins venv..."

if "$VENV_DIR/bin/python3" -c "from PIL import Image, ImageDraw, ImageFont" 2>/dev/null; then
    info "      Pillow bereits installiert ✓"
else
    info "      Installiere Pillow (~15 MB)..."
    "$VENV_DIR/bin/pip" install --quiet "Pillow" || {
        warning "Pillow-Installation fehlgeschlagen — versuche ohne optionale Abhängigkeiten..."
        "$VENV_DIR/bin/pip" install --quiet --no-binary :all: "Pillow" || \
        err "Pillow konnte nicht installiert werden. Prüfe: df -h /opt"
    }
    info "      Pillow installiert ✓"
fi

# Pillow-Funktion testen
if "$VENV_DIR/bin/python3" -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', ($FB_W, $FB_H), (0, 0, 0))
d = ImageDraw.Draw(img)
d.text((2, 2), 'TEST', fill=(255, 255, 255))
print('OK')
" 2>/dev/null | grep -q OK; then
    info "      Pillow-Test (${FB_W}×${FB_H}) erfolgreich ✓"
else
    warning "Pillow-Test fehlgeschlagen — Service startet möglicherweise nicht."
fi

# ── 3. display_service.py installieren ───────────────────────────────────────
info "[3/5] Kopiere display_service.py nach $INSTALL_DIR..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "$SCRIPT_DIR/display_service.py" ]; then
    cp "$SCRIPT_DIR/display_service.py" "$INSTALL_DIR/"
    info "      display_service.py kopiert ✓"
else
    err "display_service.py nicht gefunden in $SCRIPT_DIR"
fi

# ── 4. init.d Service installieren ───────────────────────────────────────────
info "[4/5] Installiere init.d Service..."

if [ -f "$SCRIPT_DIR/obd-display" ]; then
    cp "$SCRIPT_DIR/obd-display" "$INIT_SCRIPT"
else
    err "obd-display init.d-Skript nicht gefunden in $SCRIPT_DIR"
fi

# ENV-Variablen mit erkannter Auflösung in init.d eintragen
# Suche procd_set_param env Zeile und ergänze FB_WIDTH/FB_HEIGHT
if grep -q 'procd_set_param command' "$INIT_SCRIPT"; then
    # ENV-Zeile einfügen falls noch nicht vorhanden
    if ! grep -q 'FB_WIDTH' "$INIT_SCRIPT"; then
        sed -i "s|procd_set_param command|procd_set_param env FB_WIDTH=${FB_W} FB_HEIGHT=${FB_H}\n    procd_set_param command|" "$INIT_SCRIPT" 2>/dev/null || true
    fi
fi

chmod +x "$INIT_SCRIPT"
/etc/init.d/obd-display enable
info "      Service aktiviert ✓"

# ── 5. Service starten ────────────────────────────────────────────────────────
info "[5/5] Starte OBD2 Display Service..."

# gl_screen stoppen (falls vorhanden)
[ -f /etc/init.d/gl_screen ] && /etc/init.d/gl_screen stop 2>/dev/null || true
sleep 1

/etc/init.d/obd-display restart 2>/dev/null || /etc/init.d/obd-display start
sleep 3

if pgrep -f display_service.py > /dev/null 2>&1; then
    info "      Display Service läuft ✓"
else
    warning "Service nicht gestartet. Logs: logread | grep -i 'obd-display'"
fi

# ── Zusammenfassung ────────────────────────────────────────────────────────────
echo ""
info "═══════════════════════════════════════════════"
info "Display Setup abgeschlossen!"
info ""
info "GL-E5800 Touchscreen (${FB_W}×${FB_H}px) zeigt jetzt:"
info "  Bildschirm 0: Status (WiFi, 5G, OBD, USB/IP)"
info "  Bildschirm 1: OBD Live (RPM, Speed, Temp)"
info "  Bildschirm 2: Kraftstoff & Batterie"
info "  Bildschirm 3: Steuerung (Adapter binden, Restart)"
info ""
info "Falls Auflösung falsch: FB_WIDTH/FB_HEIGHT in init.d anpassen"
info "  Systemwert: cat /sys/class/graphics/fb0/virtual_size"
info ""
info "Logs:"
info "  logread | grep -i 'obd-display\\|\\[display\\]'"
info "═══════════════════════════════════════════════"
