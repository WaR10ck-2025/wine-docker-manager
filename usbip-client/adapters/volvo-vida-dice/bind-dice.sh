#!/bin/sh
# Volvo VIDA DiCE — USB/IP Bind/Unbind Script
# VID:PID 17aa:d1ce (SETEK chipset)
#
# Verwendung:
#   sh bind-dice.sh bind          # DiCE binden (für Windows-VM Export)
#   sh bind-dice.sh unbind        # DiCE freigeben
#   sh bind-dice.sh status        # Status anzeigen

VENDOR="17aa"
PRODUCT="d1ce"
ACTION="${1:-status}"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; N='\033[0m'
ok()   { printf "${G}  ✓${N} %s\n" "$1"; }
fail() { printf "${R}  ✗${N} %s\n" "$1"; }
warn() { printf "${Y}  !${N} %s\n" "$1"; }

case "$ACTION" in
    bind)
        echo "Volvo DiCE binden (${VENDOR}:${PRODUCT})..."
        echo "HINWEIS: Kein Linux-Treiber — USB/IP leitet an Windows-VM weiter."
        BID=$(usbip list -l 2>/dev/null | grep "${VENDOR}:${PRODUCT}" | \
              grep -o 'busid [^ ]*' | awk '{print $2}' | head -1)
        if [ -n "$BID" ]; then
            usbip bind -b "$BID" && ok "DiCE gebunden: $BID (bereit für Windows-VM Import)" || \
                warn "Bind fehlgeschlagen"
        else
            fail "DiCE (${VENDOR}:${PRODUCT}) nicht erkannt."
            echo "Prüfe: Eingesteckt? USB-Treiber geladen? lsusb:"
            lsusb 2>/dev/null | head -15
        fi
        ;;

    unbind)
        BID=$(usbip list -l 2>/dev/null | grep "${VENDOR}:${PRODUCT}" | \
              grep -o 'busid [^ ]*' | awk '{print $2}' | head -1)
        [ -n "$BID" ] && usbip unbind -b "$BID" && ok "DiCE freigegeben: $BID" || \
            warn "DiCE nicht gebunden"
        ;;

    status)
        echo "Volvo DiCE Status (${VENDOR}:${PRODUCT}):"
        if command -v usbip >/dev/null 2>&1; then
            usbip list -l 2>/dev/null | grep -A2 "${VENDOR}:${PRODUCT}" || \
                echo "  DiCE nicht erkannt"
        else
            warn "usbip nicht verfügbar"
        fi
        ;;

    *)
        echo "Verwendung: $0 bind | unbind | status"
        exit 1
        ;;
esac
