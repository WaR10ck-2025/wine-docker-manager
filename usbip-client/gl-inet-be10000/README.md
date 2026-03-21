# GL.iNet GL-BE10000 (Slate 7 Pro) — OBD2 USB/IP Setup

> ⚠️ **PROTOTYPE-STATUS**: Der GL-BE10000 befindet sich noch in der Prototyp-Phase.
> Technische Daten sind vorläufig. Hardware noch nicht allgemein verfügbar.
> Alle Konfigurationswerte sind als Platzhalter markiert und müssen auf echter
> Hardware verifiziert werden.

---

## Hardware (vorläufig — TODO: verify on hardware)

| Eigenschaft       | Wert                                |
|-------------------|-------------------------------------|
| Modell            | GL-BE10000 (Slate 7 Pro)            |
| SoC               | Qualcomm (TBD — Prototype)          |
| CPU               | TBD                                 |
| RAM               | TBD                                 |
| Flash / Storage   | TBD (eMMC oder NAND?)               |
| USB               | TBD                                 |
| Display           | 2.8" Touchscreen (320×240 Querformat)|
| WiFi              | WiFi 7 BE10000 (tri-band)           |
| Akku              | ❌ Kein Akku                        |
| 5G Modem          | TBD (wahrscheinlich kein integriertes 5G) |
| Ethernet          | TBD                                 |
| OpenWrt           | GL.iNet OpenWrt (Version TBD)       |
| Python-Speicher   | eMMC (venv — USB-Stick als Fallback)|

### Vergleich mit anderen Modellen

| Merkmal            | GL-BE3600 (Slate 7) | GL-E5800 (Mudi 7) | GL-BE10000 (Slate 7 Pro) |
|--------------------|---------------------|-------------------|--------------------------|
| Display            | 76×284px Hochformat | Touchscreen TBD   | 2.8" 320×240 Querformat  |
| Akku               | ❌                  | ✅ 5380 mAh       | ❌                       |
| 5G Modem           | ❌                  | ✅                | ❌ (wahrsch.)            |
| Flash              | 512 MB NAND         | 8 GB eMMC         | TBD                      |
| WiFi               | BE3600              | BE + 5G           | BE10000                  |
| Python-Speicher    | USB-Stick nötig     | eMMC direkt       | eMMC (erwartet)          |
| Status             | ✅ Verfügbar        | 🛒 Kaufbar        | 🔬 Prototype             |

---

## Unterschiede zu GL-E5800 (Mudi 7)

1. **Kein Akku** — stationäres Gerät, kein Batteriestatus
2. **2.8" Display (320×240)** — Querformat, größere Fläche für Daten
3. **Kein 5G Modem** — nur WiFi + Ethernet als WAN
4. **Prototype-Hardware** — Konfigurationen mit `# TODO: verify on hardware` markiert

---

## Schnell-Setup

### Voraussetzungen
- GL-BE10000 im Netzwerk erreichbar unter `192.168.10.191` (Ethernet) oder `192.168.10.196` (WiFi)
- SSH-Zugang als root

### Phase 1: OBD2 Service installieren
```bash
# Von lokalem PC aus:
./ssh-manager.sh -h 192.168.10.196 setup

# Oder manuell:
scp install_obd_openwrt.sh root@192.168.10.196:/tmp/
ssh root@192.168.10.196 "sh /tmp/install_obd_openwrt.sh"
```

### Phase 2: Display-Service (2.8" 320×240)
```bash
# Display-Auflösung aus Framebuffer lesen (TODO: verify on hardware)
ssh root@192.168.10.196 "cat /sys/class/graphics/fb0/virtual_size"
# Erwartet: 320,240

# Display-Service installieren
scp -r obd-display/ root@192.168.10.196:/opt/obd-display/
ssh root@192.168.10.196 "sh /opt/obd-display/install_display.sh"
```

### Phase 3: USB/IP Kernel-Module
```bash
# Nach SDK-Build (sdk-build/build_usbip_modules.sh):
opkg install /tmp/kmod-usbip_*.ipk /tmp/kmod-usbip-host_*.ipk

# USB/IP Service starten
cp usbipd-openwrt /etc/init.d/usbipd
chmod +x /etc/init.d/usbipd
/etc/init.d/usbipd enable && /etc/init.d/usbipd start
```

### Phase 4: Netzwerk konfigurieren
```bash
# Netzwerk-Konfiguration übertragen
scp network-config/network   root@192.168.10.196:/etc/config/network
scp network-config/wireless  root@192.168.10.196:/etc/config/wireless

# WiFi-Passwort setzen (YOUR_WIFI_PASSWORD ersetzen)
ssh root@192.168.10.196 "uci set wireless.wifinet_sta.key='DEIN_WLAN_PASSWORT'; uci commit wireless; wifi reload"
```

---

## Display-Konfiguration (2.8" 320×240)

Das GL-BE10000 hat ein 2.8" Display im **Querformat** (320×240 Pixel).
Größeres horizontales Display als BE3600 → mehr Platz für Messwerte.

```bash
# Auflösung prüfen (TODO: verify on hardware)
cat /sys/class/graphics/fb0/virtual_size
# Erwartet: 320,240

# Display-Service manuell mit Auflösung testen
FB_WIDTH=320 FB_HEIGHT=240 /opt/obd-venv/bin/python3 display_service.py
```

ENV-Override falls Auflösung abweicht:
```bash
# In /etc/init.d/obd-display einfügen:
procd_set_param env FB_WIDTH=320 FB_HEIGHT=240
```

---

## Netzwerk

```
GL-BE10000 (Slate 7 Pro)
├── br-lan (LAN)  : 192.168.10.191/24  (Ethernet-Bridge)
├── wwan (WiFi-STA): 192.168.10.196/24  (WiFi-Client zum AP)
└── wan  (eth0)   : DHCP               (falls direkte Ethernet-WAN-Verbindung)
```

Standard-Gateway: `192.168.10.1`

---

## Adapter-Auswahl

Der USB-Adapter wird via `/etc/obd-adapter.conf` konfiguriert:
```bash
# Standard: Autocom CDP+ (FTDI 0403:d6da)
cp ../adapters/autocom-cdp-plus/adapter.conf /etc/obd-adapter.conf

# Volvo Tiefdiagnose: GODIAG GD101 J2534
cp ../adapters/godiag-gd101/adapter.conf /etc/obd-adapter.conf

/etc/init.d/usbipd restart
```

---

## Verifikation

```bash
# OBD2 Service
curl http://192.168.10.196:8765/obd/status

# Display ENV-Override testen
ssh root@192.168.10.196 "FB_WIDTH=320 FB_HEIGHT=240 /opt/obd-venv/bin/python3 /opt/obd-display/display_service.py --test"

# venv-Pakete
ssh root@192.168.10.196 "/opt/obd-venv/bin/python3 -c 'import fastapi; print(fastapi.__version__)'"

# Adapter-Status
ssh root@192.168.10.196 "obd-ctl adapter"
```

---

## Bekannte Einschränkungen (Prototype)

- Display-Auflösung nicht amtlich dokumentiert → `FB_WIDTH=320 FB_HEIGHT=240` als Annahme
- SDK-Build-Profil unbekannt → `GL_SDK_PROFILE` ENV-Variable setzen wenn bekannt
- Kein 5G Modem → `obd-ctl modem` nicht verfügbar
- Kein Akku → kein Batteriestatus im Display

> Sobald Hardware verfügbar: `# TODO: verify on hardware` Kommentare prüfen und entfernen.
