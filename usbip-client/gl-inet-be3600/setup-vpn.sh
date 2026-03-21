#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# GL.iNet GL-BE3600 — VPN Setup (WireGuard + Tailscale)
#
# Richtet einen optionalen VPN-Tunnel auf dem Router ein.
# Zweck: Zugriff auf den GL-BE3600 und OBD2-Daten von außerhalb des Heimnetzes.
#
# Wird LOKAL ausgeführt und konfiguriert den Router via SSH.
# Voraussetzung: ssh-manager.sh Verbindung funktioniert.
#
# VERWENDUNG:
#   ./setup-vpn.sh [OPTIONEN]
#
# OPTIONEN:
#   -h HOST           Router-IP (Standard: 192.168.8.1)
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

SSH_HOST="192.168.8.1"
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

# SSH-Wrapper (gleiche Logik wie ssh-manager.sh)
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

# Existierendes Interface entfernen falls vorhanden
uci -q delete network.\$IFACE 2>/dev/null || true

# WireGuard Interface via UCI anlegen
uci set network.\$IFACE=interface
uci set network.\$IFACE.proto='wireguard'
uci set network.\$IFACE.private_key=\$(grep 'PrivateKey' \"\$CONF\" | awk '{print \$3}')

# Listen-Port falls vorhanden
LPORT=\$(grep 'ListenPort' \"\$CONF\" | awk '{print \$3}')
[ -n \"\$LPORT\" ] && uci set network.\$IFACE.listen_port=\"\$LPORT\"

# IP-Adresse des Interfaces
ADDR=\$(grep 'Address' \"\$CONF\" | awk '{print \$3}')
[ -n \"\$ADDR\" ] && uci set network.\$IFACE.addresses=\"\$ADDR\"

uci commit network

# Peer-Sektion aus Config extrahieren + als UCI Peer anlegen
# (vereinfacht — für komplexe Setups: wg-quick direkt nutzen)
PEER_KEY=\$(grep 'PublicKey' \"\$CONF\" | awk '{print \$3}')
ENDPOINT=\$(grep 'Endpoint' \"\$CONF\" | awk '{print \$3}')
ALLOWED=\$(grep 'AllowedIPs' \"\$CONF\" | awk '{print \$3}')
DNS_SRV=\$(grep 'DNS' \"\$CONF\" | awk '{print \$3}')

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
# WireGuard Interface in lan-Zone hinzufügen (Zugriff auf Router-Services)
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

# init.d Service anlegen
cat > /etc/init.d/vpn-\$IFACE << 'INITD'
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=97
STOP=5

start_service() {
    procd_open_instance
    procd_set_param command /sbin/ip link show ${IFACE} 2>/dev/null || \
                            wg-quick up ${CONF}
    procd_close_instance
}

stop_service() {
    wg-quick down ${CONF} 2>/dev/null || true
}
INITD

# Sauberer Start via wg-quick (verarbeitet auch DNS, Routes, PostUp/Down)
wg-quick up \"\$CONF\" 2>&1 || /etc/init.d/network restart
chmod +x /etc/init.d/vpn-\$IFACE
/etc/init.d/vpn-\$IFACE enable
echo 'VPN-Service aktiviert: vpn-\$IFACE'
"

    _show_vpn_status
}

# ── Modus: Server (Router als WireGuard-Server) ───────────────────────────────
_setup_server() {
    step "Router als WireGuard-Server konfigurieren"
    warn "In diesem Modus können sich externe Geräte mit dem Router verbinden."
    warn "Der Router teilt dann OBD2-Daten über das VPN."

    # Keys generieren
    step "WireGuard-Keys generieren"
    _ssh "
mkdir -p /etc/wireguard && chmod 700 /etc/wireguard
cd /etc/wireguard

if [ ! -f server_private.key ]; then
    # Keys generieren (wg oder openssl als Fallback)
    if command -v wg >/dev/null 2>&1; then
        wg genkey | tee server_private.key | wg pubkey > server_public.key
        echo 'Keys generiert via wg'
    else
        # Fallback: openssl (WireGuard-Keys sind 32-Byte Curve25519)
        openssl genpkey -algorithm X25519 -out /tmp/wg_private_raw.pem 2>/dev/null
        openssl pkey -in /tmp/wg_private_raw.pem -noout -text 2>/dev/null | \
            grep -A4 'private' | head -2 > server_private.key || \
            dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 > server_private.key
        echo 'Fallback-Keys generiert (wg-Pakete für korrekte Keys empfohlen)'
    fi
    chmod 600 server_private.key
fi

PRIV_KEY=\$(cat server_private.key)
PUB_KEY=\$(cat server_public.key 2>/dev/null || echo '(Public Key nicht verfügbar)')
echo ''
echo '=== WireGuard Server-Keys ==='
echo \"Private: \$PRIV_KEY\"
echo \"Public:  \$PUB_KEY\"
echo ''
echo 'Für Client-Config (VPN_SERVER_PUBLIC_KEY):'
echo \"\$PUB_KEY\"
"

    # Server-Config erstellen
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

# Clients hier hinzufügen:
# [Peer]
# PublicKey = <CLIENT_PUBLIC_KEY>
# AllowedIPs = 10.100.0.2/32
EOF

chmod 600 /etc/wireguard/wg-server.conf
echo 'Server-Config erstellt: /etc/wireguard/wg-server.conf'
echo ''
echo 'UDP-Port $wg_port muss in der Firewall geöffnet sein.'
"

    step "Firewall: UDP-Port $WG_PORT öffnen"
    _ssh "
# WireGuard UDP-Port öffnen
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

    info "Server-Config abgeschlossen."
    warn "Client-Konfiguration erstellen:"
    echo ""
    echo "  Beispiel-Client-Config (auf dem Client-Gerät speichern):"
    _ssh "
PUB=\$(cat /etc/wireguard/server_public.key 2>/dev/null || echo 'SERVER_PUBLIC_KEY')
WIFI=\$(ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1 || echo $SSH_HOST)
echo ''
echo '[Interface]'
echo 'Address = 10.100.0.2/24'
echo 'PrivateKey = <CLIENT_PRIVATE_KEY>'
echo 'DNS = 10.100.0.1'
echo ''
echo '[Peer]'
echo \"PublicKey = \$PUB\"
echo \"Endpoint = \$WIFI:$wg_port\"
echo 'AllowedIPs = 10.100.0.0/24, 192.168.10.0/24'
echo 'PersistentKeepalive = 25'
"
    _show_vpn_status
}

# ── Split-Tunnel konfigurieren ────────────────────────────────────────────────
_setup_split_tunnel() {
    if [ "$TUNNEL_MODE" != "split" ]; then return; fi
    step "Split-Tunnel: Nur OBD2-Traffic ($SSH_HOST:8765) über VPN"

    _ssh "
# Routen so setzen, dass nur OBD2-Host über VPN geroutet wird
# Alle anderen Routen bleiben auf normalem Interface
if command -v wg >/dev/null 2>&1; then
    WG_IFACE=\$(wg show interfaces 2>/dev/null | head -1)
    if [ -n \"\$WG_IFACE\" ]; then
        # OBD-Monitor-Host über VPN
        ip route add 192.168.10.0/24 dev \$WG_IFACE 2>/dev/null || true
        echo 'Split-Tunnel: 192.168.10.0/24 → \$WG_IFACE'
    fi
fi
"
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
echo 'Stop:     obd-ctl vpn stop'
echo 'SSH:      ./ssh-manager.sh -h <vpn-ip> status'
"
}

# ── Modus: Tailscale ─────────────────────────────────────────────────────────
_setup_tailscale() {
    local authkey="$TS_AUTHKEY"
    local subnet_flag="$TS_SUBNET"
    local exit_flag="$TS_EXIT_NODE"
    local subnet_cidr="192.168.10.0/24"   # Heimnetz hinter dem Router

    step "Tailscale Installation auf GL-BE3600"

    # 1. Tailscale installieren
    _ssh "
echo '=== Prüfe Tailscale-Installation ==='
if command -v tailscale >/dev/null 2>&1; then
    echo 'Tailscale bereits installiert: '\$(tailscale version 2>/dev/null | head -1)
else
    echo 'Installiere Tailscale...'

    # Methode 1: GL.iNet opkg-Repo (falls verfügbar)
    if opkg list 2>/dev/null | grep -q '^tailscale '; then
        opkg install tailscale tailscaled && echo 'Tailscale via opkg installiert'

    # Methode 2: Offizielles ARM64-Binary (zuverlässiger)
    else
        echo 'Lade offizielles Tailscale ARM64-Binary...'
        TS_VERSION=\$(curl -s https://pkgs.tailscale.com/stable/?mode=json 2>/dev/null | \
            python3 -c \"import sys,json; d=json.load(sys.stdin); print(d['Tarballs']['arm64'])\" 2>/dev/null || \
            echo 'tailscale_1.78.0_arm64.tgz')

        # Tarball herunterladen
        curl -L \"https://pkgs.tailscale.com/stable/\$TS_VERSION\" -o /tmp/tailscale.tgz
        tar xzf /tmp/tailscale.tgz -C /tmp/
        TS_DIR=\$(ls -d /tmp/tailscale_* 2>/dev/null | head -1)

        # Binaries installieren
        install -m 755 \"\$TS_DIR/tailscale\"  /usr/bin/tailscale
        install -m 755 \"\$TS_DIR/tailscaled\" /usr/sbin/tailscaled
        rm -rf /tmp/tailscale* || true
        echo 'Tailscale '\$(tailscale version | head -1)' installiert'
    fi
fi
"

    # 2. TUN-Device sicherstellen
    _ssh "
# TUN-Interface für Tailscale (OpenWrt braucht explizit tun-Modul)
modprobe tun 2>/dev/null || insmod /lib/modules/\$(uname -r)/tun.ko 2>/dev/null || true
ls /dev/net/tun 2>/dev/null || { mkdir -p /dev/net; mknod /dev/net/tun c 10 200; chmod 666 /dev/net/tun; }
echo 'TUN-Device: '\$(ls -la /dev/net/tun)
"

    # 3. tailscaled als Service einrichten
    step "tailscaled Daemon einrichten"
    _ssh "
# Zustandsverzeichnis
mkdir -p /etc/tailscale

# init.d Service (procd) anlegen
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

# Daemon starten
/etc/init.d/tailscaled enable
/etc/init.d/tailscaled restart
sleep 3

# Prüfen ob tailscaled läuft
if pgrep tailscaled >/dev/null 2>&1; then
    echo 'tailscaled läuft ✓'
else
    echo 'WARNUNG: tailscaled nicht gestartet — prüfe: logread | grep tailscale'
fi
"

    # 4. Tailscale authentifizieren
    step "Tailscale authentifizieren"
    if [ -n "$authkey" ]; then
        info "Authentifiziere mit Auth-Key..."
        local ts_args="--authkey $authkey --hostname gl-be3600-obd"
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
        warn "Manuell authentifizieren:"
        echo ""
        _ssh "
echo 'Authentifizierungs-URL:'
tailscale up --hostname gl-be3600-obd 2>&1 | grep 'https://' || \
    echo 'tailscale up ausführen und URL im Browser öffnen'
"
        echo ""
        warn "Nach der Browser-Authentifizierung:"
        warn "  ./ssh-manager.sh run 'tailscale status'"
    fi

    # 5. Subnet Routing aktivieren (falls gewählt)
    if [ "$subnet_flag" = "1" ]; then
        step "Subnet Routing: $subnet_cidr exponieren"
        _ssh "
# IP-Forwarding aktivieren
echo 1 > /proc/sys/net/ipv4/ip_forward
uci set network.globals.packet_steering='1' 2>/dev/null || true

# Masquerade für Tailscale-Clients die ins Heimnetz wollen
iptables -t nat -A POSTROUTING -s 100.64.0.0/10 -d $subnet_cidr -j MASQUERADE 2>/dev/null || true

echo 'Subnet-Routing konfiguriert: $subnet_cidr'
echo 'WICHTIG: Im Tailscale Admin-Panel Routes bestätigen:'
echo '  https://login.tailscale.com/admin/machines'
echo '  → Maschine gl-be3600-obd → Edit route settings → Route aktivieren'
"
    fi

    # 6. Firewall: Tailscale Interface erlauben
    step "Firewall für Tailscale konfigurieren"
    _ssh "
# tailscale0 in lan-Zone aufnehmen (Zugriff auf OBD-API + SSH)
uci -q del_list firewall.@zone[0].network='tailscale0' 2>/dev/null || true
uci add_list firewall.@zone[0].network='tailscale0' 2>/dev/null || true
uci commit firewall 2>/dev/null || true
/etc/init.d/firewall reload 2>/dev/null || true
echo 'Firewall: tailscale0 → lan'
"

    # 7. Zusammenfassung
    step "Tailscale Status"
    _ssh "
echo ''
echo '=== Tailscale Status ==='
tailscale status 2>/dev/null || echo '(warte auf Authentifizierung)'
echo ''
echo '=== Tailscale IP ==='
TS_IP=\$(tailscale ip 2>/dev/null | head -1)
echo \"\${TS_IP:-(noch nicht zugewiesen)}\"
echo ''
[ -n \"\$TS_IP\" ] && echo 'SSH via Tailscale: ssh root@'\$TS_IP || true
[ -n \"\$TS_IP\" ] && echo 'OBD-API via Tailscale: curl http://'\$TS_IP':8765/obd/status' || true
"

    echo ""
    ok "Tailscale eingerichtet!"
    echo ""
    echo -e "  Nächste Schritte:"
    if [ -z "$authkey" ]; then
        echo -e "  1. ${Y}Tailscale-URL im Browser öffnen und einloggen${N}"
        echo -e "  2. ./ssh-manager.sh run 'tailscale status'"
    fi
    if [ "$subnet_flag" = "1" ]; then
        echo -e "  ${Y}WICHTIG:${N} Routes im Tailscale Admin-Panel bestätigen:"
        echo -e "  → https://login.tailscale.com/admin/machines"
        echo -e "  → gl-be3600-obd → Edit route settings → ${subnet_cidr} aktivieren"
    fi
    echo ""
    echo -e "  Danach erreichbar:"
    echo -e "  ${B}ssh root@<tailscale-ip>                       ${N}(SSH via Tailnet)"
    echo -e "  ${B}./ssh-manager.sh -h <tailscale-ip> status     ${N}(SSH-Manager via Tailnet)"
    echo -e "  ${B}curl http://<tailscale-ip>:8765/obd/status    ${N}(OBD-API via Tailnet)"
    [ "$subnet_flag" = "1" ] && \
    echo -e "  ${B}http://192.168.10.147:<port>                  ${N}(Umbrel via Subnet-Route)"
    echo ""
}

# ── Haupt ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${B}${C}╔══════════════════════════════════════════════════════╗"
echo -e "║  GL-BE3600 WireGuard VPN Setup                       ║"
echo -e "╚══════════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  Router:       ${B}${SSH_HOST}${N}"
if [ "$USE_TAILSCALE" = "1" ]; then
    echo -e "  VPN:          ${B}Tailscale${N}"
    [ -n "$TS_AUTHKEY" ] && echo -e "  Auth-Key:     ${B}${TS_AUTHKEY:0:20}…${N}" || echo -e "  Auth-Key:     ${Y}nicht angegeben (Browser-Login)${N}"
    [ "$TS_SUBNET" = "1" ] && echo -e "  Subnet:       ${B}192.168.10.0/24 wird exponiert${N}"
    [ "$TS_EXIT_NODE" = "1" ] && echo -e "  Exit-Node:    ${B}Ja${N}"
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

     Tailscale (empfohlen — kein eigener Server nötig):
       --tailscale -t tskey-auth-xxx
       --tailscale -t tskey-auth-xxx --subnet   (Heimnetz exponieren)

     WireGuard (bestehende Config):
       -c ~/meine-config.conf

     WireGuard (Router als Server):
       --server

     Hilfe anzeigen:
       ./setup-vpn.sh --help"
fi

echo ""
echo -e "${G}${B}VPN Setup abgeschlossen!${N}"
echo ""
echo -e "Steuerung via ssh-manager.sh:"
echo -e "  ${B}./ssh-manager.sh -h $SSH_HOST run 'obd-ctl vpn status'${N}"
echo ""

# ── QR-Code (WireGuard Config) ────────────────────────────────────────────────
# Wenn WireGuard Config importiert wurde, QR-Code für WireGuard App generieren
if command -v qrcreds &>/dev/null && [ -n "$WG_CONF" ] && [ -f "$WG_CONF" ]; then
    echo ""
    echo -e "${G}${B}═══ WireGuard QR-Code (WireGuard App scannen) ═══${N}"
    qrcreds generate wireguard --config "$WG_CONF" 2>/dev/null || true
fi
# SSH-QR für GL-BE3600 (wenn QR_PIN gesetzt)
if command -v qrcreds &>/dev/null && [ -n "${QR_PIN:-}" ]; then
    echo ""
    echo -e "${G}${B}═══ SSH-Zugang GL-BE3600 per QR ═══${N}"
    qrcreds generate ssh \
        --host "$SSH_HOST" --user root \
        --alias "gl-be3600" \
        --pin "$QR_PIN" --expires 60 2>/dev/null || true
    echo -e "  PIN: ${QR_PIN}  |  Termius App → QR scannen"
fi
