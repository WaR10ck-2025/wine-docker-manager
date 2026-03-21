#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# OBD2 Display Install — GL.iNet GL-BE10000 (Slate 7 Pro)
#
# ⚠️ PROTOTYPE: Display-Auflösung noch nicht auf echter Hardware verifiziert.
#    Erwartet: 320×240 Querformat (2.8" Display)
#    TODO: verify on hardware — tatsächliche Auflösung prüfen
#
# Installiert display_service.py + Pillow ins venv.
# Liest Auflösung aus Framebuffer-Sys-Interface.
#
# Auf dem GL-BE10000 als root ausführen:
#   scp -r obd-display/ root@192.168.10.196:/opt/obd-display/
#   ssh root@192.168.10.196 "sh /opt/obd-display/install_display.sh"
# ─────────────────────────────────────────────────────────────────────────────

set -e

VENV_DIR="/opt/obd-venv"
INSTALL_DIR="/opt/obd-display"
INIT_SCRIPT="/etc/init.d/obd-display"
# TODO: verify on hardware
DEFAULT_FB_W=320
DEFAULT_FB_H=240

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo "${GREEN}[display]${NC} $1"; }
warning() { echo "${YELLOW}[display]${NC} $1"; }
err()     { echo "${RED}[display]${NC} $1"; exit 1; }

[ "$(id -u)" = "0" ] || err "Bitte als root ausführen"

info "OBD2 Display Setup — GL.iNet GL-BE10000 (Slate 7 Pro — PROTOTYPE)"
echo ""

# ── 1. venv prüfen ───────────────────────────────────────────────────────────
info "[1/4] venv prüfen..."
[ -f "$VENV_DIR/bin/python3" ] || err "venv nicht gefunden. Zuerst install_obd_openwrt.sh ausführen."
info "      venv OK: $VENV_DIR ✓"

# ── 2. Pillow installieren ───────────────────────────────────────────────────
info "[2/4] Pillow installieren..."
if "$VENV_DIR/bin/python3" -c "from PIL import Image" 2>/dev/null; then
    info "      Pillow bereits installiert ✓"
else
    "$VENV_DIR/bin/pip" install --no-compile Pillow 2>/dev/null && \
        info "      Pillow installiert ✓" || \
        err "Pillow-Installation fehlgeschlagen"
fi

# ── 3. Display-Auflösung erkennen ────────────────────────────────────────────
info "[3/4] Display-Auflösung erkennen..."

FB_W="$DEFAULT_FB_W"
FB_H="$DEFAULT_FB_H"

# Auflösung aus Framebuffer-Sys lesen (TODO: verify on hardware)
if [ -f /sys/class/graphics/fb0/virtual_size ]; then
    FB_SIZE=$(cat /sys/class/graphics/fb0/virtual_size)
    FB_W=$(echo "$FB_SIZE" | cut -d',' -f1)
    FB_H=$(echo "$FB_SIZE" | cut -d',' -f2)
    info "      Framebuffer: ${FB_W}×${FB_H} px (aus /sys/class/graphics/fb0/virtual_size)"

    # Sanity-Check (TODO: verify on hardware)
    if [ "$FB_W" != "320" ] || [ "$FB_H" != "240" ]; then
        warning "Auflösung weicht von erwartetem 320×240 ab!"
        warning "Gefunden: ${FB_W}×${FB_H}"
        warning "Prüfen ob Querformat oder Hochformat korrekt ist."
        warning "Falls nötig: obd-display init.d FB_WIDTH/FB_HEIGHT anpassen"
    else
        info "      Auflösung 320×240 bestätigt ✓ (TODO: endgültig verify on hardware)"
    fi
else
    warning "/sys/class/graphics/fb0/virtual_size nicht gefunden"
    warning "Verwende Standard: ${FB_W}×${FB_H} (TODO: verify on hardware)"
fi

# ── 4. Display-Service installieren ─────────────────────────────────────────
info "[4/4] Display-Service installieren..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$INSTALL_DIR"

if [ -f "$SCRIPT_DIR/display_service.py" ]; then
    cp "$SCRIPT_DIR/display_service.py" "$INSTALL_DIR/"
    info "      display_service.py installiert ✓"
else
    err "display_service.py nicht gefunden in $SCRIPT_DIR"
fi

# init.d-Skript kopieren oder aus gl-inet-be10000/ laden
if [ -f "$SCRIPT_DIR/obd-display" ]; then
    cp "$SCRIPT_DIR/obd-display" "$INIT_SCRIPT"
else
    # Inline-Fallback mit erkannter Auflösung
    cat > "$INIT_SCRIPT" << INITD
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=96
STOP=9

VENV_DIR="$VENV_DIR"
INSTALL_DIR="$INSTALL_DIR"

start_service() {
    procd_open_instance
    procd_set_param env FB_WIDTH=$FB_W FB_HEIGHT=$FB_H
    procd_set_param command "\$VENV_DIR/bin/python3" display_service.py
    procd_set_param dir "\$INSTALL_DIR"
    procd_set_param respawn 3600 5 3
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    [ -f /etc/init.d/gl_screen ] && /etc/init.d/gl_screen start 2>/dev/null || true
}
INITD
fi

# FB_WIDTH/FB_HEIGHT in init.d injizieren (falls von Standard abweichend)
if [ "$FB_W" != "320" ] || [ "$FB_H" != "240" ]; then
    warning "Aktualisiere FB_WIDTH=${FB_W} FB_HEIGHT=${FB_H} in $INIT_SCRIPT"
    sed -i "s/FB_WIDTH=[0-9]*/FB_WIDTH=$FB_W/g" "$INIT_SCRIPT" 2>/dev/null || true
    sed -i "s/FB_HEIGHT=[0-9]*/FB_HEIGHT=$FB_H/g" "$INIT_SCRIPT" 2>/dev/null || true
fi

chmod +x "$INIT_SCRIPT"
/etc/init.d/obd-display enable
info "      Display-Service aktiviert ✓"

# Service starten
/etc/init.d/obd-display restart 2>/dev/null || /etc/init.d/obd-display start
sleep 2

echo ""
info "═══════════════════════════════════════════════"
info "Display Setup abgeschlossen! [PROTOTYPE]"
info ""
info "Display:      ${FB_W}×${FB_H} px (Querformat)"
info "Service:      /etc/init.d/obd-display"
info "Logs:         logread | grep -i 'obd-display'"
info ""
info "TODO: verify on hardware"
info "  cat /sys/class/graphics/fb0/virtual_size"
info "  FB_WIDTH=${FB_W} FB_HEIGHT=${FB_H} python3 display_service.py"
info "═══════════════════════════════════════════════"
