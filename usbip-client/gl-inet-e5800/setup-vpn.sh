#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# GL.iNet GL-E5800 (Mudi 7) — VPN Setup (WireGuard + Tailscale)
#
# Richtet einen optionalen VPN-Tunnel auf dem Router ein.
# Zweck: Zugriff auf den GL-E5800 und OBD2-Daten von außerhalb des Heimnetzes.
#
# Wird LOKAL ausgeführt und konfiguriert den Router via SSH.
# Voraussetzung: ssh-manager.sh Verbindung funktioniert.
#
# VERWENDUNG:
#   ./setup-vpn.sh [OPTIONEN]
#
# OPTIONEN:
#   -h HOST           Router-IP (Standard: 192.168.10.195)
#   -p PASS           SSH-Passwort (Standard: goodlife)
#   -k KEY            SSH-Key-Datei
#
#   WireGuard:
#   -c CONF           Bestehende WireGuard .conf-Datei importieren
#   -s SERVER         WireGuard-Server (Endpoint)
#   -P PORT           WireGuard UDP-Port (Standard: 51820)
#   --split           Split-Tunnel: nur Heimnetz-Traffic über VPN (Standard)
#   --full            Full-Tunnel: gesamter Traffic über VPN
#   --peer            Peer-Mode: Router verbindet sich mit VPN-Server (Standard)
#   --server          Server-Mode: Router ist selbst der VPN-Server
#
#   Tailscale:
#   --tailscale       Tailscale statt WireGuard installieren (empfohlen)
#   -t AUTHKEY        Tailscale Auth-Key (tskey-auth-xxx von tailscale.com)
#   --subnet          Heimnetz (192.168.10.0/24) als Subnet-Route exponieren
#   --exit-node       Router als Exit-Node (Full-Tunnel-Ausgang) anbieten
#
# BEISPIELE:
#   ./setup-vpn.sh --tailscale -t tskey-auth-xxx          # Tailscale (einfach)
#   ./setup-vpn.sh --tailscale -t tskey-auth-xxx --subnet # + Heimnetz-Zugang
#   ./setup-vpn.sh -c ~/myvpn.conf                        # WireGuard Config
#   ./setup-vpn.sh --server                               # Router als WG-Server
# ─────────────────────────────────────────────────────────────────────────────

set -e

SSH_HOST="192.168.10.195"
SSH_PASS="goodlife"
SSH_PORT=22
SSH_KEY=""
WG_CONF=""
WG_SERVER=""
WG_PORT=51820
VPN_MODE="peer"
TUNNEL_MODE="split"
USE_TAILSCALE=0
TS_AUTHKEY=""
TS_SUBNET=0
TS_EXIT_NODE=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; C='\033[0;36m'; B='\033[1m'; N='\033[0m'
info()  { echo -e "${G}[vpn]${N} $1"; }
step()  { echo -e "\n${C}${B}══ $1${N}"; }
ok()    { echo -e "${G}  ✓${N} $1"; }
warn()  { echo -e "${Y}  !${N} $1"; }
err()   { echo -e "${R}[vpn]${N} $1"; exit 1; }

while getopts "h:p:k:c:s:P:t:-:" opt; do
    case $opt in
        h) SSH_HOST="$OPTARG" ;;
        p) SSH_PASS="$OPTARG" ;;
        k) SSH_KEY="$OPTARG" ;;
        c) WG_CONF="$OPTARG" ;;
        s) WG_SERVER="$OPTARG" ;;
        P) WG_PORT="$OPTARG" ;;
        t) TS_AUTHKEY="$OPTARG" ;;
        -)
            case "$OPTARG" in
                split)      TUNNEL_MODE="split" ;;
                full)       TUNNEL_MODE="full" ;;
                peer)       VPN_MODE="peer" ;;
                server)     VPN_MODE="server" ;;
                tailscale)  USE_TAILSCALE=1 ;;
                subnet)     TS_SUBNET=1 ;;
                exit-node)  TS_EXIT_NODE=1 ;;
            esac ;;
    esac
done

# SSH-Wrapper
_ssh() {
    local ssh_opts="-p $SSH_PORT -o StrictHostKeyChecking=no -o ConnectTimeout=8"
    if [ -n "$SSH_KEY" ]; then
        ssh $ssh_opts -i "$SSH_KEY" "root@${SSH_HOST}" "$@"
    elif command -v sshpass >/dev/null 2>&1; then
        sshpass -p "$SSH_PASS" ssh $ssh_opts "root@${SSH_HOST}" "$@"
    else
        ssh $ssh_opts "root@${SSH_HOST}" "$@"
    fi
}

_scp() {
    local ssh_opts="-P $SSH_PORT -o StrictHostKeyChecking=no"
    if [ -n "$SSH_KEY" ]; then
        scp $ssh_opts -i "$SSH_KEY" "$1" "root@${SSH_HOST}:$2"
    elif command -v sshpass >/dev/null 2>&1; then
        sshpass -p "$SSH_PASS" scp $ssh_opts "$1" "root@${SSH_HOST}:$2"
    else
        scp $ssh_opts "$1" "root@${SSH_HOST}:$2"
    fi
}

# ── Modus: Config importieren ─────────────────────────────────────────────────
_import_config() {
    step "WireGuard Config importieren"
    [ -f "$WG_CONF" ] || err "Config-Datei nicht gefunden: $WG_CONF"

    info "Übertrage: $WG_CONF → /etc/wireguard/"
    _ssh "mkdir -p /etc/wireguard && chmod 700 /etc/wireguard"
    _scp "$WG_CONF" "/etc/wireguard/$(basename "$WG_CONF")"
    _ssh "chmod 600 /etc/wireguard/$(basename "$WG_CONF")"

    local iface
    iface=$(basename "$WG_CONF" .conf)

    step "WireGuard Pakete installieren"
    _ssh "
if ! command -v wg >/dev/null 2>&1; then
    opkg update -q 2>/dev/null || true
    opkg install wireguard-tools kmod-wireguard 2>/dev/null && \
        echo 'wireguard-tools installiert' || \
        echo 'Hinweis: GL.iNet Firmware hat WireGuard evtl. bereits eingebaut'
else
    echo 'WireGuard bereits vorhanden'
fi
"

    step "WireGuard Netzwerk-Interface konfigurieren (UCI)"
    _ssh "
IFACE='$iface'
CONF='/etc/wireguard/$iface.conf'

uci -q delete network.\$IFACE 2>/dev/null || true

uci set network.\$IFACE=interface
uci set network.\$IFACE.proto='wireguard'
uci set network.\$IFACE.private_key=\$(grep 'PrivateKey' \"\$CONF\" | awk '{print \$3}')

LPORT=\$(grep 'ListenPort' \"\$CONF\" | awk '{print \$3}')
[ -n \"\$LPORT\" ] && uci set network.\$IFACE.listen_port=\"\$LPORT\"

ADDR=\$(grep 'Address' \"\$CONF\" | awk '{print \$3}')
[ -n \"\$ADDR\" ] && uci set network.\$IFACE.addresses=\"\$ADDR\"

uci commit network

PEER_KEY=\$(grep 'PublicKey' \"\$CONF\" | awk '{print \$3}')
ENDPOINT=\$(grep 'Endpoint' \"\$CONF\" | awk '{print \$3}')
ALLOWED=\$(grep 'AllowedIPs' \"\$CONF\" | awk '{print \$3}')

if [ -n \"\$PEER_KEY\" ]; then
    uci -q delete network.wgpeer_\$IFACE 2>/dev/null || true
    uci set network.wgpeer_\$IFACE=wireguard_\$IFACE
    uci set network.wgpeer_\$IFACE.public_key=\"\$PEER_KEY\"
    [ -n \"\$ENDPOINT\" ]  && uci set network.wgpeer_\$IFACE.endpoint_host=\"\${ENDPOINT%:*}\" && \
                              uci set network.wgpeer_\$IFACE.endpoint_port=\"\${ENDPOINT#*:}\"
    [ -n \"\$ALLOWED\" ]   && uci set network.wgpeer_\$IFACE.allowed_ips=\"\$ALLOWED\"
    uci set network.wgpeer_\$IFACE.persistent_keepalive='25'
    uci commit network
fi

echo 'UCI-Konfiguration abgeschlossen'
echo \"Interface: \$IFACE | Peer: \${ENDPOINT:-unbekannt} | IPs: \${ADDR:-unbekannt}\"
"

    step "Firewall-Regel für WireGuard"
    _ssh "
IFACE='$iface'
uci -q del_list firewall.@zone[0].network=\"\$IFACE\" 2>/dev/null || true
uci add_list firewall.@zone[0].network=\"\$IFACE\"
uci commit firewall
/etc/init.d/firewall reload 2>/dev/null || true
echo 'Firewall: \$IFACE → lan-Zone'
"

    step "VPN-Service einrichten + starten"
    _ssh "
IFACE='$iface'
CONF='/etc/wireguard/\$IFACE.conf'

cat > /etc/init.d/vpn-\$IFACE << 'INITD'
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=97
STOP=5

start_service() {
    procd_open_instance
    procd_set_param command /sbin/ip link show \${IFACE} 2>/dev/null || \
                            wg-quick up \${CONF}
    procd_close_instance
}

stop_service() {
    wg-quick down \${CONF} 2>/dev/null || true
}
INITD

wg-quick up \"\$CONF\" 2>&1 || /etc/init.d/network restart
chmod +x /etc/init.d/vpn-\$IFACE
/etc/init.d/vpn-\$IFACE enable
echo 'VPN-Service aktiviert: vpn-\$IFACE'
"

    _show_vpn_status
}

# ── Modus: Server ─────────────────────────────────────────────────────────────
_setup_server() {
    step "Router als WireGuard-Server konfigurieren"
    warn "In diesem Modus können sich externe Geräte mit dem Router verbinden."

    step "WireGuard-Keys generieren"
    _ssh "
mkdir -p /etc/wireguard && chmod 700 /etc/wireguard
cd /etc/wireguard

if [ ! -f server_private.key ]; then
    if command -v wg >/dev/null 2>&1; then
        wg genkey | tee server_private.key | wg pubkey > server_public.key
        echo 'Keys generiert via wg'
    else
        dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 > server_private.key
        echo 'Fallback-Keys generiert'
    fi
    chmod 600 server_private.key
fi

PRIV_KEY=\$(cat server_private.key)
PUB_KEY=\$(cat server_public.key 2>/dev/null || echo '(Public Key nicht verfügbar)')
echo ''
echo '=== WireGuard Server-Keys ==='
echo \"Private: \$PRIV_KEY\"
echo \"Public:  \$PUB_KEY\"
"

    local wg_subnet="10.100.0.1/24"
    local wg_port="$WG_PORT"

    _ssh "
cat > /etc/wireguard/wg-server.conf << EOF
[Interface]
Address = $wg_subnet
ListenPort = $wg_port
PrivateKey = \$(cat /etc/wireguard/server_private.key)
PostUp = iptables -A FORWARD -i wg-server -j ACCEPT; iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg-server -j ACCEPT; iptables -t nat -D POSTROUTING -o wlan0 -j MASQUERADE

# [Peer]
# PublicKey = <CLIENT_PUBLIC_KEY>
# AllowedIPs = 10.100.0.2/32
EOF

chmod 600 /etc/wireguard/wg-server.conf
echo 'Server-Config: /etc/wireguard/wg-server.conf'
"

    step "Firewall: UDP-Port $WG_PORT öffnen"
    _ssh "
uci -q delete firewall.wg_allow 2>/dev/null || true
uci set firewall.wg_allow=rule
uci set firewall.wg_allow.name='WireGuard VPN'
uci set firewall.wg_allow.src='wan'
uci set firewall.wg_allow.dest_port='$wg_port'
uci set firewall.wg_allow.proto='udp'
uci set firewall.wg_allow.target='ACCEPT'
uci commit firewall
/etc/init.d/firewall reload 2>/dev/null
echo 'Firewall: UDP/$wg_port geöffnet'
"
    _show_vpn_status
}

# ── VPN-Status anzeigen ───────────────────────────────────────────────────────
_show_vpn_status() {
    step "VPN Status"
    _ssh "
echo 'WireGuard Interfaces:'
wg show 2>/dev/null || echo '  Kein aktives WireGuard Interface'
echo ''
echo 'Netzwerk-Interfaces:'
ip addr show 2>/dev/null | grep -E 'wg|inet ' | head -20
echo ''
echo '=== VPN Nutzung ==='
echo 'Status:   obd-ctl vpn status'
echo 'Start:    obd-ctl vpn start'
echo 'SSH:      ./ssh-manager.sh -h <vpn-ip> status'
"
}

# ── Modus: Tailscale ─────────────────────────────────────────────────────────
_setup_tailscale() {
    local authkey="$TS_AUTHKEY"
    local subnet_flag="$TS_SUBNET"
    local exit_flag="$TS_EXIT_NODE"
    local subnet_cidr="192.168.10.0/24"

    step "Tailscale Installation auf GL-E5800 (Mudi 7)"

    _ssh "
echo '=== Prüfe Tailscale-Installation ==='
if command -v tailscale >/dev/null 2>&1; then
    echo 'Tailscale bereits installiert: '\$(tailscale version 2>/dev/null | head -1)
else
    echo 'Installiere Tailscale...'

    if opkg list 2>/dev/null | grep -q '^tailscale '; then
        opkg install tailscale tailscaled && echo 'Tailscale via opkg installiert'
    else
        echo 'Lade offizielles Tailscale ARM64-Binary...'
        TS_VERSION=\$(curl -s https://pkgs.tailscale.com/stable/?mode=json 2>/dev/null | \
            python3 -c \"import sys,json; d=json.load(sys.stdin); print(d['Tarballs']['arm64'])\" 2>/dev/null || \
            echo 'tailscale_1.78.0_arm64.tgz')

        curl -L \"https://pkgs.tailscale.com/stable/\$TS_VERSION\" -o /tmp/tailscale.tgz
        tar xzf /tmp/tailscale.tgz -C /tmp/
        TS_DIR=\$(ls -d /tmp/tailscale_* 2>/dev/null | head -1)

        install -m 755 \"\$TS_DIR/tailscale\"  /usr/bin/tailscale
        install -m 755 \"\$TS_DIR/tailscaled\" /usr/sbin/tailscaled
        rm -rf /tmp/tailscale* || true
        echo 'Tailscale '\$(tailscale version | head -1)' installiert'
    fi
fi
"

    _ssh "
modprobe tun 2>/dev/null || insmod /lib/modules/\$(uname -r)/tun.ko 2>/dev/null || true
ls /dev/net/tun 2>/dev/null || { mkdir -p /dev/net; mknod /dev/net/tun c 10 200; chmod 666 /dev/net/tun; }
echo 'TUN-Device: '\$(ls -la /dev/net/tun)
"

    step "tailscaled Daemon einrichten"
    _ssh "
mkdir -p /etc/tailscale

cat > /etc/init.d/tailscaled << 'INITD'
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=98
STOP=4

start_service() {
    modprobe tun 2>/dev/null || true
    procd_open_instance
    procd_set_param command /usr/sbin/tailscaled \
        --state /etc/tailscale/state \
        --socket /var/run/tailscale/tailscaled.sock \
        --tun userspace-networking
    procd_set_param respawn 3600 5 3
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    /usr/bin/tailscale down 2>/dev/null || true
}
INITD

chmod +x /etc/init.d/tailscaled
mkdir -p /var/run/tailscale

/etc/init.d/tailscaled enable
/etc/init.d/tailscaled restart
sleep 3

if pgrep tailscaled >/dev/null 2>&1; then
    echo 'tailscaled läuft ✓'
else
    echo 'WARNUNG: tailscaled nicht gestartet — prüfe: logread | grep tailscale'
fi
"

    step "Tailscale authentifizieren"
    if [ -n "$authkey" ]; then
        info "Authentifiziere mit Auth-Key..."
        local ts_args="--authkey $authkey --hostname gl-e5800-obd"
        [ "$subnet_flag" = "1" ] && ts_args="$ts_args --advertise-routes=$subnet_cidr"
        [ "$exit_flag"   = "1" ] && ts_args="$ts_args --advertise-exit-node"
        ts_args="$ts_args --accept-routes --accept-dns=false"

        _ssh "
tailscale up $ts_args 2>&1
echo ''
echo 'Tailscale Status:'
tailscale status 2>/dev/null || echo '(Status noch nicht verfügbar)'
echo ''
echo 'Tailscale IP:'
tailscale ip 2>/dev/null || echo '(IP noch nicht zugewiesen)'
"
    else
        warn "Kein Auth-Key angegeben (-t tskey-auth-xxx)."
        _ssh "
echo 'Authentifizierungs-URL:'
tailscale up --hostname gl-e5800-obd 2>&1 | grep 'https://' || \
    echo 'tailscale up ausführen und URL im Browser öffnen'
"
    fi

    if [ "$subnet_flag" = "1" ]; then
        step "Subnet Routing: $subnet_cidr exponieren"
        _ssh "
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -s 100.64.0.0/10 -d $subnet_cidr -j MASQUERADE 2>/dev/null || true
echo 'Subnet-Routing konfiguriert: $subnet_cidr'
echo 'WICHTIG: Im Tailscale Admin-Panel Routes bestätigen'
"
    fi

    step "Firewall für Tailscale konfigurieren"
    _ssh "
uci -q del_list firewall.@zone[0].network='tailscale0' 2>/dev/null || true
uci add_list firewall.@zone[0].network='tailscale0' 2>/dev/null || true
uci commit firewall 2>/dev/null || true
/etc/init.d/firewall reload 2>/dev/null || true
echo 'Firewall: tailscale0 → lan'
"

    step "Tailscale Status"
    _ssh "
echo ''
echo '=== Tailscale Status ==='
tailscale status 2>/dev/null || echo '(warte auf Authentifizierung)'
echo ''
TS_IP=\$(tailscale ip 2>/dev/null | head -1)
echo \"\${TS_IP:-(noch nicht zugewiesen)}\"
[ -n \"\$TS_IP\" ] && echo 'SSH via Tailscale: ssh root@'\$TS_IP || true
[ -n \"\$TS_IP\" ] && echo 'OBD-API: curl http://'\$TS_IP':8765/obd/status' || true
"

    echo ""
    ok "Tailscale eingerichtet auf GL-E5800!"
    if [ "$subnet_flag" = "1" ]; then
        echo -e "  ${Y}WICHTIG:${N} Routes im Admin-Panel bestätigen:"
        echo -e "  → https://login.tailscale.com/admin/machines"
        echo -e "  → gl-e5800-obd → Edit route settings → ${subnet_cidr} aktivieren"
    fi
    echo ""
}

# ── Haupt ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${B}${C}╔══════════════════════════════════════════════════════╗"
echo -e "║  GL-E5800 (Mudi 7) WireGuard VPN Setup              ║"
echo -e "╚══════════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  Router:       ${B}${SSH_HOST}${N}"
if [ "$USE_TAILSCALE" = "1" ]; then
    echo -e "  VPN:          ${B}Tailscale${N}"
    [ -n "$TS_AUTHKEY" ] && echo -e "  Auth-Key:     ${B}${TS_AUTHKEY:0:20}…${N}" || echo -e "  Auth-Key:     ${Y}nicht angegeben (Browser-Login)${N}"
    [ "$TS_SUBNET" = "1" ] && echo -e "  Subnet:       ${B}192.168.10.0/24 wird exponiert${N}"
else
    echo -e "  VPN:          ${B}WireGuard${N}"
    echo -e "  Modus:        ${B}${VPN_MODE}${N} (${TUNNEL_MODE}-tunnel)"
    [ -n "$WG_CONF" ] && echo -e "  Config:       ${B}${WG_CONF}${N}"
fi
echo ""

if [ "$USE_TAILSCALE" = "1" ]; then
    _setup_tailscale
elif [ -n "$WG_CONF" ]; then
    _import_config
elif [ "$VPN_MODE" = "server" ]; then
    _setup_server
else
    err "Kein VPN-Modus gewählt. Optionen:

     Tailscale (empfohlen):
       --tailscale -t tskey-auth-xxx
       --tailscale -t tskey-auth-xxx --subnet

     WireGuard (bestehende Config):
       -c ~/meine-config.conf

     WireGuard (Router als Server):
       --server"
fi

echo ""
echo -e "${G}${B}VPN Setup abgeschlossen!${N}"
echo ""
echo -e "Steuerung: ./ssh-manager.sh -h $SSH_HOST run 'obd-ctl vpn status'"
echo ""

# QR-Code (WireGuard Config)
if command -v qrcreds &>/dev/null && [ -n "$WG_CONF" ] && [ -f "$WG_CONF" ]; then
    echo ""
    echo -e "${G}${B}═══ WireGuard QR-Code ═══${N}"
    qrcreds generate wireguard --config "$WG_CONF" 2>/dev/null || true
fi
if command -v qrcreds &>/dev/null && [ -n "${QR_PIN:-}" ]; then
    echo ""
    echo -e "${G}${B}═══ SSH-Zugang GL-E5800 per QR ═══${N}"
    qrcreds generate ssh \
        --host "$SSH_HOST" --user root \
        --alias "gl-e5800" \
        --pin "$QR_PIN" --expires 60 2>/dev/null || true
    echo -e "  PIN: ${QR_PIN}  |  Termius App → QR scannen"
fi
