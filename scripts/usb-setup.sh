#!/bin/bash
# USB-udev-Regeln für Wine-Docker auf Linux einrichten.
# Als root ausführen: sudo bash scripts/usb-setup.sh

set -e

RULES_FILE="/etc/udev/rules.d/99-wine-docker-usb.rules"

echo "Schreibe udev-Regeln nach $RULES_FILE ..."

cat > "$RULES_FILE" <<'EOF'
# Wine Docker — USB-Zugriff ohne --privileged
# Serielle Geräte
SUBSYSTEMS=="usb-serial", MODE="0666"
KERNEL=="ttyUSB*",        MODE="0666"
KERNEL=="ttyACM*",        MODE="0666"
# HID-Geräte
KERNEL=="hidraw*",        MODE="0666"
# Spezifische Geräte per Vendor:Product (Beispiel FTDI):
# SUBSYSTEMS=="usb", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", MODE="0666"
EOF

echo "Lade udev-Regeln neu..."
udevadm control --reload
udevadm trigger

echo "Fertig. Stecke das USB-Gerät neu ein, damit die Regeln gelten."
echo ""
echo "Stabile Gerätepfade findest du unter:"
echo "  ls /dev/serial/by-id/"
echo ""
echo "Diese Pfade in docker-compose.yml unter 'devices:' eintragen, z.B.:"
echo "  devices:"
echo "    - /dev/serial/by-id/usb-FTDI_..._UART_XXXX:/dev/ttyUSB0"
