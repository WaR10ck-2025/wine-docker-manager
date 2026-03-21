#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# GL.iNet GL-BE10000 (Slate 7 Pro) — Wiederherstellung des Original-Zustands
# PROTOTYPE
#
# Drei Modi:
#   soft   — Nur installierte OBD2/USB-IP-Dateien entfernen (Standard)
#   full   — Vollständiger Werksreset via firstboot (WARNUNG: alles gelöscht!)
#   wifi   — Nur Netzwerk-Config zurücksetzen
#
# Unterschied zu GL-BE3600: entfernt venv (/opt/obd-venv) statt USB-Stick-Pakete
#
# Verwendung:
#   scp restore_openwrt.sh root@192.168.10.196:/tmp/
#   ssh root@192.168.10.196 "sh /tmp/restore_openwrt.sh"         # → soft
#   ssh root@192.168.10.196 "sh /tmp/restore_openwrt.sh full"    # → Werksreset
#   ssh root@192.168.10.196 "sh /tmp/restore_openwrt.sh wifi"    # → nur Netz
# ─────────────────────────────────────────────────────────────────────────────

MODE="${1:-soft}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo "${GREEN}[restore]${NC} $1"; }
warning() { echo "${YELLOW}[restore]${NC} $1"; }
err()     { echo "${RED}[restore]${NC} $1"; exit 1; }

[ "$(id -u)" = "0" ] || err "Bitte als root ausführen"

_do_soft_restore() {
    info "=== Soft-Restore: Entferne OBD2/USB-IP Installation ==="
    echo ""

    # ── 1. Services stoppen ───────────────────────────────────────────────────
    info "[1/5] Services stoppen..."

    if [ -f /etc/init.d/obd-display ]; then
        /etc/init.d/obd-display stop 2>/dev/null || true
        /etc/init.d/obd-display disable 2>/dev/null || true
        rm -f /etc/init.d/obd-display
        info "      obd-display entfernt ✓"
    fi

    # gl_screen wiederherstellen (falls vorhanden — TODO: verify on hardware)
    [ -f /etc/init.d/gl_screen ] && /etc/init.d/gl_screen start 2>/dev/null || true

    if [ -f /etc/init.d/obd-monitor ]; then
        /etc/init.d/obd-monitor stop 2>/dev/null || true
        /etc/init.d/obd-monitor disable 2>/dev/null || true
        rm -f /etc/init.d/obd-monitor
        info "      obd-monitor entfernt ✓"
    fi

    if [ -f /etc/init.d/usbipd ]; then
        /etc/init.d/usbipd stop 2>/dev/null || true
        /etc/init.d/usbipd disable 2>/dev/null || true
        rm -f /etc/init.d/usbipd
        info "      usbipd entfernt ✓"
    fi

    if [ -f /etc/init.d/tailscaled ]; then
        /etc/init.d/tailscaled stop 2>/dev/null || true
        /etc/init.d/tailscaled disable 2>/dev/null || true
        rm -f /etc/init.d/tailscaled
        info "      tailscaled entfernt ✓"
    fi

    # ── 2. Python-venv und Code entfernen ─────────────────────────────────────
    info "[2/5] Python-venv und Code entfernen..."

    if [ -d /opt/obd-venv ]; then
        rm -rf /opt/obd-venv
        info "      /opt/obd-venv entfernt ✓"
    fi

    if [ -d /opt/obd-monitor ]; then
        rm -rf /opt/obd-monitor
        info "      /opt/obd-monitor entfernt ✓"
    fi

    if [ -d /opt/obd-display ]; then
        rm -rf /opt/obd-display
        info "      /opt/obd-display entfernt ✓"
    fi

    if [ -f /etc/obd-adapter.conf ]; then
        rm -f /etc/obd-adapter.conf
        info "      /etc/obd-adapter.conf entfernt ✓"
    fi

    # ── 3. obd-ctl entfernen ─────────────────────────────────────────────────
    info "[3/5] obd-ctl entfernen..."
    rm -f /usr/local/bin/obd-ctl
    info "      obd-ctl entfernt ✓"

    # ── 4. Tailscale entfernen (falls installiert) ───────────────────────────
    info "[4/5] Tailscale prüfen..."
    if command -v tailscale > /dev/null 2>&1; then
        tailscale logout 2>/dev/null || true
        rm -f /usr/bin/tailscale /usr/sbin/tailscaled
        rm -rf /var/lib/tailscale
        info "      Tailscale entfernt ✓"
    else
        info "      Tailscale nicht installiert (skip)"
    fi

    # ── 5. Kernel-Module entfernen ───────────────────────────────────────────
    info "[5/5] USB/IP Kernel-Module prüfen..."
    if opkg list-installed 2>/dev/null | grep -q kmod-usbip; then
        opkg remove kmod-usbip kmod-usbip-host 2>/dev/null || \
        warning "Kernel-Module konnten nicht entfernt werden (manuell: opkg remove kmod-usbip)"
        info "      kmod-usbip entfernt ✓"
    else
        info "      kmod-usbip nicht installiert (skip)"
    fi

    echo ""
    info "═══════════════════════════════════════════════"
    info "Soft-Restore abgeschlossen!"
    info ""
    info "Entfernt:"
    info "  - /opt/obd-venv  (Python-venv)"
    info "  - /opt/obd-monitor  (Code)"
    info "  - /opt/obd-display  (Display-Code)"
    info "  - init.d Services (obd-monitor, obd-display, usbipd)"
    info ""
    info "Erhalten:"
    info "  - WiFi-Einstellungen"
    info "  - SSH-Keys"
    info "  - VPN-Konfiguration"
    info "═══════════════════════════════════════════════"
}

_do_wifi_reset() {
    info "=== WiFi-Reset: Netzwerk-Konfiguration zurücksetzen ==="
    echo ""

    info "[1/2] Netzwerk-Config von ROM wiederherstellen..."
    cp /rom/etc/config/network /etc/config/network 2>/dev/null || \
        warning "/rom/etc/config/network nicht gefunden — manuell zurücksetzen nötig"

    cp /rom/etc/config/wireless /etc/config/wireless 2>/dev/null || \
        warning "/rom/etc/config/wireless nicht gefunden"

    info "[2/2] Netzwerk-Service neu starten..."
    /etc/init.d/network restart

    echo ""
    info "WiFi-Reset abgeschlossen. Router-IP zurück auf GL.iNet-Standard (192.168.8.1)."
}

_do_full_reset() {
    warning "=== VOLLSTÄNDIGER WERKSRESET ==="
    warning "ALLE Daten, Einstellungen und installierten Pakete werden gelöscht!"
    warning "Router-IP nach Reset: 192.168.8.1, Passwort: goodlife"
    echo ""
    printf "Zur Bestätigung 'RESET' eingeben: "
    read CONFIRM
    if [ "$CONFIRM" != "RESET" ]; then
        info "Abgebrochen."
        exit 0
    fi

    info "Starte Werksreset..."
    if command -v gl_factory_reset > /dev/null 2>&1; then
        gl_factory_reset 2>/dev/null || firstboot -y && reboot
    else
        firstboot -y && reboot
    fi
}

case "$MODE" in
    soft)   _do_soft_restore ;;
    full)   _do_full_reset ;;
    wifi)   _do_wifi_reset ;;
    *)      echo "Unbekannter Modus: $MODE"; echo "Gültig: soft | full | wifi"; exit 1 ;;
esac
