#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# SDK-Build: USB/IP Kernel-Module für GL-BE10000 (Slate 7 Pro)
#
# ⚠️ PROTOTYPE: SoC und SDK-Profil noch unbekannt.
#    GL_SDK_PROFILE env setzen wenn Profil bekannt:
#      GL_SDK_PROFILE=<profil> ./build_usbip_modules.sh
#
# Voraussetzung: GL.iNet SDK für GL-BE10000 aus dem offiziellen SDK-Repository
# SDK-Repo: https://github.com/gl-inet/sdk (nach Verfügbarkeit für BE10000)
#
# Ergebnis:
#   ./bin/targets/.../kmod-usbip_*.ipk
#   ./bin/targets/.../kmod-usbip-host_*.ipk
# ─────────────────────────────────────────────────────────────────────────────

set -e

SDK_DIR="${SDK_DIR:-$(pwd)/gl-sdk}"
SDK_REPO="${SDK_REPO:-https://github.com/gl-inet/sdk}"

# TODO: verify on hardware — korrektes Profil bestätigen
# Mögliche Profile (nach git clone prüfen mit: ls configs/):
#   config-qsdk-ipq-5.4.yml
#   config-qsdk-be10000-5.4.yml   (hypothetisch)
#   config-wlan-ap-6.x.yml
GL_SDK_PROFILE="${GL_SDK_PROFILE:-}"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; C='\033[0;36m'; B='\033[1m'; N='\033[0m'
info()  { echo -e "${G}[sdk-build]${N} $1"; }
warn()  { echo -e "${Y}[sdk-build]${N} $1"; }
err()   { echo -e "${R}[sdk-build]${N} $1"; exit 1; }
step()  { echo -e "\n${C}${B}══ $1${N}"; }

echo ""
echo -e "${B}${C}╔══════════════════════════════════════════════╗"
echo -e "║  GL-BE10000 USB/IP SDK-Build — PROTOTYPE     ║"
echo -e "╚══════════════════════════════════════════════╝${N}"
echo ""
warn "PROTOTYPE: SDK-Profil noch nicht bestätigt!"
warn "GL_SDK_PROFILE ENV-Variable setzen wenn Profil bekannt."
echo ""

# ── 1. SDK klonen ─────────────────────────────────────────────────────────────
step "GL.iNet SDK klonen"

if [ -d "$SDK_DIR" ]; then
    info "SDK-Verzeichnis bereits vorhanden: $SDK_DIR"
    info "Update via: cd $SDK_DIR && git pull"
else
    info "Klone GL.iNet SDK → $SDK_DIR"
    git clone --depth=1 "$SDK_REPO" "$SDK_DIR" || {
        warn "SDK-Clone fehlgeschlagen. Manuelle Alternativen:"
        warn "  1. GL.iNet Forum: https://forum.gl-inet.com → SDK für BE10000"
        warn "  2. OpenWrt Buildroot: https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem"
        exit 1
    }
fi

cd "$SDK_DIR"

# ── 2. Verfügbare Profile anzeigen ────────────────────────────────────────────
step "Verfügbare SDK-Profile"
if [ -d "configs" ]; then
    info "Verfügbare Profile in configs/:"
    ls configs/*.yml 2>/dev/null | while read f; do echo "  $(basename $f)"; done
    echo ""
    if [ -z "$GL_SDK_PROFILE" ]; then
        warn "GL_SDK_PROFILE nicht gesetzt!"
        warn "Setzen und erneut ausführen:"
        warn "  GL_SDK_PROFILE=<profil-datei> $0"
        warn ""
        warn "Für GL-BE10000 wahrscheinlich zutreffende Profile:"
        ls configs/ 2>/dev/null | grep -i 'be10000\|qsdk\|wifi7\|be' | \
            while read f; do warn "  $f"; done || \
            warn "  (Kein passendes Profil gefunden — manuell auswählen)"
        exit 1
    fi
else
    warn "configs/ Verzeichnis nicht gefunden (anderes SDK-Layout?)"
    warn "Profile manuell prüfen: ls $SDK_DIR"
fi

# ── 3. .config erstellen ──────────────────────────────────────────────────────
step "Konfiguration erstellen"

if [ -n "$GL_SDK_PROFILE" ]; then
    info "Verwende Profil: $GL_SDK_PROFILE"
    ./scripts/gen_config.py "$GL_SDK_PROFILE" 2>/dev/null || \
    cp "configs/$GL_SDK_PROFILE" .config 2>/dev/null || {
        warn "Profil-Generierung fehlgeschlagen."
        warn "Manuell: cp configs/$GL_SDK_PROFILE .config"
        exit 1
    }
fi

# USB/IP-Konfiguration anhängen
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/dot-config-usbip" ]; then
    cat "$SCRIPT_DIR/dot-config-usbip" >> .config
    info "dot-config-usbip Overlay angehängt ✓"
else
    info "USB/IP-Config direkt schreiben..."
    cat >> .config << 'EOF'
# USB/IP — GL-BE10000 (TODO: verify on hardware)
CONFIG_USBIP_CORE=m
CONFIG_USBIP_HOST=m
CONFIG_USB_SERIAL=m
CONFIG_USB_SERIAL_FTDI_SIO=m
CONFIG_PACKAGE_usbip=y
CONFIG_PACKAGE_usbip-server=y
CONFIG_PACKAGE_kmod-usbip=y
CONFIG_PACKAGE_kmod-usbip-host=y
EOF
fi

# ── 4. Defconfig + Build ──────────────────────────────────────────────────────
step "make defconfig"
make defconfig 2>&1 | tail -5

step "USB/IP Module bauen (kmod-usbip + kmod-usbip-host)"
warn "Dauer: 10-30 Minuten je nach System..."

make package/kmod-usbip/compile V=s 2>&1 | tail -20 && \
    info "kmod-usbip ✓" || {
    warn "kmod-usbip build fehlgeschlagen — Fallback: Standard-Pakete"
    warn "  opkg install kmod-usbip kmod-usbip-host"
    exit 1
}

make package/usbip/compile V=s 2>&1 | tail -20 && \
    info "usbip-tools ✓" || \
    warn "usbip-tools build fehlgeschlagen (Kernel-Module reichen oft)"

# ── 5. IPK-Dateien anzeigen ───────────────────────────────────────────────────
step "Build-Ergebnisse"
find bin/ -name '*.ipk' 2>/dev/null | grep -i 'usbip\|serial' | while read ipk; do
    info "$(basename $ipk)"
    echo "  → $ipk"
done || warn "Keine .ipk Dateien gefunden"

echo ""
echo -e "${G}${B}SDK-Build abgeschlossen! [PROTOTYPE]${N}"
echo ""
echo "Installation auf GL-BE10000 (192.168.10.196):"
echo "  scp bin/targets/**/kmod-usbip*.ipk root@192.168.10.196:/tmp/"
echo "  ssh root@192.168.10.196 'opkg install /tmp/kmod-usbip*.ipk'"
echo ""
warn "TODO: verify on hardware — Kernel-Module-Kompatibilität prüfen!"
echo ""
