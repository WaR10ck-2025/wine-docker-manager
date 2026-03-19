#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# USB/IP Server — Headless Mini-PC Setup
# Teilt den Autocom CDP+ (FTDI 0403:d6da) über das Netzwerk (Port 3240).
# Unterstützt: Debian, Ubuntu, Raspberry Pi OS
# Idempotent: mehrfach ausführbar ohne Schaden
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

# Root-Prüfung
[ "$(id -u)" = "0" ] || error "Bitte als root ausführen: sudo bash install.sh"

info "USB/IP Server Setup für Autocom CDP+ (FTDI ${AUTOCOM_VENDOR}:${AUTOCOM_PRODUCT})"
echo ""

# ── 1. Paketquellen & Installation ──────────────────────────────────────────
info "Installiere USB/IP Tools..."
apt-get update -qq

# linux-tools-generic enthält usbip auf Ubuntu/Debian
# Raspberry Pi OS: usbip ist in linux-tools-common oder rpi-usbip
if apt-cache show linux-tools-generic &>/dev/null; then
    apt-get install -y --no-install-recommends linux-tools-generic linux-tools-common kmod
elif apt-cache show usbip &>/dev/null; then
    apt-get install -y --no-install-recommends usbip kmod
else
    # Fallback: linux-tools für aktuellen Kernel
    KERNEL=$(uname -r)
    apt-get install -y --no-install-recommends "linux-tools-${KERNEL}" linux-tools-common kmod || \
        error "Konnte usbip nicht installieren. Bitte manuell: apt-get install usbip"
fi

# usbipd-Binär suchen
USBIPD_BIN=""
for p in /usr/sbin/usbipd /usr/bin/usbipd /usr/lib/linux-tools/*/usbipd; do
    [ -x "$p" ] && USBIPD_BIN="$p" && break
done
[ -n "$USBIPD_BIN" ] || error "usbipd nicht gefunden nach Installation."
info "usbipd gefunden: $USBIPD_BIN"

USBIP_BIN=""
for p in /usr/sbin/usbip /usr/bin/usbip /usr/lib/linux-tools/*/usbip; do
    [ -x "$p" ] && USBIP_BIN="$p" && break
done
[ -n "$USBIP_BIN" ] || error "usbip nicht gefunden nach Installation."

# ── 2. Kernel-Module laden ───────────────────────────────────────────────────
info "Lade Kernel-Module..."
modprobe usbip-core  || warning "usbip-core konnte nicht geladen werden"
modprobe usbip-host  || warning "usbip-host konnte nicht geladen werden"

# Persistent machen
grep -q "usbip-core" "$MODULES_FILE" || echo "usbip-core" >> "$MODULES_FILE"
grep -q "usbip-host" "$MODULES_FILE" || echo "usbip-host" >> "$MODULES_FILE"
info "Kernel-Module werden beim Boot geladen (${MODULES_FILE})"

# ── 3. Systemd Service ───────────────────────────────────────────────────────
info "Richte systemd Service ein..."
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=USB/IP Server (Autocom CDP+ Headless)
After=network.target
Wants=network.target

[Service]
Type=forking
ExecStartPre=/sbin/modprobe usbip-core
ExecStartPre=/sbin/modprobe usbip-host
ExecStart=${USBIPD_BIN} -D
ExecStartPost=/bin/bash -c 'sleep 2 && BID=\$(${USBIP_BIN} list -l 2>/dev/null | grep "${AUTOCOM_VENDOR}:${AUTOCOM_PRODUCT}" | grep -oP "(?<=busid )\\S+" | head -1) && [ -n "\$BID" ] && ${USBIP_BIN} bind --busid "\$BID" && echo "[usbip] Gerät \$BID gebunden" || echo "[usbip] Gerät nicht gefunden (noch nicht eingesteckt?)"'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable usbipd.service
info "Service aktiviert: usbipd.service"

# ── 4. udev-Regel für Auto-Bind beim Einstecken ──────────────────────────────
info "Richte udev-Regel ein (Auto-Bind bei USB-Einstecken)..."
cat > "$UDEV_RULE" << EOF
# Autocom CDP+ (FTDI ${AUTOCOM_VENDOR}:${AUTOCOM_PRODUCT}) — USB/IP Auto-Bind
ACTION=="add", SUBSYSTEM=="usb", \
  ATTR{idVendor}=="${AUTOCOM_VENDOR}", ATTR{idProduct}=="${AUTOCOM_PRODUCT}", \
  RUN+="/bin/systemctl restart usbipd.service"
EOF
udevadm control --reload-rules
info "udev-Regel installiert: $UDEV_RULE"

# ── 5. Service starten ───────────────────────────────────────────────────────
info "Starte USB/IP Server..."
systemctl restart usbipd.service
sleep 2

# Status ausgeben
if systemctl is-active --quiet usbipd.service; then
    info "usbipd läuft ✓"
else
    warning "usbipd hat Probleme — prüfe: journalctl -u usbipd.service"
fi

# Geräte anzeigen
echo ""
info "Verfügbare USB-Geräte:"
${USBIP_BIN} list -l 2>/dev/null || true

# ── 6. Netzwerk-Info ─────────────────────────────────────────────────────────
echo ""
IP=$(hostname -I | awk '{print $1}')
info "──────────────────────────────────────────"
info "Mini-PC IP-Adresse:  ${IP}"
info "USB/IP Port:          3240"
info ""
info "Diesen Wert in docker-compose.yml setzen:"
info "  USBIP_REMOTE_HOST: \"${IP}\""
info ""
info "Windows VM (einmalig, in der VM ausführen):"
info "  .\\windows-usbip-autoconnect.ps1 -MiniPcIp ${IP}"
info "──────────────────────────────────────────"
