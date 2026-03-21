# Vgate iCar 2 WiFi — Günstig + Kabellos (ELM327, Pfad B)

## Übersicht

Der **Vgate iCar 2 WiFi** ist ein günstiger ELM327-basierter OBD2-Adapter
der sich direkt in den OBD2-Port steckt und ein eigenes WiFi-AP aufbaut.

| Eigenschaft | Wert |
|---|---|
| Chipset | ARM + LPT230 WiFi + ELM327 V2.x |
| Verbindung | WiFi 2.4G (AP-Mode oder STA-Mode) |
| Protokoll | **ELM327** (ISO 9141, ISO 14230, CAN, J1850 PWM/VPW) |
| **J2534** | ❌ Nicht unterstützt |
| Linux-Treiber | ✅ Via TCP-Socket (kein Treiber nötig) |
| python-obd | ✅ Via TCP (Port 35000) |
| Volvo VIDA/vdash | ❌ ELM327 ≠ J2534 |
| Volvo Tiefdiagnose | ❌ Nur Standard OBD2 |
| USB/IP nötig | ❌ WiFi-Bridge-Pfad |
| Preis | ~€20–40 |

> **Wichtig:** Der Vgate iCar 2 WiFi unterstützt **kein J2534**.
> Für WiFi + J2534 + Linux → **WiCAN Pro** verwenden.

---

## Architektur: Pfad B — WiFi-Bridge

```
[Pfad B: Vgate iCar 2 WiFi]
Auto → iCar 2 (OBD2) → Router (WiFi AP + Bridge) → [LAN] → Server
                                                              ↓
                                              python-obd via TCP-Socket
                                              Port 35000 (ELM327)
```

Router-seitig: **Kein Setup nötig** — iCar 2 verbindet sich ins Router-WiFi,
bekommt DHCP-IP, ist sofort per TCP erreichbar.

---

## Voraussetzungen

- Vgate iCar 2 WiFi (Modell für WiFi — nicht Bluetooth-Version)
- GL.iNet Router mit WLAN-AP (Standard-Config)
- python-obd auf Server: `pip install obd`

---

## Setup

### Option A — iCar 2 verbindet sich in Router-WiFi (empfohlen)

**Im Vgate-Konfigurations-Tool (Android/iOS App) oder Web-UI:**
```
WiFi-Mode: Station (STA)
SSID: GL-BE3600-AP
Password: <Router-Passwort>
```

Nach Verbindung: iCar 2 bekommt DHCP-IP vom Router (z.B. 192.168.10.201).
DHCP-Reservation empfohlen → [../wican-pro/router-bridge-setup.md](../wican-pro/router-bridge-setup.md)

**Feste IP setzen:**
```bash
ssh root@192.168.10.194 "
uci add dhcp host
uci set dhcp.@host[-1].mac='<iCar2-MAC>'
uci set dhcp.@host[-1].ip='192.168.10.201'
uci set dhcp.@host[-1].name='vgate-icar2'
uci commit dhcp && /etc/init.d/dnsmasq restart
"
```

### Option B — Direkt mit iCar 2 AP verbinden (ohne Router)

```
iCar 2 erstellt eigenes SSID: V-LINK
Standard-IP: 192.168.0.10
Port: 35000
```

Server verbindet sich direkt mit V-LINK SSID — Router dann nicht im Pfad.

---

## python-obd Verbindung

```python
import obd

# Via Router (empfohlen, feste IP nach DHCP-Reservation)
conn = obd.OBD("192.168.10.201", portstr="35000")

# ODER direkt (Option B, ohne Router)
conn = obd.OBD("192.168.0.10", portstr="35000")

print(conn.status())

# Kühlwasser-Temperatur
cmd = obd.commands.COOLANT_TEMP
response = conn.query(cmd)
print(f"Kühlwasser: {response.value}")

# Drehzahl
rpm = conn.query(obd.commands.RPM)
print(f"Drehzahl: {rpm.value}")
```

---

## ELM327 vs. J2534 — Einschränkungen

| Feature | iCar 2 (ELM327) | WiCAN Pro (J2534/SocketCAN) |
|---|---|---|
| Standard OBD2 PIDs | ✅ | ✅ |
| DTC auslesen | ✅ | ✅ |
| Live-Daten | ✅ | ✅ |
| Hersteller-spezifische PIDs | ⚠️ Begrenzt | ✅ |
| UDS-Diagnose | ❌ | ✅ |
| Volvo Tiefdiagnose | ❌ | ⚠️ UDS |
| ECU-Flashen | ❌ | ❌ |
| Preis | €20–40 | €50–80 |

**Fazit:** Für Standard-OBD2 (Fehlercodes, Live-Daten) ist der iCar 2 ausreichend
und deutlich günstiger. Für Tiefdiagnose oder UDS → WiCAN Pro.

---

## Typische Use-Cases für iCar 2

- ✅ Fehlercodes auslesen (alle OBD2-Fahrzeuge)
- ✅ Live-Sensordaten (Temperatur, Drehzahl, O2-Sonden)
- ✅ Kraftstoffverbrauch berechnen
- ✅ Fahrzeug-Diagnose ohne Laptop (Handy-App)
- ❌ Volvo-Steuergeräte-Coding
- ❌ VIDA / vdash

---

## Troubleshooting

### Verbindung fehlgeschlagen
```python
# Timeout erhöhen
conn = obd.OBD("192.168.10.201", portstr="35000", timeout=10)
```

### Fahrzeug nicht erkannt
```python
# Protokoll manuell setzen (ISO 9141-2 für ältere Fahrzeuge wie Suzuki Wagon R+ 2004)
conn = obd.OBD("192.168.10.201", portstr="35000",
               protocol=obd.protocols.ISO_9141_2)
```

### iCar 2 nicht im Netz
```bash
# DHCP-Leases prüfen
ssh root@192.168.10.194 "cat /tmp/dhcp.leases"
# Falls nicht verbunden: Vgate App nutzen um STA-Mode zu konfigurieren
```
