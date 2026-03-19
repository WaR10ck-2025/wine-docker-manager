#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# NanoPi R5C — USB/IP First-Boot Setup
# Wird vom systemd Service 'usbip-firstboot-setup' einmalig ausgeführt.
# Auf Boot-Partition ablegen: /boot/usbip-firstboot.sh
# ─────────────────────────────────────────────────────────────────────────────
set -e

LOG="/var/log/usbip-firstboot.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== NanoPi R5C USB/IP First-Boot: $(date) ==="

AUTOCOM_VENDOR="0403"
AUTOCOM_PRODUCT="d6da"

# ── 1. usbip installieren ────────────────────────────────────────────────────
echo "[1/4] Installiere usbip..."
apt-get update -qq
apt-get install -y --no-install-recommends usbip kmod
USBIPD=$(which usbipd || echo "/usr/sbin/usbipd")
USBIP=$(which usbip   || echo "/usr/sbin/usbip")

# ── 2. Kernel-Module ─────────────────────────────────────────────────────────
echo "[2/4] Kernel-Module..."
modprobe usbip-core 2>/dev/null || true
modprobe usbip-host 2>/dev/null || true
grep -q usbip-core /etc/modules || echo usbip-core >> /etc/modules
grep -q usbip-host /etc/modules || echo usbip-host >> /etc/modules

# ── 3. Systemd Service + udev ────────────────────────────────────────────────
echo "[3/4] Richte usbipd Service ein..."
cat > /etc/systemd/system/usbipd.service << UNIT
[Unit]
Description=USB/IP Server (Autocom CDP+ Headless)
After=network.target

[Service]
Type=forking
ExecStartPre=/sbin/modprobe usbip-core
ExecStartPre=/sbin/modprobe usbip-host
ExecStart=${USBIPD} -D
ExecStartPost=/bin/bash -c 'sleep 2 && BID=\$(${USBIP} list -l 2>/dev/null | grep "${AUTOCOM_VENDOR}:${AUTOCOM_PRODUCT}" | grep -oP "(?<=busid )\\S+" | head -1) && [ -n "\$BID" ] && ${USBIP} bind --busid "\$BID" || true'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

echo "ACTION==\"add\", SUBSYSTEM==\"usb\", ATTR{idVendor}==\"${AUTOCOM_VENDOR}\", ATTR{idProduct}==\"${AUTOCOM_PRODUCT}\", RUN+=\"/bin/systemctl restart usbipd.service\"" \
    > /etc/udev/rules.d/99-autocom-usbip.rules

udevadm control --reload-rules
systemctl daemon-reload
systemctl enable usbipd.service
systemctl start usbipd.service || true

# ── 4. Abschluss ─────────────────────────────────────────────────────────────
touch /etc/usbip-setup-done
IP=$(hostname -I | awk '{print $1}')
echo "[4/4] Setup abgeschlossen"
echo ""
echo "=== NanoPi R5C bereit ==="
echo "  IP:     ${IP}"
echo "  Port:   3240"
echo "  docker-compose.yml: USBIP_REMOTE_HOST: \"${IP}\""
echo "=========================="
