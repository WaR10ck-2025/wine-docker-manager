#!/bin/bash
set -e

echo "[Wine-Desktop] Starte virtuellen Display..."
Xvfb :99 -screen 0 1280x800x24 -ac &
XVFB_PID=$!
sleep 1

echo "[Wine-Desktop] Initialisiere WINEPREFIX (falls noch nicht vorhanden)..."
wineboot --init 2>/dev/null || true
sleep 2

echo "[Wine-Desktop] Starte VNC-Server auf Port 5900..."
x11vnc -display :99 -forever -nopw -rfbport 5900 -quiet &
sleep 1

echo "[Wine-Desktop] Starte noVNC auf Port 8080..."
websockify --web /usr/share/novnc/ 8080 localhost:5900 &

# COM-Port-Symlinks automatisch setzen
for i in 0 1 2 3; do
    [ -e "/dev/ttyUSB$i" ] && ln -sf "/dev/ttyUSB$i" "$WINEPREFIX/dosdevices/com$((i+1))" 2>/dev/null || true
    [ -e "/dev/ttyACM$i" ] && ln -sf "/dev/ttyACM$i" "$WINEPREFIX/dosdevices/com$((i+5))" 2>/dev/null || true
done

echo "[Wine-Desktop] Bereit. Zugriff über http://host:8080"

# Container am Leben halten
wait $XVFB_PID
