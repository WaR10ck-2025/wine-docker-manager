#!/bin/sh
# Xhorse MVCI PRO+ — USB/IP Bind/Unbind Script
#
# HINWEIS: VID:PID in adapter.conf setzen (lsusb prüfen!)
# Verwendung:
#   sh bind-mvci.sh bind
#   sh bind-mvci.sh unbind
#   sh bind-mvci.sh status

# Config laden
[ -f "$(dirname $0)/adapter.conf" ] && . "$(dirname $0)/adapter.conf"
VENDOR="${ADAPTER_VENDOR:-04d8}"
PRODUCT="${ADAPTER_PRODUCT:-0000}"
ACTION="${1:-status}"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; N='\033[0m'
ok()   { printf "${G}  ✓${N} %s\n" "$1"; }
fail() { printf "${R}  ✗${N} %s\n" "$1"; }
warn() { printf "${Y}  !${N} %s\n" "$1"; }

case "$ACTION" in
    bind)
        echo "MVCI PRO+ binden (${VENDOR}:${PRODUCT})..."
        warn "Tatsächlichen VID:PID via lsusb prüfen!"
        BID=$(usbip list -l 2>/dev/null | grep "${VENDOR}:${PRODUCT}" | \
              grep -o 'busid [^ ]*' | awk '{print $2}' | head -1)
        if [ -n "$BID" ]; then
            usbip bind -b "$BID" && ok "MVCI gebunden: $BID" || warn "Bind fehlgeschlagen"
        else
            fail "MVCI (${VENDOR}:${PRODUCT}) nicht gefunden."
            echo "VID:PID via lsusb prüfen und adapter.conf aktualisieren:"
            lsusb 2>/dev/null | head -20
        fi
        ;;
    unbind)
        BID=$(usbip list -l 2>/dev/null | grep "${VENDOR}:${PRODUCT}" | \
              grep -o 'busid [^ ]*' | awk '{print $2}' | head -1)
        [ -n "$BID" ] && usbip unbind -b "$BID" && ok "Freigegeben: $BID" || warn "Nicht gebunden"
        ;;
    status)
        echo "MVCI PRO+ Status:"
        usbip list -l 2>/dev/null | grep -A2 "${VENDOR}:${PRODUCT}" || \
            echo "  MVCI nicht erkannt. VID:PID korrekt?"
        ;;
    *) echo "Verwendung: $0 bind | unbind | status"; exit 1 ;;
esac
