# GL.iNet Router als WiFi-Bridge — WiCAN Pro Setup

## Konzept

Der GL.iNet Router fungiert als **transparenter WiFi-Bridge**:
- WiCAN Pro verbindet sich mit dem Router-WiFi (SSID)
- Router bridget den WiFi-Client automatisch ins LAN (`br-lan`)
- Server (Umbrel, 192.168.10.147) greift direkt per TCP/SocketCAN auf WiCAN Pro zu

```
WiCAN Pro (192.168.10.200)
       │ WiFi
       ▼
GL.iNet Router (AP + Bridge)
       │ LAN (br-lan)
       ▼
Umbrel-Server (192.168.10.147)
  → python-can via SocketCAN TCP → 192.168.10.200:3333
```

Keine Treiber, kein USB/IP, kein usbipd auf dem Router nötig.

---

## Schritt 1: WiCAN Pro Firmware konfigurieren

### 1a. WiCAN im AP-Mode öffnen (Ersteinrichtung)

```
WiCAN Pro einschalten → steckt im OBD2-Port oder Netzteil
SSID: WiCAN_XXXXXX (steht auf dem Gerät)
Verbinden mit: WiCAN_XXXXXX (kein Passwort)
Browser öffnen: http://192.168.80.1
```

### 1b. WiFi-Modus auf Station umstellen

```
Settings → WiFi
  Mode: Station
  SSID: <Router-SSID> (z.B. "GL-BE3600-AP" oder eigene SSID)
  Password: <Router-WLAN-Passwort>
Save
```

### 1c. SocketCAN-Modus aktivieren

```
Settings → Protocol
  Protocol: SocketCAN
  Port: 3333
  Bitrate: 500000 (Standard CAN-Bus)
Save → Reboot
```

Nach dem Reboot verbindet WiCAN Pro sich mit dem Router-WiFi und
erscheint im DHCP-Log des Routers.

---

## Schritt 2: DHCP-Reservation auf Router (feste IP)

```bash
# SSH auf Router
ssh root@192.168.10.194

# WiCAN MAC-Adresse ermitteln
cat /tmp/dhcp.leases
# → Zeile mit "wican" oder unbekanntem Gerät → MAC kopieren

# DHCP-Reservation erstellen (MAC anpassen!)
uci add dhcp host
uci set dhcp.@host[-1].mac='AA:BB:CC:DD:EE:FF'  # WiCAN MAC hier eintragen
uci set dhcp.@host[-1].ip='192.168.10.200'
uci set dhcp.@host[-1].name='wican-pro'
uci commit dhcp
/etc/init.d/dnsmasq restart
```

**Verifikation:**
```bash
ping 192.168.10.200          # WiCAN Pro erreichbar?
curl http://192.168.10.200   # WiCAN Web-UI erreichbar?
```

---

## Schritt 3: Zweites SSID für OBD-Geräte (optional, empfohlen)

Ein dediziertes SSID für OBD2-Adapter verhindert Konflikte mit anderen WiFi-Clients:

```bash
# SSH auf Router
ssh root@192.168.10.194

# Zweites SSID auf radio0 (2.4 GHz) anlegen
uci set wireless.obd_ap=wifi-iface
uci set wireless.obd_ap.device='radio0'
uci set wireless.obd_ap.mode='ap'
uci set wireless.obd_ap.ssid='OBD-Bridge'
uci set wireless.obd_ap.encryption='psk2'
uci set wireless.obd_ap.key='obd-secret-pw'
uci set wireless.obd_ap.network='lan'    # Ins LAN bridgen
uci set wireless.obd_ap.disabled='0'
uci commit wireless
wifi reload
```

Dann im WiCAN Pro Web-UI:
```
WiFi SSID: OBD-Bridge
Password: obd-secret-pw
```

---

## Schritt 4: Firewall (nur falls nötig)

GL.iNet im Standard-Modus erlaubt LAN-intern allen Traffic.
Falls Firewall-Regeln aktiviert sind:

```bash
# Port 3333 (SocketCAN) von LAN zu WiCAN freigeben
uci add firewall rule
uci set firewall.@rule[-1].name='wican-socketcan'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].dest_ip='192.168.10.200'
uci set firewall.@rule[-1].dest_port='3333'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall
/etc/init.d/firewall reload
```

---

## Schritt 5: Server-seitig verbinden (Umbrel)

### Linux SocketCAN via TCP (empfohlen)

```bash
# can-utils + python-can installieren
sudo apt-get install can-utils python3-pip
pip3 install python-can can-isotp udsoncan

# SocketCAN Netzwerk-Interface anlegen (WiCAN Pro TCP-Bridge)
# WiCAN Pro stellt TCP-SocketCAN auf Port 3333 bereit
sudo modprobe vcan
```

```python
# Verbindung testen (python-can)
import can

# WiCAN Pro unterstützt socketcand-Protokoll
bus = can.interface.Bus(
    interface='socketcand',
    channel='can0',
    host='192.168.10.200',
    port=3333
)

print("Warte auf CAN-Frame...")
msg = bus.recv(timeout=10.0)
if msg:
    print(f"Frame: ID={hex(msg.arbitration_id)} Data={msg.data.hex()}")
bus.shutdown()
```

### Alternative: slcan über USB (falls WiFi-Probleme)

WiCAN Pro hat auch einen USB-Anschluss. Über USB erscheint es als `/dev/ttyACM0`:

```bash
sudo slcan_attach -o -s6 -t hw -S 3000000 /dev/ttyACM0
sudo slcand -o -c -f -s6 /dev/ttyACM0 can0
sudo ip link set can0 up
candump can0
```

---

## Verifikation: Ende-zu-Ende Test

```bash
# 1. WiCAN Pro im Netz?
ping -c 3 192.168.10.200

# 2. SocketCAN erreichbar?
nc -zv 192.168.10.200 3333

# 3. OBD2-Anfrage senden (Mode 01 PID 0C = RPM)
cansend can0 7DF#02010C0000000000
candump can0 -n 1

# 4. python-can Schnelltest
python3 -c "
import can
bus = can.Bus(interface='socketcand', channel='can0', host='192.168.10.200', port=3333)
print('Bus OK:', bus.channel_info)
bus.shutdown()
"
```

---

## Für alle drei GL.iNet-Geräte

Diese Bridge-Konfiguration gilt für alle drei Router-Modelle:

| Router | SSH-IP | WiCAN DHCP-Range |
|---|---|---|
| GL-BE3600 | 192.168.10.194 | 192.168.10.200 |
| GL-E5800 | 192.168.10.195 | 192.168.10.200 |
| GL-BE10000 | 192.168.10.196 | 192.168.10.200 |

**Empfehlung:** Nur ein Router aktiv gleichzeitig → WiCAN behält IP .200.
