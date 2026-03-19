#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# DietPi Automation Script — USB/IP Server für Autocom CDP+
#
# Wird von DietPi automatisch nach dem First-Boot-Setup ausgeführt.
# Installiert den USB/IP-Server ohne manuelle Eingriffe.
#
# Auf die Boot-Partition des USB-Sticks kopieren (neben dietpi.txt).
# ─────────────────────────────────────────────────────────────────────────────
set -e

LOG="/var/log/autocom-usbip-setup.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== Autocom USB/IP Setup Start: $(date) ==="

AUTOCOM_VENDOR="0403"
AUTOCOM_PRODUCT="d6da"
SERVICE_FILE="/etc/systemd/system/usbipd.service"
UDEV_RULE="/etc/udev/rules.d/99-autocom-usbip.rules"

# ── 1. USB/IP Pakete + RTL8822CE WiFi-Firmware installieren ─────────────────
echo "[1/5] Installiere usbip + Realtek WiFi-Firmware (RTL8822CE)..."
apt-get update -qq

# firmware-realtek: enthält rtl8822c_fw.bin für den rtw88_8822ce Treiber
# non-free-firmware Repo aktivieren (Debian Bookworm trennt Firmware in eigene Sektion)
if ! grep -q "non-free-firmware" /etc/apt/sources.list 2>/dev/null; then
    sed -i 's/bookworm main$/bookworm main non-free-firmware/' /etc/apt/sources.list 2>/dev/null || true
    apt-get update -qq
fi

apt-get install -y --no-install-recommends usbip kmod firmware-realtek
echo "      OK"

# rtw88_8822ce Modul laden (WiFi-Treiber für RTL8822CE)
modprobe rtw88_8822ce 2>/dev/null && echo "      rtw88_8822ce geladen ✓" || \
    echo "      rtw88_8822ce: Modul nicht gefunden (Kernel-Version prüfen)"

# usbip-Binaries finden
USBIPD_BIN=$(which usbipd 2>/dev/null || echo "/usr/sbin/usbipd")
USBIP_BIN=$(which usbip 2>/dev/null || echo "/usr/sbin/usbip")
echo "      usbipd: $USBIPD_BIN"
echo "      usbip:  $USBIP_BIN"

# ── 2. Kernel-Module ─────────────────────────────────────────────────────────
echo "[2/6] Lade Kernel-Module..."
modprobe usbip-core 2>/dev/null || echo "      WARNUNG: usbip-core nicht geladen"
modprobe usbip-host 2>/dev/null || echo "      WARNUNG: usbip-host nicht geladen"

grep -q "usbip-core" /etc/modules 2>/dev/null || echo "usbip-core" >> /etc/modules
grep -q "usbip-host" /etc/modules 2>/dev/null || echo "usbip-host" >> /etc/modules
echo "      Module für Boot persistiert"

# ── 3. Systemd Service ───────────────────────────────────────────────────────
echo "[3/6] Erstelle systemd Service..."
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
ExecStartPost=/bin/bash -c 'sleep 2 && BID=\$(${USBIP_BIN} list -l 2>/dev/null | grep "${AUTOCOM_VENDOR}:${AUTOCOM_PRODUCT}" | grep -oP "(?<=busid )\\S+" | head -1) && [ -n "\$BID" ] && ${USBIP_BIN} bind --busid "\$BID" && echo "[usbip] Geraet \$BID gebunden" || echo "[usbip] Geraet nicht gefunden (noch nicht eingesteckt)"'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable usbipd.service
echo "      Service aktiviert"

# ── 4. udev-Regel ────────────────────────────────────────────────────────────
echo "[4/6] Installiere udev-Regel..."
cat > "$UDEV_RULE" << UDEV
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="${AUTOCOM_VENDOR}", ATTR{idProduct}=="${AUTOCOM_PRODUCT}", RUN+="/bin/systemctl restart usbipd.service"
UDEV
udevadm control --reload-rules
echo "      udev-Regel installiert"

# ── 5. Service starten ───────────────────────────────────────────────────────
echo "[5/6] Starte USB/IP Server..."
systemctl start usbipd.service || echo "      WARNUNG: Start fehlgeschlagen (Gerät nicht eingesteckt?)"

# ── 6. WiFi-Status prüfen ────────────────────────────────────────────────────
echo "[6/6] WiFi-Status (RTL8822CE)..."
if ip link show | grep -q wlan; then
    echo "      WLAN-Interface gefunden ✓"
    ip link show | grep wlan | awk '{print "      "$2}' || true
else
    echo "      WARNUNG: Kein WLAN-Interface — Modul eingesteckt? (M.2 Key-E)"
fi

# ── Abschluss ────────────────────────────────────────────────────────────────
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
HOSTNAME=$(hostname)

echo ""
echo "=== Setup abgeschlossen: $(date) ==="
echo ""
echo "  Hostname:  $HOSTNAME"
echo "  IP:        ${IP:-<wird per DHCP zugewiesen>}"
echo "  SSH:       ssh root@${IP:-$HOSTNAME} (Passwort: dietpi)"
echo "  USB/IP:    Port 3240"
echo ""
echo "  In docker-compose.yml setzen:"
echo "    USBIP_REMOTE_HOST: \"${IP:-<ip-hier-eintragen>}\""
echo ""
echo "  Log: $LOG"
echo "==="

# Hostname für einfaches Auffinden im Netzwerk setzen
hostnamectl set-hostname autocom-usbip 2>/dev/null || true
