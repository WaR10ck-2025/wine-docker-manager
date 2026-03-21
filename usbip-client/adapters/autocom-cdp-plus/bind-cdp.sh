#!/bin/sh
# Autocom CDP+ — USB/IP Bind/Unbind Script
# Standalone-Version (alternativ: obd-ctl bind)
#
# Verwendung:
#   sh bind-cdp.sh bind          # Adapter binden
#   sh bind-cdp.sh unbind        # Adapter freigeben
#   sh bind-cdp.sh status        # Status anzeigen

VENDOR="0403"
PRODUCT="d6da"
ACTION="${1:-status}"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; N='\033[0m'
ok()   { printf "${G}  ✓${N} %s\n" "$1"; }
fail() { printf "${R}  ✗${N} %s\n" "$1"; }
warn() { printf "${Y}  !${N} %s\n" "$1"; }

case "$ACTION" in
    bind)
        echo "CDP+ binden (${VENDOR}:${PRODUCT})..."
        BID=$(usbip list -l 2>/dev/null | grep "${VENDOR}:${PRODUCT}" | \
              grep -o 'busid [^ ]*' | awk '{print $2}' | head -1)
        if [ -n "$BID" ]; then
            usbip bind -b "$BID" && ok "CDP+ gebunden: $BID" || \
                warn "Bind fehlgeschlagen (schon gebunden?)"
        else
            fail "CDP+ (${VENDOR}:${PRODUCT}) nicht gefunden. Eingesteckt?"
            echo "Verfügbare Geräte:"
            usbip list -l 2>/dev/null || echo "  (usbip nicht verfügbar)"
        fi
        ;;

    unbind)
        echo "CDP+ freigeben..."
        BID=$(usbip list -l 2>/dev/null | grep "${VENDOR}:${PRODUCT}" | \
              grep -o 'busid [^ ]*' | awk '{print $2}' | head -1)
        [ -n "$BID" ] && usbip unbind -b "$BID" && ok "CDP+ freigegeben: $BID" || \
            warn "CDP+ nicht gebunden"
        ;;

    status)
        echo "CDP+ Status (${VENDOR}:${PRODUCT}):"
        if command -v usbip >/dev/null 2>&1; then
            usbip list -l 2>/dev/null | grep -A2 "${VENDOR}:${PRODUCT}" || \
                echo "  CDP+ nicht erkannt (nicht eingesteckt?)"
        else
            warn "usbip nicht verfügbar"
        fi
        ;;

    *)
        echo "Verwendung: $0 bind | unbind | status"
        exit 1
        ;;
esac
