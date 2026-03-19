#!/bin/bash
set -e

# Hintergrundjobs (x11vnc, websockify) sollen Fehler nicht propagieren
trap '' ERR

# ── Als root: Volume-Ownership korrigieren, dann zu wineuser wechseln ────────
if [ "$(id -u)" = "0" ]; then
    echo "[Wine-Desktop] Korrigiere Volume-Ownership für wineuser..."
    chown -R wineuser:wineuser /home/wineuser /uploads /app 2>/dev/null || true
    # noVNC index.html als root schreiben (kein Schreibrecht für wineuser)
    echo '<meta http-equiv="refresh" content="0;url=vnc_auto.html">' \
        > /usr/share/novnc/index.html
    echo "[Wine-Desktop] Wechsle zu wineuser..."
    exec su - wineuser -s /bin/bash -c "exec /start.sh"
fi
# ─────────────────────────────────────────────────────────────────────────────

echo "[Wine-Desktop] Starte virtuellen Display..."
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null || true
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
