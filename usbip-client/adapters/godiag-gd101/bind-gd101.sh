#!/bin/sh
# GODIAG GD101 — USB/IP Bind/Unbind Script
#
# HINWEIS: VID:PID in adapter.conf setzen (lsusb prüfen!)
# Verwendung:
#   sh bind-gd101.sh bind
#   sh bind-gd101.sh unbind
#   sh bind-gd101.sh status

# Config laden
[ -f "$(dirname $0)/adapter.conf" ] && . "$(dirname $0)/adapter.conf"
VENDOR="${ADAPTER_VENDOR:-0403}"
PRODUCT="${ADAPTER_PRODUCT:-6001}"
ACTION="${1:-status}"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; N='\033[0m'
ok()   { printf "${G}  ✓${N} %s\n" "$1"; }
fail() { printf "${R}  ✗${N} %s\n" "$1"; }
warn() { printf "${Y}  !${N} %s\n" "$1"; }

case "$ACTION" in
    bind)
        echo "GD101 binden (${VENDOR}:${PRODUCT}) für Volvo VIDA/vdash..."
        BID=$(usbip list -l 2>/dev/null | grep "${VENDOR}:${PRODUCT}" | \
              grep -o 'busid [^ ]*' | awk '{print $2}' | head -1)
        if [ -n "$BID" ]; then
            usbip bind -b "$BID" && ok "GD101 gebunden: $BID (bereit für Windows-Import)" || \
                warn "Bind fehlgeschlagen (schon gebunden?)"
            echo "  → Windows: usbipd attach --remote <router-ip> --busid $BID"
            echo "  → dann: VIDA 2014D oder vdash starten"
        else
            fail "GD101 (${VENDOR}:${PRODUCT}) nicht erkannt."
            warn "VID:PID via lsusb prüfen und adapter.conf aktualisieren!"
            echo ""
            echo "FTDI-Geräte:"
            lsusb 2>/dev/null | grep -i "ftdi\|0403" | head -10 || \
                lsusb 2>/dev/null | head -20
        fi
        ;;
    unbind)
        BID=$(usbip list -l 2>/dev/null | grep "${VENDOR}:${PRODUCT}" | \
              grep -o 'busid [^ ]*' | awk '{print $2}' | head -1)
        [ -n "$BID" ] && usbip unbind -b "$BID" && ok "GD101 freigegeben: $BID" || \
            warn "GD101 nicht gebunden"
        ;;
    status)
        echo "GD101 Status (${VENDOR}:${PRODUCT}):"
        if command -v usbip >/dev/null 2>&1; then
            result=$(usbip list -l 2>/dev/null | grep -A2 "${VENDOR}:${PRODUCT}")
            if [ -n "$result" ]; then
                echo "$result"
                ok "GD101 erkannt"
            else
                echo "  GD101 nicht erkannt. VID:PID korrekt? (lsusb | grep 0403)"
            fi
        else
            warn "usbip nicht verfügbar"
        fi
        ;;
    *) echo "Verwendung: $0 bind | unbind | status"; exit 1 ;;
esac
