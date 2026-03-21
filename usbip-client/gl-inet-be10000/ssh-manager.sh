#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# GL.iNet GL-BE10000 (Slate 7 Pro) — SSH-Manager
# ⚠️ PROTOTYPE — Hardware noch nicht allgemein verfügbar
#
# Vollständige Einrichtung und Steuerung des Routers über SSH.
# Läuft auf dem LOKALEN Rechner (Windows/WSL, Linux, macOS).
#
# VERWENDUNG:
#   ./ssh-manager.sh [OPTIONEN] BEFEHL [ARGUMENTE]
#
# OPTIONEN:
#   -h HOST       Router-IP (Standard: 192.168.8.1 = GL.iNet Default)
#   -p PASS       SSH-Passwort (Standard: goodlife)
#   -k KEYFILE    SSH-Key-Datei (statt Passwort, empfohlen)
#   -P PORT       SSH-Port (Standard: 22)
#   -q            Ruhiger Modus (weniger Ausgabe)
#
# BEFEHLE:
#   setup              Vollständige Ersteinrichtung (alle Phasen)
#   setup-obd          Nur OBD2-Service einrichten
#   setup-display      Nur Display-Service einrichten (2.8" 320×240)
#   setup-wifi SSID PW WiFi-Client konfigurieren
#   setup-ip [WLAN-IP] [ETH-IP]  Statische IPs setzen
#   setup-key          SSH-Key auf Router einrichten
#
#   status             Kompakte Status-Übersicht aller Services
#   start  [svc]       Service starten  (all | obd | display | usbipd)
#   stop   [svc]       Service stoppen
#   restart [svc]      Service neu starten
#   enable [svc]       Service für Autostart aktivieren
#   disable [svc]      Autostart deaktivieren
#
#   logs [n]           Letzte n Logzeilen (Standard: 60)
#   follow             Logs live folgen (logread -f)
#   obd                OBD2 Live-Daten vom Router-API
#   bind               USB-Adapter an USB/IP binden
#   ip                 Alle Netzwerk-IPs anzeigen
#
#   deploy             Dateien auf Router übertragen
#   shell              Interaktive SSH-Shell öffnen
#   run CMD            Beliebigen Befehl auf dem Router ausführen
#   restore [MODE]     Deinstallieren: soft (Standard) | wifi | full
#   setup-vpn          VPN einrichten (WireGuard oder Tailscale)
#
# BEISPIELE:
#   ./ssh-manager.sh setup
#   ./ssh-manager.sh -h 192.168.10.196 status
#   ./ssh-manager.sh -k ~/.ssh/id_rsa restart obd
#   ./ssh-manager.sh logs 100
# ═══════════════════════════════════════════════════════════════════════════════

set -e

SSH_HOST="192.168.8.1"
SSH_PASS="goodlife"
SSH_PORT=22
SSH_KEY=""
QUIET=0

ROUTER_SETUP_DIR="/tmp/gl-inet-setup"
ROUTER_CTL="/usr/local/bin/obd-ctl"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

B='\033[1m'
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
C='\033[0;36m'
N='\033[0m'

info()    { [ "$QUIET" -eq 0 ] && echo -e "${G}[mgr]${N} $1"; }
step()    { echo -e "${C}${B}══ $1${N}"; }
warning() { echo -e "${Y}[mgr]${N} $1"; }
err()     { echo -e "${R}[mgr]${N} $1"; exit 1; }
ok()      { echo -e "${G}  ✓${N} $1"; }
fail()    { echo -e "${R}  ✗${N} $1"; }

while getopts "h:p:k:P:q" opt; do
    case $opt in
        h) SSH_HOST="$OPTARG" ;;
        p) SSH_PASS="$OPTARG" ;;
        k) SSH_KEY="$OPTARG" ;;
        P) SSH_PORT="$OPTARG" ;;
        q) QUIET=1 ;;
        *) _usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

COMMAND="${1:-help}"; shift 2>/dev/null || true

_ssh_opts() {
    local opts="-p $SSH_PORT -o StrictHostKeyChecking=no -o ConnectTimeout=8"
    opts+=" -o ServerAliveInterval=30 -o BatchMode=no"
    if [ -n "$SSH_KEY" ]; then
        opts+=" -i $SSH_KEY -o PasswordAuthentication=no"
    fi
    echo "$opts"
}

_ssh() {
    local cmd="$*"
    local ssh_opts; ssh_opts="$(_ssh_opts)"
    if [ -n "$SSH_KEY" ]; then
        # shellcheck disable=SC2086
        ssh $ssh_opts "root@${SSH_HOST}" "$cmd"
    elif command -v sshpass >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        sshpass -p "$SSH_PASS" ssh $ssh_opts "root@${SSH_HOST}" "$cmd"
    else
        warning "sshpass nicht gefunden — SSH fragt nach Passwort: $SSH_PASS"
        # shellcheck disable=SC2086
        ssh $ssh_opts "root@${SSH_HOST}" "$cmd"
    fi
}

_ssh_tty() {
    local cmd="$*"
    local ssh_opts; ssh_opts="$(_ssh_opts)"
    if [ -n "$SSH_KEY" ]; then
        # shellcheck disable=SC2086
        ssh -t $ssh_opts "root@${SSH_HOST}" "$cmd"
    elif command -v sshpass >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        sshpass -p "$SSH_PASS" ssh -t $ssh_opts "root@${SSH_HOST}" "$cmd"
    else
        # shellcheck disable=SC2086
        ssh -t $ssh_opts "root@${SSH_HOST}" "$cmd"
    fi
}

_scp() {
    local src="$1"; local dst="$2"
    local ssh_opts; ssh_opts="$(_ssh_opts)"
    if [ -n "$SSH_KEY" ]; then
        # shellcheck disable=SC2086
        scp -r -P "$SSH_PORT" $ssh_opts "$src" "root@${SSH_HOST}:${dst}"
    elif command -v sshpass >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        sshpass -p "$SSH_PASS" scp -r -P "$SSH_PORT" $ssh_opts "$src" "root@${SSH_HOST}:${dst}"
    else
        # shellcheck disable=SC2086
        scp -r -P "$SSH_PORT" $ssh_opts "$src" "root@${SSH_HOST}:${dst}"
    fi
}

_check_reachable() {
    info "Prüfe Verbindung zu root@${SSH_HOST}:${SSH_PORT}..."
    if _ssh "echo OK" 2>/dev/null | grep -q OK; then
        ok "Router erreichbar: ${SSH_HOST}"
    else
        err "Router ${SSH_HOST}:${SSH_PORT} nicht erreichbar.
       Prüfe:
         • Router eingeschaltet und verbunden?
         • IP korrekt? (GL.iNet default: 192.168.8.1)
         • SSH-Port $SSH_PORT offen?
         • Passwort korrekt? (GL.iNet default: goodlife)"
    fi
}

_deploy() {
    step "Übertrage Dateien auf Router..."
    _ssh "rm -rf $ROUTER_SETUP_DIR && mkdir -p $ROUTER_SETUP_DIR"
    _scp "$SCRIPT_DIR/" "$ROUTER_SETUP_DIR"
    if [ -d "$SCRIPT_DIR/../obd-monitor" ]; then
        _ssh "mkdir -p $ROUTER_SETUP_DIR/obd-monitor"
        _scp "$SCRIPT_DIR/../obd-monitor/" "$ROUTER_SETUP_DIR/obd-monitor"
    fi
    ok "Dateien übertragen → $ROUTER_SETUP_DIR"
}

_setup_key() {
    local keyfile="${1:-$HOME/.ssh/id_rsa.pub}"
    [ -f "$keyfile" ] || keyfile="${keyfile%.pub}"
    [ -f "${keyfile}.pub" ] && keyfile="${keyfile}.pub"
    [ -f "$keyfile" ] || err "SSH-Public-Key nicht gefunden: $keyfile
     Erstellen: ssh-keygen -t ed25519 -f ~/.ssh/gl-be10000"
    step "Richte SSH-Key auf Router ein..."
    local pubkey; pubkey=$(cat "$keyfile")
    _ssh "mkdir -p /etc/dropbear && \
          grep -qF '$pubkey' /etc/dropbear/authorized_keys 2>/dev/null || \
          echo '$pubkey' >> /etc/dropbear/authorized_keys && \
          chmod 600 /etc/dropbear/authorized_keys"
    ok "SSH-Key eingerichtet: $keyfile"
}

_setup_wifi() {
    local ssid="${1:-HTP-1-2.4G}"
    local pass="${2:-test123456}"
    step "Konfiguriere WiFi-Client: '$ssid'..."
    _ssh "
uci -q delete wireless.wifinet_sta 2>/dev/null || true
uci set wireless.wifinet_sta=wifi-iface
uci set wireless.wifinet_sta.device='radio0'
uci set wireless.wifinet_sta.network='wwan'
uci set wireless.wifinet_sta.mode='sta'
uci set wireless.wifinet_sta.ssid='$ssid'
uci set wireless.wifinet_sta.encryption='psk2'
uci set wireless.wifinet_sta.key='$pass'
uci set wireless.wifinet_sta.disabled='0'
uci -q delete network.wwan 2>/dev/null || true
uci set network.wwan=interface
uci set network.wwan.proto='dhcp'
uci commit wireless
uci commit network
wifi reload
sleep 3
echo 'WiFi konfiguriert. SSID: $ssid'
ip addr show wlan0 2>/dev/null | grep 'inet ' || echo 'Warte auf IP...'
"
    ok "WiFi konfiguriert: '$ssid'"
}

_setup_ip() {
    local wifi_ip="${1:-192.168.10.196}"
    local eth_ip="${2:-192.168.10.191}"
    local gw="${3:-192.168.10.1}"
    step "Setze statische IPs: WiFi=$wifi_ip  Eth=$eth_ip..."
    _ssh "
uci set network.wwan.proto='static'
uci set network.wwan.ipaddr='$wifi_ip'
uci set network.wwan.netmask='255.255.255.0'
uci set network.wwan.gateway='$gw'
uci -q del_list network.wwan.dns 2>/dev/null || true
uci add_list network.wwan.dns='$gw'
uci add_list network.wwan.dns='8.8.8.8'
uci set network.lan.ipaddr='$eth_ip'
uci set network.lan.netmask='255.255.255.0'
uci commit network
/etc/init.d/network restart
sleep 4
echo 'IPs gesetzt:'
ip addr show wlan0 2>/dev/null | grep 'inet '
ip addr show br-lan 2>/dev/null | grep 'inet '
"
    ok "Statische IPs gesetzt. WiFi: $wifi_ip  LAN: $eth_ip"
    warning "WICHTIG: Router ist jetzt unter $wifi_ip erreichbar!"
    warning "Neu verbinden: ./ssh-manager.sh -h $wifi_ip status"
}

_setup_obd() {
    step "Installiere OBD2-Service..."
    _deploy
    _ssh "sh $ROUTER_SETUP_DIR/install_obd_openwrt.sh"
    ok "OBD2-Service installiert"
}

_setup_display() {
    step "Installiere Touchscreen-Display-Service (2.8\" 320×240)..."
    _deploy
    _ssh "sh $ROUTER_SETUP_DIR/obd-display/install_display.sh"
    ok "Display-Service installiert"
}

_deploy_ctl() {
    info "Deploye obd-ctl Management-CLI..."
    _scp "$SCRIPT_DIR/remote/obd-ctl" "$ROUTER_CTL"
    _ssh "chmod +x $ROUTER_CTL"
    ok "obd-ctl deployed → $ROUTER_CTL"
}

_setup_all() {
    echo ""
    echo -e "${B}${C}╔══════════════════════════════════════════════════════╗"
    echo -e "║  GL.iNet GL-BE10000 (Slate 7 Pro) — Ersteinrichtung  ║"
    echo -e "║  ⚠️  PROTOTYPE — TODO: verify on hardware             ║"
    echo -e "╚══════════════════════════════════════════════════════╝${N}"
    echo ""
    echo -e "  Router:  ${B}${SSH_HOST}${N}"
    echo -e "  SSH:     root@${SSH_HOST}:${SSH_PORT}"
    echo ""

    step "Phase 0 — Verbindung prüfen"
    _check_reachable

    local default_key="$HOME/.ssh/id_rsa.pub"
    if [ -f "$default_key" ] && [ -z "$SSH_KEY" ]; then
        step "Phase 1 — SSH-Key einrichten (empfohlen)"
        printf "  SSH-Key %s einrichten? [J/n] " "$default_key"
        read -r ans
        if [ "${ans:-J}" = "J" ] || [ "$ans" = "j" ]; then
            _setup_key "$default_key"
            SSH_KEY="${default_key%.pub}"
        fi
    fi

    step "Phase 2 — Dateien übertragen"
    _deploy
    _deploy_ctl

    step "Phase 3 — OBD2-Service"
    _ssh "sh $ROUTER_SETUP_DIR/install_obd_openwrt.sh"
    ok "OBD2-Service installiert"

    step "Phase 4 — Touchscreen-Display (2.8\")"
    _ssh "sh $ROUTER_SETUP_DIR/obd-display/install_display.sh"
    ok "Display-Service installiert"

    step "Phase 5 — WiFi-Konfiguration"
    printf "  SSID (Standard: HTP-1-2.4G): "; read -r ssid; ssid="${ssid:-HTP-1-2.4G}"
    printf "  WiFi-Passwort: "; read -r wpass; wpass="${wpass:-test123456}"
    _setup_wifi "$ssid" "$wpass"

    step "Phase 6 — Statische IPs"
    printf "  WiFi-IP (Standard: 192.168.10.196): "; read -r wip; wip="${wip:-192.168.10.196}"
    printf "  Ethernet-IP (Standard: 192.168.10.191): "; read -r eip; eip="${eip:-192.168.10.191}"
    _setup_ip "$wip" "$eip"

    step "Phase 7 — Verifikation"
    sleep 3
    SSH_HOST="$wip"
    _cmd_status

    echo ""
    echo -e "${B}${G}╔══════════════════════════════════════════════════════╗"
    echo -e "║  ✓ GL-BE10000 Einrichtung abgeschlossen! [PROTOTYPE]  ║"
    echo -e "╚══════════════════════════════════════════════════════╝${N}"
    echo ""
    echo -e "  WiFi-IP:  ${B}$wip${N}   LAN-IP: ${B}$eip${N}"
    echo -e "  Verbinden: ${B}./ssh-manager.sh -h $wip status${N}"
    echo ""
    warning "TODO: verify on hardware — Alle Konfigurationswerte prüfen!"
}

_cmd_status() {
    step "Router-Status: ${SSH_HOST}"
    _ssh_tty "
if command -v obd-ctl >/dev/null 2>&1; then
    obd-ctl status
else
    echo '--- Services ---'
    for svc in obd-monitor obd-display usbipd; do
        if [ -f /etc/init.d/\$svc ]; then
            state=\$(/etc/init.d/\$svc status 2>/dev/null | head -1 || echo 'unbekannt')
            printf '  %-14s %s\n' \"\$svc\" \"\$state\"
        fi
    done
    echo '--- Netzwerk ---'
    ip addr show 2>/dev/null | grep -E 'inet |^[0-9]+:' | grep -v '127.0.0.1' | head -15
    echo '--- OBD API ---'
    curl -s --max-time 2 http://127.0.0.1:8765/obd/status 2>/dev/null || echo 'OBD-API nicht erreichbar'
fi
"
}

_cmd_service() {
    local action="$1"; local svc="${2:-all}"
    step "${action}: $svc"
    _ssh "
case '$svc' in
    all)
        for s in usbipd obd-monitor obd-display; do
            [ -f /etc/init.d/\$s ] && /etc/init.d/\$s $action 2>/dev/null && echo \"  $action: \$s ✓\" || echo \"  $action: \$s (nicht installiert)\"
        done ;;
    obd)     [ -f /etc/init.d/obd-monitor ] && /etc/init.d/obd-monitor $action ;;
    display) [ -f /etc/init.d/obd-display  ] && /etc/init.d/obd-display $action ;;
    usbipd)  [ -f /etc/init.d/usbipd       ] && /etc/init.d/usbipd $action ;;
    *)       [ -f /etc/init.d/$svc          ] && /etc/init.d/$svc $action ;;
esac
"
    ok "$action $svc"
}

_cmd_logs()   { local n="${1:-60}"; step "Letzte $n Logzeilen (${SSH_HOST})"; _ssh_tty "logread | tail -$n"; }
_cmd_follow() { step "Live-Logs (${SSH_HOST}) — STRG+C zum Beenden"; _ssh_tty "logread -f"; }

_cmd_obd() {
    step "OBD2 Live-Daten (${SSH_HOST}:8765)"
    _ssh_tty "
STATUS=\$(curl -s --max-time 3 http://127.0.0.1:8765/obd/status 2>/dev/null)
DATA=\$(curl -s   --max-time 3 http://127.0.0.1:8765/obd/data   2>/dev/null)
echo ''
echo 'STATUS:'
echo \"\$STATUS\" | python3 -c \"
import json,sys
try:
    d=json.load(sys.stdin)
    print('  Verbunden:  ' + str(d.get('connected','-')))
    print('  Protokoll:  ' + str(d.get('protocol','-')))
    print('  Port:       ' + str(d.get('port','-')))
    e=d.get('error')
    if e: print('  Fehler:     ' + str(e))
except: print('  (kein JSON)')
\" 2>/dev/null || echo \"\$STATUS\"
echo ''
echo 'LIVE-DATEN:'
echo \"\$DATA\" | python3 -c \"
import json,sys
try:
    d=json.load(sys.stdin)
    def f(k,fmt,unit):
        v=d.get(k)
        return fmt.format(v)+unit if v is not None else '---'
    print('  RPM:         ' + f('rpm','{:.0f}',' rpm'))
    print('  Speed:       ' + f('speed','{:.0f}',' km/h'))
    print('  Coolant:     ' + f('coolant_temp','{:.0f}',' °C'))
    print('  Throttle:    ' + f('throttle','{:.0f}','%'))
    print('  Battery:     ' + f('battery_voltage','{:.1f}',' V'))
except: print('  (kein JSON)')
\" 2>/dev/null || echo \"\$DATA\"
echo ''
"
}

_cmd_bind() {
    step "Binde USB-Adapter an USB/IP..."
    _ssh "
VENDOR=0403; PRODUCT=d6da
[ -f /etc/obd-adapter.conf ] && . /etc/obd-adapter.conf
echo \"Adapter: \${ADAPTER_NAME:-Unbekannt} (\${VENDOR}:\${PRODUCT})\"
echo 'Verfügbare USB-Geräte:'
usbip list -l 2>/dev/null || echo '  (usbip nicht verfügbar)'
echo ''
BID=\$(usbip list -l 2>/dev/null | grep \"\${VENDOR}:\${PRODUCT}\" | grep -o 'busid [^ ]*' | awk '{print \$2}' | head -1)
if [ -n \"\$BID\" ]; then
    usbip bind -b \"\$BID\" && echo \"Adapter gebunden: \$BID ✓\" || echo 'Bind fehlgeschlagen'
else
    echo \"Adapter (\${VENDOR}:\${PRODUCT}) nicht gefunden. Eingesteckt?\"
    lsusb 2>/dev/null | head -10
fi
"
}

_cmd_ip() {
    step "Netzwerk-Interfaces (${SSH_HOST})"
    _ssh "
echo 'IP-Adressen:'
ip addr show 2>/dev/null | grep -E 'inet |^[0-9]+:' | grep -v '127.0.0.1'
echo ''
echo 'WiFi-Status:'
iwinfo wlan0 info 2>/dev/null | grep -E 'ESSID|Signal|Mode' || echo '  (iwinfo nicht verfügbar)'
echo ''
echo 'Routen:'
ip route 2>/dev/null | head -8
"
}

_cmd_restore() {
    local mode="${1:-soft}"
    step "Wiederherstellung: Modus '$mode'"
    if [ "$mode" = "full" ]; then
        echo -e "${R}${B}WARNUNG: full-Reset löscht ALLE Einstellungen!${N}"
        printf "Bestätigen mit 'RESET': "; read -r conf
        [ "$conf" = "RESET" ] || { info "Abgebrochen."; exit 0; }
    fi
    _ssh "
if [ -f $ROUTER_SETUP_DIR/restore_openwrt.sh ]; then
    sh $ROUTER_SETUP_DIR/restore_openwrt.sh $mode
elif [ -f /tmp/restore_openwrt.sh ]; then
    sh /tmp/restore_openwrt.sh $mode
else
    echo 'restore_openwrt.sh nicht gefunden — erst deploy ausführen'
fi
"
}

_cmd_shell() {
    step "Öffne SSH-Shell (${SSH_HOST}) — exit zum Beenden"
    local ssh_opts; ssh_opts="$(_ssh_opts)"
    if [ -n "$SSH_KEY" ]; then
        # shellcheck disable=SC2086
        ssh -t $ssh_opts "root@${SSH_HOST}"
    elif command -v sshpass >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        sshpass -p "$SSH_PASS" ssh -t $ssh_opts "root@${SSH_HOST}"
    else
        # shellcheck disable=SC2086
        ssh -t $ssh_opts "root@${SSH_HOST}"
    fi
}

_cmd_run() {
    local cmd="$*"
    [ -n "$cmd" ] || err "run: Kein Befehl angegeben."
    info "Führe aus auf ${SSH_HOST}: $cmd"
    _ssh_tty "$cmd"
}

_usage() {
    echo ""
    echo -e "${B}GL.iNet GL-BE10000 (Slate 7 Pro) — SSH-Manager [PROTOTYPE]${N}"
    echo ""
    echo -e "${B}VERWENDUNG:${N}  ./ssh-manager.sh [OPTIONEN] BEFEHL [ARGUMENTE]"
    echo ""
    echo "  setup               Vollständige Ersteinrichtung (7 Phasen)"
    echo "  setup-obd           OBD2-Service einrichten"
    echo "  setup-display       Display-Service (2.8\" 320×240)"
    echo "  setup-wifi SSID PW  WiFi-Client konfigurieren"
    echo "  setup-ip [WIP] [EIP] Statische IPs (Standard: .196/.191)"
    echo "  setup-key           SSH-Key einrichten"
    echo "  status              Service-Status"
    echo "  start|stop|restart [svc]  Service steuern (all|obd|display|usbipd)"
    echo "  logs [n]            Letzte n Logzeilen"
    echo "  follow              Logs live"
    echo "  obd                 OBD2 Live-Daten"
    echo "  bind                USB-Adapter binden"
    echo "  ip                  IPs anzeigen"
    echo "  shell               SSH-Shell"
    echo "  run CMD             Befehl ausführen"
    echo "  restore [soft|wifi|full]  Deinstallieren"
    echo "  setup-vpn           VPN einrichten"
    echo ""
    echo "  Standard WiFi-IP: 192.168.10.196  |  ETH-IP: 192.168.10.191"
    echo ""
}

# ── Haupt-Dispatcher ──────────────────────────────────────────────────────────
case "$COMMAND" in
    setup)           _setup_all ;;
    setup-obd)       _check_reachable; _setup_obd ;;
    setup-display)   _check_reachable; _setup_display ;;
    setup-wifi)      _check_reachable; _setup_wifi "$1" "$2" ;;
    setup-ip)        _check_reachable; _setup_ip "$1" "$2" "$3" ;;
    setup-key)       _check_reachable; _setup_key "$1" ;;
    deploy)          _check_reachable; _deploy; _deploy_ctl ;;

    status)          _check_reachable; _cmd_status ;;
    start)           _check_reachable; _cmd_service start  "$1" ;;
    stop)            _check_reachable; _cmd_service stop   "$1" ;;
    restart)         _check_reachable; _cmd_service restart "$1" ;;
    enable)          _check_reachable; _cmd_service enable "$1" ;;
    disable)         _check_reachable; _cmd_service disable "$1" ;;

    logs)            _check_reachable; _cmd_logs "$1" ;;
    follow)          _check_reachable; _cmd_follow ;;
    obd)             _check_reachable; _cmd_obd ;;
    bind)            _check_reachable; _cmd_bind ;;
    ip)              _check_reachable; _cmd_ip ;;

    shell)           _check_reachable; _cmd_shell ;;
    run)             _check_reachable; _cmd_run "$@" ;;
    restore)         _check_reachable; _cmd_restore "$1" ;;

    setup-vpn)       _check_reachable
                     vpn_args="-h $SSH_HOST -p $SSH_PASS"
                     [ -n "$SSH_KEY" ] && vpn_args="$vpn_args -k $SSH_KEY"
                     bash "$SCRIPT_DIR/setup-vpn.sh" $vpn_args "$@" ;;

    help|--help|-h)  _usage ;;
    *)               warning "Unbekannter Befehl: $COMMAND"; _usage; exit 1 ;;
esac
