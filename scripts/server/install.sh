#!/bin/bash
# Wine Manager — Server-Deployment (Umbrel / Linux)
# Idempotent: git clone ODER git pull, dann docker compose up
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
step() { echo -e "\n${CYAN}[*] $1${NC}"; }
ok()   { echo -e "${GREEN}[OK] $1${NC}"; }
warn() { echo -e "${YELLOW}[!]  $1${NC}"; }
fail() { echo -e "${RED}[FEHLER] $1${NC}"; exit 1; }

REPO_URL="https://github.com/WaR10ck-2025/wine-docker-manager.git"
INSTALL_DIR="$HOME/docker/wine-docker-manager"

echo -e "\n${CYAN}╔══════════════════════════════════════╗"
echo -e "║     Wine Manager — Deployment        ║"
echo -e "╚══════════════════════════════════════╝${NC}"

# ── [1] Docker prüfen ─────────────────────────────────────────────────────
step "Prüfe Docker..."
command -v docker >/dev/null 2>&1 || fail "Docker nicht gefunden."
docker compose version >/dev/null 2>&1 || fail "Docker Compose nicht gefunden."
ok "Docker verfügbar."

# ── [2] Git clone oder pull ───────────────────────────────────────────────
step "Repository aktualisieren..."
if [ -d "$INSTALL_DIR/.git" ]; then
    warn "Verzeichnis vorhanden → git pull"
    git -C "$INSTALL_DIR" pull --ff-only
else
    git clone "$REPO_URL" "$INSTALL_DIR"
fi
ok "Repository aktuell."

PROJECT_ROOT="$INSTALL_DIR"
cd "$PROJECT_ROOT"

# ── [3] .env anlegen ──────────────────────────────────────────────────────
if [ ! -f ".env" ]; then
    step ".env aus Vorlage erstellen..."
    cp .env.example .env
    ok ".env angelegt."
fi

# ── [4] Docker-Images bauen ───────────────────────────────────────────────
step "Baue Docker-Images (kann beim ersten Mal mehrere Minuten dauern)..."
docker compose build
ok "Images gebaut."

# ── [5] Dienste starten ───────────────────────────────────────────────────
step "Starte Dienste..."
docker compose up -d
ok "Container gestartet."

# ── [6] Warten auf Wine-Initialisierung ───────────────────────────────────
step "Warte auf Wine-Initialisierung (30s)..."
sleep 30

# ── [7] Health-Check ──────────────────────────────────────────────────────
step "Health-Check..."
MAX=6; i=0
until curl -sf http://localhost:4000/health >/dev/null 2>&1; do
    i=$((i+1))
    [ $i -ge $MAX ] && fail "Backend antwortet nicht nach $(( MAX * 5 ))s."
    warn "Warte auf API... ($i/$MAX)"
    sleep 5
done
ok "Backend erreichbar."

# ── [8] Abschluss ─────────────────────────────────────────────────────────
LOCAL_IP=$(hostname -I | awk '{print $1}')
echo -e "\n${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  Wine Manager läuft!${NC}"
echo -e ""
echo -e "  App-Manager:  ${CYAN}http://${LOCAL_IP}:3000${NC}"
echo -e "  Wine Desktop: ${CYAN}http://${LOCAL_IP}:8080${NC}"
echo -e "  API Docs:     ${CYAN}http://${LOCAL_IP}:4000/docs${NC}"
echo -e "  VNC direkt:   ${CYAN}${LOCAL_IP}:5900${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}\n"



# ── QR-Code Credentials (aktivierbar via .env) ───────────────────────────────
# Aktivieren: QR_ENABLED=true und QR_PIN=1234 in .env setzen
_QR_ENABLED="${QR_ENABLED:-false}"
_QR_PIN_VALUE="${QR_PIN:-}"
if [ -f ".env" ]; then
    _QR_ENV_ENABLED=$(grep -E "^QR_ENABLED=" .env 2>/dev/null | cut -d= -f2- | tr -d '"' | xargs || true)
    _QR_ENV_PIN=$(grep -E "^QR_PIN=[^#]+" .env 2>/dev/null | cut -d= -f2- | tr -d '"' | xargs || true)
    [ -n "${_QR_ENV_ENABLED:-}" ] && _QR_ENABLED="$_QR_ENV_ENABLED"
    [ -n "${_QR_ENV_PIN:-}" ]     && _QR_PIN_VALUE="$_QR_ENV_PIN"
fi
_QRCREDS_IP="${LOCAL_IP:-${NAS_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}}"
if command -v qrcreds &>/dev/null && [ "$_QR_ENABLED" = "true" ] && [ -n "${_QR_PIN_VALUE:-}" ]; then
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  QR-Code Zugang — SSH + Tailscale${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    _QR_ALIAS="$(basename "$(pwd)")"
    qrcreds generate ssh \
        --host "$_QRCREDS_IP" \
        --user "${USER:-$(whoami)}" \
        --alias "$_QR_ALIAS" \
        --pin "$_QR_PIN_VALUE" --expires 60 2>/dev/null || true
    echo -e "  PIN: ${YELLOW}${_QR_PIN_VALUE}${NC}  |  Termius App → QR scannen"
    _TS_KEY=""
    [ -f ".env" ] && _TS_KEY=$(grep -E "^TS_AUTHKEY=[^#]+" .env 2>/dev/null | cut -d= -f2- | tr -d '"' | xargs || true)
    if [ -n "${_TS_KEY:-}" ]; then
        echo ""
        qrcreds generate tailscale --authkey "$_TS_KEY" \
            --hostname "$_QR_ALIAS" \
            --pin "$_QR_PIN_VALUE" --expires 60 2>/dev/null || true
    fi
    echo ""
fi
