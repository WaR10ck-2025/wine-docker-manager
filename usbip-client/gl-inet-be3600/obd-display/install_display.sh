#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# OBD2 Display — Installationsskript für GL.iNet GL-BE3600 (Slate 7)
#
# Installiert display_service.py und den zugehörigen init.d-Service.
# Benötigt: USB-Stick unter /mnt/usb (für Pillow-Pakete, ~15 MB)
#           obd-monitor bereits installiert (install_obd_openwrt.sh)
#
# Ausführen auf dem Router:
#   scp -r obd-display/ root@192.168.8.1:/tmp/obd-display/
#   ssh root@192.168.8.1 "sh /tmp/obd-display/install_display.sh"
#
# Idempotent: mehrfach ausführbar.
# ─────────────────────────────────────────────────────────────────────────────

set -e

INSTALL_DIR="/opt/obd-monitor"
USB_PKG_DIR="/mnt/usb/obd-pkgs"
INIT_SCRIPT="/etc/init.d/obd-display"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo "${GREEN}[display]${NC} $1"; }
warning() { echo "${YELLOW}[display]${NC} $1"; }
err()     { echo "${RED}[display]${NC} $1"; exit 1; }

[ "$(id -u)" = "0" ] || err "Bitte als root ausführen"

info "OBD2 Display Setup — GL.iNet GL-BE3600"
echo ""

# ── 1. Voraussetzungen prüfen ─────────────────────────────────────────────────
info "[1/5] Prüfe Voraussetzungen..."

# Framebuffer vorhanden?
if [ ! -e /dev/fb0 ]; then
    err "/dev/fb0 nicht gefunden. Kein Framebuffer auf diesem Gerät?"
fi
info "      /dev/fb0 gefunden ✓"

# obd-monitor installiert?
if [ ! -f "$INSTALL_DIR/obd_service.py" ]; then
    err "obd-monitor nicht installiert. Bitte erst install_obd_openwrt.sh ausführen."
fi
info "      obd-monitor gefunden ✓"

# USB-Stick gemountet?
if [ ! -d "$USB_PKG_DIR" ]; then
    warning "USB-Stick-Pakete nicht unter $USB_PKG_DIR gefunden."
    warning "Stelle sicher, dass USB-Stick eingesteckt und gemountet ist."
    warning "Falls pip-Pakete fehlen, display_service.py kann nicht starten."
else
    info "      USB-Stick-Pakete: $USB_PKG_DIR ✓"
fi

# ── 2. Pillow installieren ────────────────────────────────────────────────────
info "[2/5] Installiere Pillow (PIL) auf USB-Stick..."

mkdir -p "$USB_PKG_DIR"

# Prüfen ob Pillow schon vorhanden
if PYTHONPATH="$USB_PKG_DIR" python3 -c "from PIL import Image, ImageDraw, ImageFont" 2>/dev/null; then
    info "      Pillow bereits installiert ✓"
else
    info "      Installiere Pillow (~15 MB)..."
    python3 -m pip install \
        --target "$USB_PKG_DIR" \
        --no-compile \
        --quiet \
        "Pillow" || {
        warning "Pillow-Installation fehlgeschlagen."
        warning "Versuche ohne optionale Dependencies..."
        python3 -m pip install \
            --target "$USB_PKG_DIR" \
            --no-compile \
            --no-binary :all: \
            "Pillow" || \
        err "Pillow konnte nicht installiert werden. Prüfe: df -h /mnt/usb"
    }
    info "      Pillow installiert ✓"
fi

# Pillow-Funktion testen
if PYTHONPATH="$USB_PKG_DIR" python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (76, 284), (0, 0, 0))
d = ImageDraw.Draw(img)
d.text((2, 2), 'TEST', fill=(255, 255, 255))
print('OK')
" 2>/dev/null | grep -q OK; then
    info "      Pillow-Test erfolgreich ✓"
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

chmod +x "$INIT_SCRIPT"
/etc/init.d/obd-display enable
info "      Service aktiviert ✓"

# ── 5. Service starten ────────────────────────────────────────────────────────
info "[5/5] Starte OBD2 Display Service..."

# gl_screen stoppen (muss vor obd-display gestoppt sein)
/etc/init.d/gl_screen stop 2>/dev/null || true
sleep 1

/etc/init.d/obd-display restart 2>/dev/null || /etc/init.d/obd-display start
sleep 3

# Prüfen ob der Prozess läuft
if pgrep -f display_service.py > /dev/null 2>&1; then
    info "      Display Service läuft ✓"
else
    warning "Service nicht gestartet. Logs: logread | grep -i obd-display"
fi

# ── Zusammenfassung ────────────────────────────────────────────────────────────
echo ""
info "═══════════════════════════════════════════════"
info "Display Setup abgeschlossen!"
info ""
info "GL-BE3600 Touchscreen zeigt jetzt:"
info "  Bildschirm 0: Status (WiFi, OBD, USB/IP)"
info "  Bildschirm 1: OBD Live (RPM, Speed, Temp)"
info "  Bildschirm 2: Kraftstoff & Batterie"
info "  Bildschirm 3: Steuerung (CDP+ binden, Restart)"
info ""
info "Bedienung:"
info "  Tap         → Nächsten Bildschirm"
info "  Lang halten → Steuerungs-Bildschirm"
info ""
info "Logs:"
info "  logread | grep -i 'obd-display\\|\\[display\\]'"
info "  logread -f"
info ""
info "Service stoppen (gl_screen wiederherstellen):"
info "  /etc/init.d/obd-display stop"
info ""
info "Deinstallieren:"
info "  sh restore_openwrt.sh soft"
info "═══════════════════════════════════════════════"
