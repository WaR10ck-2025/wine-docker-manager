#!/bin/bash
set -e

BUSID="${USBIP_BUSID:-3-6}"

echo "[USB/IP] Lade Kernel-Module..."
modprobe usbip-core  2>/dev/null || { echo "[USB/IP] FEHLER: usbip-core nicht geladen"; exit 1; }
modprobe usbip-host  2>/dev/null || { echo "[USB/IP] FEHLER: usbip-host nicht geladen"; exit 1; }

echo "[USB/IP] Starte usbipd Daemon..."
usbipd -D

sleep 1

echo "[USB/IP] Binde Gerät Bus-ID $BUSID..."
if usbip bind --busid "$BUSID" 2>/dev/null; then
    echo "[USB/IP] Gerät $BUSID wird auf Port 3240 geteilt"
else
    echo "[USB/IP] WARNUNG: Gerät $BUSID konnte nicht gebunden werden (noch nicht eingesteckt?)"
fi

echo "[USB/IP] Bereit. Windows-PC verbindet sich mit: usbip attach -r <umbrel-ip> -b $BUSID"

# Halte Container am Leben und re-binde bei Bedarf
while true; do
    sleep 10
    # Gerät neu binden falls es noch nicht gebunden ist
    status=$(usbip list --exported 2>/dev/null || echo "")
    if ! echo "$status" | grep -q "$BUSID"; then
        usbip bind --busid "$BUSID" 2>/dev/null || true
    fi
done
