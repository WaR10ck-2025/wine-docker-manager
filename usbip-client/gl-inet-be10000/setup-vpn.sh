#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# GL.iNet GL-BE10000 (Slate 7 Pro) — VPN Setup (WireGuard + Tailscale)
# ⚠️ PROTOTYPE — TODO: verify on hardware
#
# Wird LOKAL ausgeführt und konfiguriert den Router via SSH.
#
# VERWENDUNG:
#   ./setup-vpn.sh [OPTIONEN]
#
# OPTIONEN:
#   -h HOST           Router-IP (Standard: 192.168.10.196)
#   -p PASS           SSH-Passwort (Standard: goodlife)
#   -k KEY            SSH-Key-Datei
#
#   --tailscale       Tailscale installieren
#   -t AUTHKEY        Tailscale Auth-Key
#   --subnet          192.168.10.0/24 als Subnet-Route
#   -c CONF           WireGuard .conf importieren
#   --server          Router als WireGuard-Server
# ─────────────────────────────────────────────────────────────────────────────

set -e

SSH_HOST="192.168.10.196"
SSH_PASS="goodlife"
SSH_PORT=22
SSH_KEY=""
WG_CONF=""
WG_PORT=51820
VPN_MODE="peer"
TUNNEL_MODE="split"
USE_TAILSCALE=0
TS_AUTHKEY=""
TS_SUBNET=0
TS_EXIT_NODE=0

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; C='\033[0;36m'; B='\033[1m'; N='\033[0m'
info()  { echo -e "${G}[vpn]${N} $1"; }
step()  { echo -e "\n${C}${B}══ $1${N}"; }
ok()    { echo -e "${G}  ✓${N} $1"; }
warn()  { echo -e "${Y}  !${N} $1"; }
err()   { echo -e "${R}[vpn]${N} $1"; exit 1; }

while getopts "h:p:k:c:P:t:-:" opt; do
    case $opt in
        h) SSH_HOST="$OPTARG" ;;
        p) SSH_PASS="$OPTARG" ;;
        k) SSH_KEY="$OPTARG" ;;
        c) WG_CONF="$OPTARG" ;;
        P) WG_PORT="$OPTARG" ;;
        t) TS_AUTHKEY="$OPTARG" ;;
        -)
            case "$OPTARG" in
                tailscale)  USE_TAILSCALE=1 ;;
                subnet)     TS_SUBNET=1 ;;
                exit-node)  TS_EXIT_NODE=1 ;;
                server)     VPN_MODE="server" ;;
            esac ;;
    esac
done

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

_import_config() {
    step "WireGuard Config importieren"
    [ -f "$WG_CONF" ] || err "Config nicht gefunden: $WG_CONF"

    local iface; iface=$(basename "$WG_CONF" .conf)
    _ssh "mkdir -p /etc/wireguard && chmod 700 /etc/wireguard"
    _scp "$WG_CONF" "/etc/wireguard/$(basename "$WG_CONF")"
    _ssh "chmod 600 /etc/wireguard/$(basename "$WG_CONF")"

    _ssh "
if ! command -v wg >/dev/null 2>&1; then
    opkg update -q 2>/dev/null || true
    opkg install wireguard-tools kmod-wireguard 2>/dev/null || \
        echo 'WireGuard evtl. bereits in Firmware'
fi
IFACE='$iface'
CONF='/etc/wireguard/$iface.conf'
uci -q delete network.\$IFACE 2>/dev/null || true
uci set network.\$IFACE=interface
uci set network.\$IFACE.proto='wireguard'
uci set network.\$IFACE.private_key=\$(grep 'PrivateKey' \"\$CONF\" | awk '{print \$3}')
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
    [ -n \"\$ENDPOINT\" ] && uci set network.wgpeer_\$IFACE.endpoint_host=\"\${ENDPOINT%:*}\" && \
                              uci set network.wgpeer_\$IFACE.endpoint_port=\"\${ENDPOINT#*:}\"
    [ -n \"\$ALLOWED\" ] && uci set network.wgpeer_\$IFACE.allowed_ips=\"\$ALLOWED\"
    uci set network.wgpeer_\$IFACE.persistent_keepalive='25'
    uci commit network
fi
wg-quick up \"\$CONF\" 2>&1 || /etc/init.d/network restart
echo 'WireGuard aktiv'
"
    ok "WireGuard konfiguriert: $iface"
}

_setup_tailscale() {
    local authkey="$TS_AUTHKEY"
    local subnet_cidr="192.168.10.0/24"

    step "Tailscale auf GL-BE10000 [PROTOTYPE]"

    _ssh "
if command -v tailscale >/dev/null 2>&1; then
    echo 'Tailscale bereits installiert: '\$(tailscale version | head -1)
else
    if opkg list 2>/dev/null | grep -q '^tailscale '; then
        opkg install tailscale tailscaled
    else
        TS_VERSION=\$(curl -s https://pkgs.tailscale.com/stable/?mode=json 2>/dev/null | \
            python3 -c \"import sys,json; d=json.load(sys.stdin); print(d['Tarballs']['arm64'])\" 2>/dev/null || \
            echo 'tailscale_1.78.0_arm64.tgz')
        curl -L \"https://pkgs.tailscale.com/stable/\$TS_VERSION\" -o /tmp/tailscale.tgz
        tar xzf /tmp/tailscale.tgz -C /tmp/
        TS_DIR=\$(ls -d /tmp/tailscale_* | head -1)
        install -m 755 \"\$TS_DIR/tailscale\" /usr/bin/tailscale
        install -m 755 \"\$TS_DIR/tailscaled\" /usr/sbin/tailscaled
        rm -rf /tmp/tailscale*
        echo 'Tailscale installiert'
    fi
fi
"

    _ssh "
modprobe tun 2>/dev/null || true
ls /dev/net/tun 2>/dev/null || { mkdir -p /dev/net; mknod /dev/net/tun c 10 200; chmod 666 /dev/net/tun; }
mkdir -p /etc/tailscale /var/run/tailscale

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

stop_service() { /usr/bin/tailscale down 2>/dev/null || true; }
INITD

chmod +x /etc/init.d/tailscaled
/etc/init.d/tailscaled enable
/etc/init.d/tailscaled restart
sleep 3
pgrep tailscaled >/dev/null && echo 'tailscaled läuft ✓' || echo 'WARNUNG: tailscaled nicht gestartet'
"

    if [ -n "$authkey" ]; then
        local ts_args="--authkey $authkey --hostname gl-be10000-obd"
        [ "$TS_SUBNET" = "1" ] && ts_args="$ts_args --advertise-routes=$subnet_cidr"
        [ "$TS_EXIT_NODE" = "1" ] && ts_args="$ts_args --advertise-exit-node"
        ts_args="$ts_args --accept-routes --accept-dns=false"
        _ssh "tailscale up $ts_args 2>&1"
    else
        warn "Kein Auth-Key → manuelle Browser-Authentifizierung:"
        _ssh "tailscale up --hostname gl-be10000-obd 2>&1 | grep 'https://' || echo 'URL nicht gefunden'"
    fi

    _ssh "
uci -q del_list firewall.@zone[0].network='tailscale0' 2>/dev/null || true
uci add_list firewall.@zone[0].network='tailscale0' 2>/dev/null || true
uci commit firewall 2>/dev/null || true
/etc/init.d/firewall reload 2>/dev/null || true
echo 'Firewall: tailscale0 → lan'
TS_IP=\$(tailscale ip 2>/dev/null | head -1)
[ -n \"\$TS_IP\" ] && echo 'Tailscale IP: '\$TS_IP || echo '(noch keine IP)'
"
    ok "Tailscale eingerichtet auf GL-BE10000 [PROTOTYPE]"
}

echo ""
echo -e "${B}${C}╔══════════════════════════════════════════════════════╗"
echo -e "║  GL-BE10000 (Slate 7 Pro) VPN Setup — PROTOTYPE      ║"
echo -e "╚══════════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  Router: ${B}${SSH_HOST}${N}"
[ "$USE_TAILSCALE" = "1" ] && echo -e "  VPN:    ${B}Tailscale${N}" || echo -e "  VPN:    ${B}WireGuard${N}"
warn "PROTOTYPE — TODO: verify on hardware"
echo ""

if [ "$USE_TAILSCALE" = "1" ]; then
    _setup_tailscale
elif [ -n "$WG_CONF" ]; then
    _import_config
else
    err "Kein VPN-Modus. Optionen:
     --tailscale -t tskey-auth-xxx
     --tailscale -t tskey-auth-xxx --subnet
     -c ~/config.conf"
fi

echo ""
ok "VPN Setup abgeschlossen!"
if command -v qrcreds &>/dev/null && [ -n "${QR_PIN:-}" ]; then
    qrcreds generate ssh --host "$SSH_HOST" --user root --alias "gl-be10000" \
        --pin "$QR_PIN" --expires 60 2>/dev/null || true
fi
