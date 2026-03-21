#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# USB/IP Kernel-Module — GL.iNet SDK Build für GL-BE3600 (IPQ5332/ipq53xx)
#
# Baut kmod-usbip und kmod-usbip-host als .ipk-Pakete für OpenWrt 23.05.
# Muss auf einem Linux-Host (Ubuntu 22.04/24.04 empfohlen) ausgeführt werden.
#
# Dauer: 30–90 Minuten (je nach CPU, beim ersten Mal länger wegen SDK-Download)
#
# Ausgabe:
#   build/packages/kmod-usbip_*.ipk
#   build/packages/kmod-usbip-host_*.ipk
#
# Danach auf GL-BE3600 installieren:
#   scp build/packages/kmod-usbip*.ipk root@192.168.8.1:/tmp/
#   ssh root@192.168.8.1 "opkg install /tmp/kmod-usbip_*.ipk && opkg install /tmp/kmod-usbip-host_*.ipk"
# ─────────────────────────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
SDK_REPO="https://github.com/gl-inet/gl-infra-builder"
SDK_BRANCH="main"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[sdk]${NC} $1"; }
warning() { echo -e "${YELLOW}[sdk]${NC} $1"; }
err()     { echo -e "${RED}[sdk]${NC} $1"; exit 1; }

# ── Voraussetzungen prüfen ────────────────────────────────────────────────────
info "Prüfe Build-Voraussetzungen..."

for pkg in git python3 rsync unzip wget curl; do
    command -v "$pkg" >/dev/null 2>&1 || err "$pkg fehlt. Installieren: sudo apt-get install -y $pkg"
done

# Build-Dependencies (Ubuntu/Debian)
if command -v apt-get >/dev/null 2>&1; then
    info "Installiere Build-Dependencies..."
    sudo apt-get install -y --no-install-recommends \
        build-essential \
        libncurses5-dev \
        libncursesw5-dev \
        zlib1g-dev \
        gawk \
        gettext \
        libssl-dev \
        xsltproc \
        python3-distutils \
        2>/dev/null || true
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# ── GL.iNet glbuilder klonen ──────────────────────────────────────────────────
if [ ! -d "gl-infra-builder" ]; then
    info "Klone GL.iNet glbuilder..."
    git clone --depth 1 -b "$SDK_BRANCH" "$SDK_REPO" gl-infra-builder
    info "      Klon abgeschlossen ✓"
else
    info "glbuilder bereits vorhanden — aktualisiere..."
    cd gl-infra-builder && git pull --ff-only && cd ..
fi

cd gl-infra-builder

# ── GL-BE3600 Profil einrichten ───────────────────────────────────────────────
info "Richte GL-BE3600 (ipq53xx) Build-Umgebung ein..."

# Profile-Config suchen
PROFILE_CONF=""
for conf in \
    "configs/config-wlan-ap-5.4.yml" \
    "configs/ipq53xx.yml" \
    "configs/gl-be3600.yml"; do
    if [ -f "$conf" ]; then
        PROFILE_CONF="$conf"
        break
    fi
done

if [ -n "$PROFILE_CONF" ]; then
    info "Verwende Profil: $PROFILE_CONF"
    python3 setup.py -c "$PROFILE_CONF"
else
    warning "Kein vordefiniertes GL-BE3600-Profil gefunden."
    info "Verfügbare Profile:"
    ls configs/*.yml 2>/dev/null || ls configs/ 2>/dev/null
    err "Bitte manuelles Profil in $SCRIPT_DIR/build/gl-infra-builder/configs/ suchen und PROFILE_CONF setzen."
fi

# ── USB/IP Kernel-Module konfigurieren ───────────────────────────────────────
info "Konfiguriere USB/IP Kernel-Module..."

# .config patchen (dot-config-usbip als Overlay)
OPENWRT_DIR=$(find . -maxdepth 3 -name ".config" -not -path "*/gl-infra-builder/.config" 2>/dev/null \
    | head -1 | xargs dirname 2>/dev/null || \
    find . -maxdepth 3 -type d -name "openwrt*" 2>/dev/null | head -1)

if [ -z "$OPENWRT_DIR" ]; then
    # Build-Umgebung noch nicht vollständig — feeds update nötig
    info "Führe feeds update aus (kann einige Minuten dauern)..."
    make feeds/update -j$(nproc) V=s 2>&1 | tail -5
    OPENWRT_DIR="."
fi

# USB/IP Konfiguration in .config eintragen
DOT_CONFIG="$OPENWRT_DIR/.config"

if [ -f "$SCRIPT_DIR/dot-config-usbip" ]; then
    info "Wende dot-config-usbip Overlay an..."
    cat "$SCRIPT_DIR/dot-config-usbip" >> "$DOT_CONFIG"
else
    info "Schreibe USB/IP Konfiguration..."
    cat >> "$DOT_CONFIG" << 'CONFIG'
# USB/IP Kernel-Module
CONFIG_USBIP_CORE=m
CONFIG_USBIP_HOST=m
CONFIG_PACKAGE_kmod-usbip=m
CONFIG_PACKAGE_kmod-usbip-host=m
CONFIG_PACKAGE_usbip-server=y
CONFIG_PACKAGE_usbip-client=y
# USB Serial (FTDI für CDP+)
CONFIG_USB_SERIAL=m
CONFIG_USB_SERIAL_FTDI_SIO=m
CONFIG_PACKAGE_kmod-usb-serial=m
CONFIG_PACKAGE_kmod-usb-serial-ftdi=m
CONFIG

fi

make defconfig 2>/dev/null | tail -3

# ── Nur Kernel-Module bauen (kein vollständiges Image) ───────────────────────
info "Baue Kernel-Module (nur kmod-usbip*)..."
info "Dauer: ~15–45 Minuten beim ersten Mal..."

# Nur die Kernel-Module kompilieren — deutlich schneller als ein Full-Build
make target/linux/{clean,prepare} V=s -j$(nproc) 2>&1 | tail -10 || \
make target/linux/prepare V=s -j$(nproc) 2>&1 | tail -10

make package/kernel/linux/compile V=s -j$(nproc) 2>&1 | \
    grep -E '(ERROR|WARNING|Building|kmod-usbip)' || true

# ── Pakete suchen und sammeln ────────────────────────────────────────────────
info "Suche generierte .ipk-Pakete..."

PKG_OUT="$BUILD_DIR/packages"
mkdir -p "$PKG_OUT"

for pkg in kmod-usbip kmod-usbip-host usbip-server usbip-client \
           kmod-usb-serial kmod-usb-serial-ftdi; do
    found=$(find . -name "${pkg}_*.ipk" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        cp "$found" "$PKG_OUT/"
        info "  ✓ $(basename $found)"
    else
        warning "  ✗ $pkg nicht gefunden"
    fi
done

# ── Zusammenfassung ───────────────────────────────────────────────────────────
echo ""
info "═══════════════════════════════════════════════"
IPK_COUNT=$(ls "$PKG_OUT"/*.ipk 2>/dev/null | wc -l)
info "Build abgeschlossen: $IPK_COUNT Pakete in $PKG_OUT"
echo ""
ls -lh "$PKG_OUT"/*.ipk 2>/dev/null || warning "Keine .ipk-Dateien gefunden"
echo ""
info "Nächste Schritte:"
info "  1. IPKs auf GL-BE3600 übertragen:"
info "     scp $PKG_OUT/kmod-usbip*.ipk root@192.168.8.1:/tmp/"
info ""
info "  2. Auf GL-BE3600 installieren:"
info "     ssh root@192.168.8.1"
info "     opkg install /tmp/kmod-usbip_*.ipk"
info "     opkg install /tmp/kmod-usbip-host_*.ipk"
info "     opkg install /tmp/usbip-server_*.ipk 2>/dev/null || true"
info ""
info "  3. USB/IP Service installieren:"
info "     scp usbipd-openwrt root@192.168.8.1:/etc/init.d/usbipd"
info "     ssh root@192.168.8.1 'chmod +x /etc/init.d/usbipd && /etc/init.d/usbipd enable && /etc/init.d/usbipd start'"
info "═══════════════════════════════════════════════"
