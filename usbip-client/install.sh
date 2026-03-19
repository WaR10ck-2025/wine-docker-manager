#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# USB/IP Server — Headless Mini-PC Setup
# Teilt den Autocom CDP+ (FTDI 0403:d6da) über das Netzwerk (Port 3240).
#
# Unterstützte Systeme:
#   - DietPi (Debian Bookworm/Bullseye, x86_64)
#   - Debian 11/12
#   - Ubuntu 22.04/24.04
#   - Raspberry Pi OS
#
# Idempotent: mehrfach ausführbar ohne Schaden.
# ─────────────────────────────────────────────────────────────────────────────
set -e

AUTOCOM_VENDOR="0403"
AUTOCOM_PRODUCT="d6da"
SERVICE_FILE="/etc/systemd/system/usbipd.service"
UDEV_RULE="/etc/udev/rules.d/99-autocom-usbip.rules"
MODULES_FILE="/etc/modules"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[usbip]${NC} $1"; }
warning() { echo -e "${YELLOW}[usbip]${NC} $1"; }
error()   { echo -e "${RED}[usbip]${NC} $1"; exit 1; }

[ "$(id -u)" = "0" ] || error "Bitte als root ausführen: sudo bash install.sh"

# OS erkennen
DISTRO="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO="${ID:-unknown}"
fi
info "USB/IP Server Setup — System: ${PRETTY_NAME:-$DISTRO}"
echo ""

# ── 1. Pakete installieren ───────────────────────────────────────────────────
info "Installiere USB/IP Tools..."
apt-get update -qq

# Debian/DietPi: Paket heißt 'usbip' (aus linux-tools-common)
# Ubuntu:        'linux-tools-generic' + 'linux-tools-common'
if [ "$DISTRO" = "ubuntu" ]; then
    KERNEL=$(uname -r)
    apt-get install -y --no-install-recommends \
        linux-tools-common \
        "linux-tools-${KERNEL}" \
        kmod 2>/dev/null || \
    apt-get install -y --no-install-recommends \
        linux-tools-common linux-tools-generic kmod
else
    # Debian / DietPi / Raspberry Pi OS
    apt-get install -y --no-install-recommends usbip kmod
fi

# usbipd-Binär suchen (Pfad je nach Distro verschieden)
USBIPD_BIN=""
for p in \
    /usr/sbin/usbipd \
    /usr/bin/usbipd \
    /usr/lib/linux-tools/*/usbipd \
    /usr/lib/linux-tools-*/usbipd; do
    if [ -x "$p" ]; then
        USBIPD_BIN="$p"
        break
    fi
done

# Fallback: which
if [ -z "$USBIPD_BIN" ]; then
    USBIPD_BIN=$(which usbipd 2>/dev/null || true)
fi
[ -n "$USBIPD_BIN" ] || error "usbipd nicht gefunden. Bitte manuell: apt-get install usbip"

USBIP_BIN=""
for p in \
    /usr/sbin/usbip \
    /usr/bin/usbip \
    /usr/lib/linux-tools/*/usbip \
    /usr/lib/linux-tools-*/usbip; do
    if [ -x "$p" ]; then
        USBIP_BIN="$p"
        break
    fi
done
if [ -z "$USBIP_BIN" ]; then
    USBIP_BIN=$(which usbip 2>/dev/null || true)
fi
[ -n "$USBIP_BIN" ] || error "usbip nicht gefunden."

info "usbipd: $USBIPD_BIN"
info "usbip:  $USBIP_BIN"

# ── 2. Kernel-Module ─────────────────────────────────────────────────────────
info "Lade Kernel-Module..."
modprobe usbip-core 2>/dev/null || warning "usbip-core: Kernel-Modul nicht verfügbar"
modprobe usbip-host 2>/dev/null || warning "usbip-host: Kernel-Modul nicht verfügbar"

# Beim Boot laden
grep -q "usbip-core" "$MODULES_FILE" 2>/dev/null || echo "usbip-core" >> "$MODULES_FILE"
grep -q "usbip-host" "$MODULES_FILE" 2>/dev/null || echo "usbip-host" >> "$MODULES_FILE"

# ── 3. Systemd Service ───────────────────────────────────────────────────────
info "Richte systemd Service ein..."
cat > "$SERVICE_FILE" << UNIT
[Unit]
Description=USB/IP Server (Autocom CDP+ Headless)
After=network.target
Wants=network.target

[Service]
Type=forking
ExecStartPre=/sbin/modprobe usbip-core
ExecStartPre=/sbin/modprobe usbip-host
ExecStart=${USBIPD_BIN} -D
ExecStartPost=/bin/bash -c 'sleep 2 && BID=\$(${USBIP_BIN} list -l 2>/dev/null | grep "${AUTOCOM_VENDOR}:${AUTOCOM_PRODUCT}" | grep -oP "(?<=busid )\\S+" | head -1) && [ -n "\$BID" ] && ${USBIP_BIN} bind --busid "\$BID" && echo "[usbip] Gerät \$BID gebunden" || echo "[usbip] Gerät ${AUTOCOM_VENDOR}:${AUTOCOM_PRODUCT} nicht gefunden (noch nicht eingesteckt?)"'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable usbipd.service
info "Service aktiviert: usbipd.service"

# ── 4. udev-Regel (Auto-Bind bei Einstecken) ────────────────────────────────
info "Richte udev-Regel ein..."
cat > "$UDEV_RULE" << UDEV
# Autocom CDP+ (FTDI ${AUTOCOM_VENDOR}:${AUTOCOM_PRODUCT}) — USB/IP Auto-Bind
ACTION=="add", SUBSYSTEM=="usb", \\
  ATTR{idVendor}=="${AUTOCOM_VENDOR}", ATTR{idProduct}=="${AUTOCOM_PRODUCT}", \\
  RUN+="/bin/systemctl restart usbipd.service"
UDEV
udevadm control --reload-rules
info "udev-Regel installiert: $UDEV_RULE"

# ── 5. Service starten ───────────────────────────────────────────────────────
info "Starte USB/IP Server..."
systemctl restart usbipd.service
sleep 2

if systemctl is-active --quiet usbipd.service; then
    info "usbipd läuft ✓"
else
    warning "usbipd hat Probleme — prüfe: journalctl -u usbipd.service -n 20"
fi

echo ""
info "Verfügbare USB-Geräte:"
$USBIP_BIN list -l 2>/dev/null || warning "usbip list fehlgeschlagen"

# ── 6. Zusammenfassung ───────────────────────────────────────────────────────
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo ""
info "══════════════════════════════════════════════"
info "Setup abgeschlossen!"
info ""
info "Mini-PC IP:   ${IP:-<IP unbekannt>}"
info "USB/IP Port:  3240"
info ""
info "In docker-compose.yml setzen:"
info "  USBIP_REMOTE_HOST: \"${IP:-<mini-pc-ip>}\""
info ""
info "Autocom CDP+ jetzt einstecken — wird automatisch gebunden."
info "Status prüfen: systemctl status usbipd"
info "══════════════════════════════════════════════"
