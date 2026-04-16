#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# OBD2 Monitor — Installationsskript für den headless Mini-PC
#
# Installiert den OBD2-Service (HTTP API auf Port 8765) und das
# SSH-Terminal-Tool (obd_monitor.py).
#
# Auf dem Mini-PC als root ausführen:
#   bash install_obd.sh
#
# Idempotent: mehrfach ausführbar ohne Schaden.
# ─────────────────────────────────────────────────────────────────────────────
set -e

LOG="/var/log/obd-monitor-install.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== OBD2 Monitor Install Start: $(date) ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/obd-monitor"
VENV_DIR="/opt/obd-monitor-venv"
SERVICE_FILE="/etc/systemd/system/obd-monitor.service"

# ── Root-Check ───────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "FEHLER: Dieses Skript muss als root ausgeführt werden (sudo bash install_obd.sh)"
    exit 1
fi

# ── 1. System-Pakete ─────────────────────────────────────────────────────────
echo "[1/5] Installiere Python3 + venv..."
apt-get update -qq

# Python3-Version erkennen (Debian Bookworm: 3.11)
PY_VER=$(python3 --version 2>/dev/null | grep -oP '3\.\d+' | head -1)
if [ -z "$PY_VER" ]; then
    echo "FEHLER: python3 nicht gefunden"
    exit 1
fi

apt-get install -y --no-install-recommends \
    python3-pip \
    "python3.${PY_VER##3.}-venv" \
    2>/dev/null || apt-get install -y --no-install-recommends python3-venv
echo "      Python $PY_VER ✓"

# ── 2. Virtualenv anlegen ────────────────────────────────────────────────────
echo "[2/5] Virtualenv in $VENV_DIR..."
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
    echo "      Virtualenv erstellt"
else
    echo "      Virtualenv bereits vorhanden"
fi

# Pip aktualisieren
"$VENV_DIR/bin/pip" install --quiet --upgrade pip

# ── 3. Python-Pakete ─────────────────────────────────────────────────────────
echo "[3/5] Installiere Python-Pakete..."
"$VENV_DIR/bin/pip" install --quiet -r "$SCRIPT_DIR/requirements.txt"
echo "      Pakete installiert ✓"

# ── 4. Dateien kopieren ──────────────────────────────────────────────────────
echo "[4/5] Kopiere Dateien nach $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR/protocols" "$INSTALL_DIR/static"

cp "$SCRIPT_DIR/obd_monitor.py"    "$INSTALL_DIR/"
cp "$SCRIPT_DIR/obd_service.py"    "$INSTALL_DIR/"
cp "$SCRIPT_DIR/uds_client.py"     "$INSTALL_DIR/"
cp "$SCRIPT_DIR/protocols/__init__.py" "$INSTALL_DIR/protocols/"
cp "$SCRIPT_DIR/protocols/base.py"     "$INSTALL_DIR/protocols/"
cp "$SCRIPT_DIR/protocols/elm327.py"   "$INSTALL_DIR/protocols/"
cp "$SCRIPT_DIR/protocols/iso9141.py"  "$INSTALL_DIR/protocols/"
cp "$SCRIPT_DIR/static/dashboard.html" "$INSTALL_DIR/static/"

# Symlink für bequemen SSH-Zugriff
ln -sf "$INSTALL_DIR/obd_monitor.py" /usr/local/bin/obd-monitor 2>/dev/null || true
echo "      Dateien kopiert ✓"

# dialout-Gruppe für seriellen Port-Zugriff
if ! groups root | grep -q dialout; then
    usermod -a -G dialout root
    echo "      root zu dialout-Gruppe hinzugefügt"
fi

# ── 5. Systemd Service ───────────────────────────────────────────────────────
echo "[5/5] Installiere systemd Service..."
cp "$SCRIPT_DIR/obd-monitor.service" "$SERVICE_FILE"

systemctl daemon-reload
systemctl enable obd-monitor.service
systemctl restart obd-monitor.service || systemctl start obd-monitor.service
echo "      Service aktiviert und gestartet ✓"

# ── Abschluss ────────────────────────────────────────────────────────────────
IP=$(hostname -I 2>/dev/null | awk '{print $1}')

echo ""
echo "=== OBD2 Monitor Install abgeschlossen: $(date) ==="
echo ""
echo "  Service-Status: systemctl status obd-monitor"
echo "  Service-Log:    journalctl -u obd-monitor -f"
echo ""
echo "  HTTP API auf Port 8765:"
echo "    curl http://${IP:-<ip>}:8765/obd/status"
echo "    curl http://${IP:-<ip>}:8765/obd/data"
echo ""
echo "  Web-Dashboard:"
echo "    http://${IP:-<ip>}:8765/"
echo ""
echo "  TCP-Mode aktivieren (z.B. ELM327-Simulator auf LXC 213):"
echo "    echo 'OBD_TCP=192.168.10.213:35000' > /etc/obd-monitor.env"
echo "    systemctl restart obd-monitor"
echo ""
echo "  SSH Terminal-Dashboard:"
echo "    python3 $INSTALL_DIR/obd_monitor.py"
echo "    obd-monitor           # (Symlink)"
echo "    obd-monitor --debug   # mit Debug-Ausgabe"
echo ""
echo "  In docker-compose.yml setzen:"
echo "    OBD_MONITOR_HOST: \"${IP:-<ip-hier-eintragen>}\""
echo ""
echo "  Log: $LOG"
echo "==="
