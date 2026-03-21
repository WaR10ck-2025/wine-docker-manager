# TOPDON RLink-Serie — Nicht empfohlen für dieses Projekt

## Übersicht

Die **TOPDON RLink-Serie** (J2534, Lite, X7) sind professionelle Werkzeug-Interfaces
für KFZ-Werkstätten. Für dieses Home/Enthusiast-Projekt sind sie nicht geeignet.

> **Kurzfazit:** Teuer, Windows-only, kein Linux-Support.
> → Für J2534: **GODIAG GD101** (~€30–60) statt RLink J2534 (~€400–600)
> → Für WiFi+J2534+Linux: **WiCAN Pro** (~€50–80) statt RLink Lite (~€800–1200)

---

## Variantenvergleich

| Merkmal | RLink J2534 | RLink Lite | RLink X7 |
|---|---|---|---|
| Formfaktor | USB-Adapter | Standalone-Gerät (5" LCD, Android OS) | USB-C-Adapter |
| Chipset | TOPDON proprietär | 4-Core ARM 1.8 GHz (Android) | TOPDON + CAN-FD |
| Protokoll | J2534, D-PDU, DoIP, CAN-FD | J2534, D-PDU, DoIP | J2534, D-PDU, DoIP, CAN-FD (3 Kanäle) |
| Verbindung | USB 2.0 | USB + WiFi + Ethernet | USB-C |
| Linux-Treiber | ❌ Windows 7/8/10/11 (64-bit) | ❌ Eigenes Android-OS | ❌ Windows only |
| python-OBD | ❌ | ❌ | ❌ |
| Volvo VIDA | ⚠️ Unbestätigt | ⚠️ Unbestätigt | ⚠️ Unbestätigt |
| USB/IP (Pfad A) | ✅ technisch | ❌ kein USB-Export | ✅ technisch |
| Nützlich in Pfad A | ❌ kein Treiber auf Server | ❌ | ❌ kein Treiber |
| Marken | 13+ (TOPDON-Liste) | 17+ | 18+ |
| Zielgruppe | KFZ-Werkstatt | KFZ-Werkstatt | KFZ-Werkstatt |
| Preis | ~€400–600 | ~€800–1200 | ~€600–900 |

---

## Warum nicht geeignet

### 1. Preis vs. Nutzen

| Funktion | TOPDON RLink J2534 | Alternative |
|---|---|---|
| Standard OBD2 + Linux | ~€400–600 | CDP+ ~€50–150 |
| Volvo Tiefdiagnose (J2534) | ~€400–600 | GD101 ~€30–60 |
| WiFi + J2534 + Linux | RLink Lite ~€800–1200 | WiCAN Pro ~€50–80 |

### 2. Kein Linux-Support

Alle RLink-Varianten benötigen Windows-Treiber (TOPDON RLink Platform Software).
Unter Linux kein Treiber verfügbar → USB/IP-Passthrough nutzlos ohne Windows-VM.

### 3. RLink Lite — kein USB-Adapter

Das RLink Lite ist ein **eigenständiger Diagnose-Computer** mit Android OS,
5-Zoll-Touchscreen und eingebautem WiFi. Es ist kein USB-Adapter der in den
Router gesteckt werden kann.

### 4. Keine bestätigte Volvo-Kompatibilität

TOPDON fokussiert auf VAG, Ford, Nissan, BMW, Mercedes, Porsche.
Volvo VIDA 2014D / vdash: **nicht dokumentiert**, kein Volvo-spezifischer Treiber.

---

## Falls TOPDON RLink bereits vorhanden

Wenn ein RLink J2534 oder X7 bereits vorhanden ist:
- Als **Windows-J2534-Interface** nutzbar (Werkstatt-Software)
- Via **USB/IP (Pfad A)** → Windows-VM → TOPDON RLink Platform Software
- **Nicht** für python-obd, FastAPI-Service oder Linux-native Diagnose

**VID:PID** ist nicht öffentlich dokumentiert — per `lsusb` ermitteln:
```bash
# Auf GL.iNet Router nach Anschluss
lsusb | grep -v "Linux"
# → TOPDON-Gerät erscheint mit unbekanntem VID:PID
```

---

## Empfohlene Alternativen

| Anwendungsfall | Empfehlung | Preis |
|---|---|---|
| J2534 für Volvo VIDA | GODIAG GD101 | ~€30–60 |
| WiFi + J2534 + Linux | WiCAN Pro | ~€50–80 |
| Multi-Brand OBD2 | Autocom CDP+ | ~€50–150 |
| Open Hardware J2534 | Macchina M2/A0 | ~€100–150 |
