# Vgate iCar 2 WiFi — Setup Guide (Router-Bridge + python-obd)

## Schritt 1: iCar 2 in Router-WiFi einbuchen

### Via Vgate App (einfachster Weg)

1. Vgate Pro App installieren (Android/iOS)
2. Mit `V-LINK` SSID verbinden (kein Passwort)
3. App öffnen → Settings → WiFi
4. SSID: `GL-BE3600-AP` (oder eigene Router-SSID)
5. Passwort: <Router-WLAN-Passwort>
6. Save → iCar 2 verbindet sich neu

### Via Web-UI (falls vorhanden)

```
Browser → http://192.168.0.10 (während mit V-LINK verbunden)
WiFi → Mode: Station → SSID + Passwort
```

---

## Schritt 2: DHCP-Reservation (feste IP)

```bash
# Auf GL.iNet Router
ssh root@192.168.10.194

# iCar 2 MAC ermitteln
cat /tmp/dhcp.leases | grep -v wican
# → Neue Zeile nach iCar-Verbindung = iCar 2

# Reservation setzen
uci add dhcp host
uci set dhcp.@host[-1].mac='<iCar2-MAC-hier>'
uci set dhcp.@host[-1].ip='192.168.10.201'
uci set dhcp.@host[-1].name='vgate-icar2'
uci commit dhcp
/etc/init.d/dnsmasq restart

# Test
ping 192.168.10.201
```

---

## Schritt 3: python-obd installieren

```bash
# Auf Umbrel-Server oder lokalem Linux-PC
pip install obd

# Verbindungstest
python3 << 'EOF'
import obd

conn = obd.OBD("192.168.10.201", portstr="35000", timeout=10)
print("Status:", conn.status())

if conn.status() == obd.OBDStatus.CAR_CONNECTED:
    print("✓ Fahrzeug verbunden!")
    # Schnelltest
    rpm = conn.query(obd.commands.RPM)
    coolant = conn.query(obd.commands.COOLANT_TEMP)
    print(f"Drehzahl: {rpm.value}")
    print(f"Kühlwasser: {coolant.value}")
else:
    print("✗ Fahrzeug nicht erkannt. Protokoll prüfen.")
    print("  Verfügbare Protokolle:", [p.value for p in obd.protocols])

conn.close()
EOF
```

---

## Schritt 4: FastAPI-Service konfigurieren (optional)

Der bestehende `obd_service.py` nutzt standardmäßig seriellen Port.
Für WiFi-Adapter Verbindungstyp anpassen:

```bash
# Auf dem GL.iNet Router (Pfad A) ODER im Docker-Container:
# OBD_PORT=192.168.10.201 setzen + Protokoll auf TCP umstellen

# docker-compose.yml (Umbrel):
# OBD_MONITOR_HOST: "192.168.10.201"
# OBD_MONITOR_PORT: "35000"
# OBD_ADAPTER_TYPE: "wifi"   # falls implementiert
```

> **Hinweis:** Der aktuelle `obd_service.py` nutzt pyserial (seriell).
> Für WiFi-Adapter muss die Verbindungslogik auf TCP umgestellt werden.
> WiCAN Pro über SocketCAN ist nativ besser integriert.

---

## Auto-Reconnect (Hintergrund-Service)

```python
# obd_wifi_monitor.py — Einfacher WiFi-OBD2-Service
import obd
import time

ADAPTER_HOST = "192.168.10.201"
ADAPTER_PORT = 35000
RECONNECT_DELAY = 10

def connect():
    while True:
        try:
            conn = obd.OBD(ADAPTER_HOST, portstr=str(ADAPTER_PORT), timeout=10)
            if conn.status() != obd.OBDStatus.NOT_CONNECTED:
                return conn
        except Exception as e:
            print(f"Verbindung fehlgeschlagen: {e}")
        print(f"Reconnect in {RECONNECT_DELAY}s...")
        time.sleep(RECONNECT_DELAY)

conn = connect()
while True:
    if not conn.is_connected():
        conn = connect()
    rpm = conn.query(obd.commands.RPM)
    print(f"RPM: {rpm.value}")
    time.sleep(1)
```

---

## Troubleshooting

| Problem | Lösung |
|---|---|
| `Connection refused` auf Port 35000 | iCar 2 im AP-Mode? → STA-Mode konfigurieren |
| `No OBD data` | Zündung AN? OBD2-Port aktiv? |
| Protokoll falsch erkannt | `protocol=obd.protocols.ISO_9141_2` für Suzuki Wagon R+ 2004 |
| iCar 2 nicht im Router | App → WiFi-Einstellungen prüfen, SSID korrekt? |
| IP wechselt nach Neustart | DHCP-Reservation auf Router setzen |
