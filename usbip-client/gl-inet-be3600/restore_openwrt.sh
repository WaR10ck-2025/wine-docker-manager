#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# GL.iNet GL-BE3600 — Wiederherstellung des Original-Zustands
#
# Drei Modi:
#   soft   — Nur installierte OBD2/USB-IP-Dateien entfernen (Standard)
#   full   — Vollständiger Werksreset via firstboot (WARNUNG: alles gelöscht!)
#   wifi   — Nur Netzwerk-Config zurücksetzen
#
# Verwendung:
#   scp restore_openwrt.sh root@192.168.8.1:/tmp/
#   ssh root@192.168.8.1 "sh /tmp/restore_openwrt.sh"         # → soft (Standard)
#   ssh root@192.168.8.1 "sh /tmp/restore_openwrt.sh full"    # → Werksreset
#   ssh root@192.168.8.1 "sh /tmp/restore_openwrt.sh wifi"    # → nur Netz reset
#
# WICHTIG: Bei "full" verlierst du ALLE Einstellungen (WLAN-Passwort, etc.)
#          Der Router ist danach wie frisch ausgepackt (IP: 192.168.8.1).
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

case "$MODE" in
    soft)   _do_soft_restore ;;
    full)   _do_full_reset ;;
    wifi)   _do_wifi_reset ;;
    *)      echo "Unbekannter Modus: $MODE"; echo "Gültig: soft | full | wifi"; exit 1 ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
# Soft-Restore: Nur OBD2/USB-IP-Installationen rückgängig machen
# Router bleibt betriebsbereit, WiFi/Netz-Einstellungen bleiben erhalten
# ─────────────────────────────────────────────────────────────────────────────
_do_soft_restore() {
    info "=== Soft-Restore: Entferne OBD2/USB-IP Installation ==="
    echo ""

    # ── 1. Services stoppen und deaktivieren ─────────────────────────────────
    info "[1/5] Services stoppen..."

    # Display-Service zuerst stoppen (gibt gl_screen frei)
    if [ -f /etc/init.d/obd-display ]; then
        /etc/init.d/obd-display stop 2>/dev/null || true
        /etc/init.d/obd-display disable 2>/dev/null || true
        rm -f /etc/init.d/obd-display
        info "      obd-display Service entfernt ✓"
    else
        info "      obd-display nicht installiert (skip)"
    fi

    # gl_screen wiederherstellen (falls noch gestoppt)
    /etc/init.d/gl_screen start 2>/dev/null || true
    info "      gl_screen wiederhergestellt ✓"

    if [ -f /etc/init.d/obd-monitor ]; then
        /etc/init.d/obd-monitor stop 2>/dev/null || true
        /etc/init.d/obd-monitor disable 2>/dev/null || true
        rm -f /etc/init.d/obd-monitor
        info "      obd-monitor Service entfernt ✓"
    else
        info "      obd-monitor nicht installiert (skip)"
    fi

    if [ -f /etc/init.d/usbipd ]; then
        /etc/init.d/usbipd stop 2>/dev/null || true
        /etc/init.d/usbipd disable 2>/dev/null || true
        rm -f /etc/init.d/usbipd
        info "      usbipd Service entfernt ✓"
    else
        info "      usbipd nicht installiert (skip)"
    fi

    # ── 2. OBD2-Code entfernen ────────────────────────────────────────────────
    info "[2/5] OBD2-Code entfernen..."

    if [ -d /opt/obd-monitor ]; then
        rm -rf /opt/obd-monitor
        info "      /opt/obd-monitor entfernt ✓"
    fi

    # ── 3. USB-Stick Pakete entfernen ─────────────────────────────────────────
    info "[3/5] Python-Pakete auf USB-Stick entfernen..."

    USB_PKG_DIR="/mnt/usb/obd-pkgs"
    if [ -d "$USB_PKG_DIR" ]; then
        rm -rf "$USB_PKG_DIR"
        info "      $USB_PKG_DIR entfernt ✓"
    else
        info "      Keine Pakete auf USB-Stick gefunden (skip)"
    fi

    # ── 4. Kernel-Module entfernen (falls installiert) ────────────────────────
    info "[4/5] Kernel-Module entfernen (falls via opkg installiert)..."

    for pkg in kmod-usbip kmod-usbip-host usbip-server usbip-client \
               kmod-usb-serial kmod-usb-serial-ftdi; do
        if opkg list-installed 2>/dev/null | grep -q "^$pkg "; then
            opkg remove --force-depends "$pkg" 2>/dev/null && \
                info "      $pkg entfernt ✓" || \
                warning "      $pkg konnte nicht entfernt werden"
        fi
    done

    # ── 5. Python3 entfernen (optional, fragt nach) ───────────────────────────
    info "[5/5] Python3 entfernen?"
    echo ""
    echo "  Python3 wurde via opkg installiert."
    echo "  Entfernen empfohlen, wenn OBD2 nicht mehr genutzt wird."
    echo ""

    if opkg list-installed 2>/dev/null | grep -q "^python3 "; then
        printf "  Python3 entfernen? [j/N] "
        read -r ANSWER
        if [ "$ANSWER" = "j" ] || [ "$ANSWER" = "J" ]; then
            opkg remove --force-depends python3 python3-pip 2>/dev/null || true
            info "      Python3 entfernt ✓"
        else
            info "      Python3 beibehalten"
        fi
    fi

    echo ""
    info "═══════════════════════════════════════════════"
    info "Soft-Restore abgeschlossen!"
    info ""
    info "Was wurde entfernt:"
    info "  - /etc/init.d/obd-display  (Touchscreen-UI)"
    info "  - /etc/init.d/obd-monitor"
    info "  - /etc/init.d/usbipd"
    info "  - /opt/obd-monitor/        (inkl. display_service.py)"
    info "  - /mnt/usb/obd-pkgs/       (Python + Pillow)"
    info "  - kmod-usbip* Pakete (falls installiert)"
    info ""
    info "Was wurde WIEDERHERGESTELLT:"
    info "  - gl_screen (GL.iNet Standard-Anzeige)"
    info ""
    info "Was wurde BEIBEHALTEN:"
    info "  - Alle Netzwerk-Einstellungen (WiFi, IPs)"
    info "  - Alle anderen opkg-Pakete"
    info "  - GL.iNet Admin-UI-Einstellungen"
    info ""
    info "Router ist wieder im Original-Funktionsumfang."
    info "Kein Neustart nötig."
    info "═══════════════════════════════════════════════"
}

# ─────────────────────────────────────────────────────────────────────────────
# Full-Reset: Vollständiger Werksreset via firstboot
# WARNUNG: Alle Einstellungen werden gelöscht!
# ─────────────────────────────────────────────────────────────────────────────
_do_full_reset() {
    echo ""
    echo "${RED}╔══════════════════════════════════════════════════╗${NC}"
    echo "${RED}║  ACHTUNG: Vollständiger Werksreset               ║${NC}"
    echo "${RED}║                                                  ║${NC}"
    echo "${RED}║  ALLE Einstellungen werden gelöscht:             ║${NC}"
    echo "${RED}║  - WiFi-Konfiguration                            ║${NC}"
    echo "${RED}║  - Netzwerk-IPs                                  ║${NC}"
    echo "${RED}║  - Installierte Pakete                           ║${NC}"
    echo "${RED}║  - OBD2/USB-IP Services                          ║${NC}"
    echo "${RED}║                                                  ║${NC}"
    echo "${RED}║  Danach: IP-Adresse → 192.168.8.1                ║${NC}"
    echo "${RED}║          Passwort   → goodlife (GL.iNet Standard)║${NC}"
    echo "${RED}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    printf "${YELLOW}  Wirklich fortfahren? Tippe 'RESET' zum Bestätigen: ${NC}"
    read -r CONFIRM

    if [ "$CONFIRM" != "RESET" ]; then
        info "Abgebrochen."
        exit 0
    fi

    info "Führe Werksreset aus..."

    # Methode 1: GL.iNet eigenes Reset-Tool (bevorzugt, setzt auch gl-config zurück)
    if command -v gl_factory_reset >/dev/null 2>&1; then
        info "Nutze gl_factory_reset..."
        gl_factory_reset
    # Methode 2: OpenWrt Standard firstboot
    elif command -v firstboot >/dev/null 2>&1; then
        info "Nutze firstboot..."
        firstboot -y
        sync
        reboot
    # Methode 3: UCI Defaults zurücksetzen
    else
        warning "Kein Reset-Tool gefunden — nutze UCI Defaults..."
        cd /etc/config || exit 1
        for cfg in network wireless firewall dhcp; do
            if [ -f "/rom/etc/config/$cfg" ]; then
                cp "/rom/etc/config/$cfg" "$cfg"
                info "      $cfg zurückgesetzt ✓"
            fi
        done
        sync
        reboot
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# WiFi-Reset: Nur Netzwerk/WiFi-Konfiguration zurücksetzen
# Nützlich wenn Router nicht mehr erreichbar ist
# ─────────────────────────────────────────────────────────────────────────────
_do_wifi_reset() {
    info "=== WiFi/Netzwerk-Reset ==="
    echo ""
    warning "Netzwerk und WiFi werden auf OpenWrt-Standard zurückgesetzt."
    warning "Danach ist der Router unter 192.168.8.1 erreichbar."
    echo ""
    printf "  Fortfahren? [j/N] "
    read -r CONFIRM

    if [ "$CONFIRM" != "j" ] && [ "$CONFIRM" != "J" ]; then
        info "Abgebrochen."
        exit 0
    fi

    # Network-Config aus ROM wiederherstellen
    for cfg in network wireless; do
        if [ -f "/rom/etc/config/$cfg" ]; then
            cp "/rom/etc/config/$cfg" "/etc/config/$cfg"
            info "      /etc/config/$cfg zurückgesetzt ✓"
        else
            # Leere Config als Fallback
            echo "" > "/etc/config/$cfg"
            warning "      /rom/etc/config/$cfg nicht gefunden — leere Config"
        fi
    done

    # UCI Commit
    uci commit network 2>/dev/null || true
    uci commit wireless 2>/dev/null || true

    info "Starte Netzwerk neu..."
    /etc/init.d/network restart 2>/dev/null || true
    wifi reload 2>/dev/null || true

    echo ""
    info "═══════════════════════════════════════════════"
    info "WiFi-Reset abgeschlossen."
    info ""
    info "Router ist jetzt erreichbar unter:"
    info "  192.168.8.1 (Standard GL.iNet IP)"
    info ""
    info "Passwort: goodlife (Standard) oder das zuletzt gesetzte"
    info "═══════════════════════════════════════════════"
}
