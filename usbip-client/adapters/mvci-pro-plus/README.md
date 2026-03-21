# Xhorse MVCI PRO+ — Bewertung für dieses Projekt

## Übersicht

Der **Xhorse MVCI PRO+ (XDMVJP)** ist ein J2534 Pass-Thru Adapter
für Multi-Marken-Diagnose.

| Eigenschaft         | Wert                                              |
|---------------------|---------------------------------------------------|
| USB VID:PID         | proprietär (Xhorse, variiert je Gerät)            |
| Protokoll           | J2534 + D-PDU API                                 |
| Linux-Treiber       | ❌ Windows-only                                   |
| python-obd          | ❌ Nicht möglich                                  |
| FastAPI OBD2        | ❌ Kein direkter Zugriff                          |
| Volvo VIDA          | ⚠️ **Nicht zuverlässig** (kein Volvo-Treiber)    |
| VAG ODIS            | ✅ Gut                                            |
| Toyota TIS          | ✅ Gut                                            |
| Subaru SSM4         | ✅ Gut                                            |
| Honda HDS           | ✅ Gut                                            |
| USB/IP-fähig        | ✅ Möglich                                        |

## Bewertung für dieses Projekt

### Geeignet für
- ✅ Multi-Brand OBD2 (Standard-Funktionen)
- ✅ VAG ODIS, Toyota TIS, Subaru SSM4 via Windows-VM
- ✅ USB/IP-Forwarding → Windows-PC
- ✅ **Nützlich als zweiter Adapter** für Nicht-Volvo-Fahrzeuge

### Nicht optimal für
- ❌ Volvo VIDA 2014D — fehlender Volvo-Treiber von Xhorse → unzuverlässig
- ❌ python-OBD / FastAPI-Direktanbindung (Windows-only Treiber)
- ❌ Linux-native Verwendung

## Fazit

Als **Allrounder-Adapter** für viele Hersteller nützlich — aber für
Volvo-Tiefdiagnose **nicht die erste Wahl**.

**Für Volvo:** → [../godiag-gd101/](../godiag-gd101/) (VIDA/vdash bestätigt)

## USB/IP Verwendung

```bash
# MVCI auf Router binden
sh bind-mvci.sh bind

# Windows: importieren und OEM-Software öffnen
# VAG ODIS / Toyota TIS / Subaru SSM4
```
