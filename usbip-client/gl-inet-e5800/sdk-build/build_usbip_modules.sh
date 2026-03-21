#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# USB/IP Kernel-Module Build für GL.iNet GL-E5800 (Mudi 7)
#
# SoC: Qualcomm Dragonwing MBB Gen 3 (X72) — ARM64
#
# HINWEIS: Das exakte SDK-Profil für den X72-SoC muss ggf. von GL.iNet
#          angepasst werden. Dieses Skript nutzt einen generischen
#          Qualcomm-QSDK-Ansatz als Startpunkt.
#
# Voraussetzungen (auf Ubuntu/Debian Build-System):
#   sudo apt install -y build-essential git python3 libncurses-dev \
#                       gawk unzip file wget libssl-dev
#
# Verwendung:
#   chmod +x build_usbip_modules.sh
#   ./build_usbip_modules.sh
#
# Ausgabe: kmod-usbip_*.ipk + kmod-usbip-host_*.ipk im aktuellen Verzeichnis
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/gl-infra-builder"
# TODO: Korrektes Profil nach Hardware-Test bestätigen
# Mögliche Profile: config-qsdk-ipq-5.4.yml, config-wlan-ap-5.4-dragonwing.yml
SDK_PROFILE="${GL_SDK_PROFILE:-config-qsdk-ipq-5.4.yml}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[sdk]${NC} $1"; }
warning() { echo -e "${YELLOW}[sdk]${NC} $1"; }
err()     { echo -e "${RED}[sdk]${NC} $1"; exit 1; }

info "USB/IP Module Build — GL-E5800 (Mudi 7 / Qualcomm X72)"
info "SDK-Profil: $SDK_PROFILE"
echo ""

warning "HINWEIS: Das X72-SDK-Profil ist noch nicht final bestätigt."
warning "         Prüfe verfügbare Profile nach SDK-Clone:"
warning "         ls gl-infra-builder/configs/"
echo ""

# ── 1. GL.iNet SDK klonen ─────────────────────────────────────────────────────
info "[1/5] GL.iNet SDK klonen..."

if [ -d "$BUILD_DIR/.git" ]; then
    info "      SDK bereits vorhanden — aktualisiere..."
    git -C "$BUILD_DIR" pull --rebase --autostash || warning "git pull fehlgeschlagen (fork?)"
else
    git clone \
        --depth 1 \
        https://github.com/gl-inet/gl-infra-builder.git \
        "$BUILD_DIR" || err "git clone fehlgeschlagen"
    info "      SDK geklont ✓"
fi

# ── 2. SDK initialisieren ─────────────────────────────────────────────────────
info "[2/5] SDK für $SDK_PROFILE initialisieren..."

cd "$BUILD_DIR"

# Verfügbare Profile anzeigen (Orientierung)
AVAILABLE=$(ls configs/ 2>/dev/null | grep -i 'ipq\|qsdk\|dragonwing' || echo "(keine ipq/dragonwing Profile gefunden)")
info "      Verfügbare Qualcomm-Profile: $AVAILABLE"

if [ ! -f "configs/$SDK_PROFILE" ]; then
    warning "Profil $SDK_PROFILE nicht gefunden!"
    warning "Wähle ein Profil aus der obigen Liste und setze:"
    warning "  GL_SDK_PROFILE=<profil> ./build_usbip_modules.sh"
    err "Profil nicht gefunden — Build abgebrochen"
fi

python3 setup.py -c "configs/$SDK_PROFILE" || err "SDK-Initialisierung fehlgeschlagen"

# SDK-Arbeitsverzeichnis ermitteln
SDK_WORK=$(ls -d */ 2>/dev/null | grep -i 'openwrt\|qsdk' | head -1 || echo "")
if [ -z "$SDK_WORK" ]; then
    err "SDK-Arbeitsverzeichnis nicht gefunden nach setup.py"
fi

cd "$BUILD_DIR/$SDK_WORK"
info "      SDK-Arbeitsverzeichnis: $SDK_WORK ✓"

# ── 3. Kernel-Konfiguration anwenden ─────────────────────────────────────────
info "[3/5] Kernel-Config für USB/IP anwenden..."

CONFIG_OVERLAY="$SCRIPT_DIR/dot-config-usbip"
if [ -f "$CONFIG_OVERLAY" ]; then
    cat "$CONFIG_OVERLAY" >> .config
    info "      Kernel-Config-Overlay angewendet ✓"
else
    warning "dot-config-usbip nicht gefunden — manuell USB/IP aktivieren:"
    warning "  make menuconfig → Kernel modules → USB Support → USB/IP"
fi

# CONFIG_DEFAULT_HOSTNAME setzen (GL-E5800 kenntlich machen)
echo 'CONFIG_TARGET_BOARD_HOSTNAME="GL-E5800"' >> .config

make defconfig 2>/dev/null || true
info "      defconfig angewendet ✓"

# ── 4. Nur Kernel-Module bauen ────────────────────────────────────────────────
info "[4/5] Baue Kernel-Module (nur USB/IP, kein Full-Image)..."
info "      Dies kann 30-90 Minuten dauern..."

make target/linux/clean   V=s 2>&1 | tail -5 || warning "clean fehlgeschlagen (ignoriert)"
make target/linux/compile V=s -j$(nproc) 2>&1 | grep -E 'ERROR|error:|warning:|Building' | tail -30

info "      Kernel-Kompilierung abgeschlossen ✓"

# ── 5. IPK-Pakete sammeln ─────────────────────────────────────────────────────
info "[5/5] Sammle kmod-usbip IPK-Pakete..."

IPK_SRC=$(find staging_dir/target-*/root-*/usr/lib/opkg/info/ -name "kmod-usbip*.list" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || true)
if [ -z "$IPK_SRC" ]; then
    IPK_SRC=$(find bin/ -name "kmod-usbip*.ipk" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || true)
fi

FOUND=0
for pkg in usbip usbip-host usbip-core; do
    IPK=$(find . -name "kmod-${pkg}*.ipk" 2>/dev/null | head -1 || true)
    if [ -n "$IPK" ]; then
        cp "$IPK" "$SCRIPT_DIR/"
        info "      Kopiert: $(basename "$IPK") ✓"
        FOUND=$((FOUND + 1))
    fi
done

echo ""
if [ "$FOUND" -gt 0 ]; then
    info "═══════════════════════════════════════════════"
    info "Build erfolgreich! $FOUND IPK-Pakete bereit."
    info ""
    info "Installation auf GL-E5800:"
    info "  scp $SCRIPT_DIR/kmod-usbip*.ipk root@192.168.8.1:/tmp/"
    info "  ssh root@192.168.8.1 'opkg install /tmp/kmod-usbip*.ipk'"
    info "  ssh root@192.168.8.1 '/etc/init.d/usbipd start'"
    info "═══════════════════════════════════════════════"
else
    warning "Keine IPK-Pakete gefunden. Manuell suchen:"
    warning "  find $BUILD_DIR -name 'kmod-usbip*.ipk'"
    warning ""
    warning "Falls das Profil falsch ist, prüfe:"
    warning "  GL_SDK_PROFILE=<korrektes-profil> ./build_usbip_modules.sh"
fi
