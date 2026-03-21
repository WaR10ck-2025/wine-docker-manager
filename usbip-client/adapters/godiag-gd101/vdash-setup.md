# vdash + GODIAG GD101 — Volvo Tiefdiagnose Setup Guide

## Was ist vdash?

**vdash** ist ein modernes Open-Source Tool für Volvo-Diagnose, das als
Ersatz für VIDA 2014D entwickelt wurde. Es unterstützt J2534-kompatible
Adapter wie den GODIAG GD101.

**Vorteile gegenüber VIDA 2014D + DiCE:**
- ✅ Kein kostspieliges Original-DiCE nötig
- ✅ Schneller und moderner als VIDA
- ✅ Keine VIDA-Aktivierung/Lizenz nötig
- ✅ Offene Entwicklung, aktive Community
- ✅ Kompatibel mit günstigem GODIAG GD101 (~€30-60)

---

## Voraussetzungen

- GODIAG GD101 (oder kompatibler J2534-Adapter)
- GL.iNet Router mit USB/IP (kmod-usbip installiert)
- Windows 10/11 (native oder VM)
- usbipd-win auf Windows

---

## Schritt 1: GD101 auf Router binden

```bash
# GD101 einstecken
sh bind-gd101.sh bind

# Oder via obd-ctl:
obd-ctl bind
```

---

## Schritt 2: Windows — usbipd-win + GD101 importieren

```powershell
# usbipd-win installieren (falls noch nicht)
winget install usbipd

# GD101 auf Router finden und importieren
usbipd list --remote 192.168.10.194
usbipd attach --remote 192.168.10.194 --busid <BUSID>

# GD101-Treiber installieren (FTDI Virtual COM Port)
# https://ftdichip.com/drivers/vcp-drivers/
# Gerät erscheint als COM-Port in Gerätemanager
```

---

## Schritt 3: vdash installieren

vdash ist auf GitHub verfügbar:
1. Aktuelle Version herunterladen
2. J2534-Treiber für GD101 installieren (Hersteller-Website)
3. vdash starten → Interface: GD101 J2534

**VIDA 2014D Alternative:**
```
Falls vdash für deine Volvo-Version nicht reicht:
  VIDA 2014D + GD101 funktioniert ebenfalls
  Download: Volvo Community / Internet Archive (2014D DVD)
```

---

## Schritt 4: Fahrzeug-Diagnose

Mit vdash oder VIDA 2014D + GD101:
- **Fehlercode-Diagnose** (alle Steuergeräte)
- **Live-Daten** (Sensor-Werte, Adaptionswerte)
- **Steuergeräte-Coding** (Parameter anpassen)
- **Software-Updates** (ECU-Flashen, wenn verfügbar)
- **Kalibrierung** (Sensoren, Getriebe)

---

## Troubleshooting

### GD101 nicht erkannt
```bash
lsusb | grep "0403"
# Falls anderer VID:PID → adapter.conf aktualisieren
```

### vdash zeigt "Kein Interface"
- J2534-Treiber installiert?
- GD101 via usbipd-win importiert?
- COM-Port in Gerätemanager sichtbar?

### VIDA startet nicht
- VIDA 2014D erfordert Windows 7/8/10 (32-bit Komponenten)
- Falls in VM: .NET Framework 3.5 + MDAC installieren

---

## USB/IP Dauerbetrieb (autostart)

```bash
# Auf GL.iNet Router — GD101 automatisch binden beim Boot:
# /etc/init.d/usbipd liest /etc/obd-adapter.conf automatisch

cp adapter.conf /etc/obd-adapter.conf
/etc/init.d/usbipd enable
/etc/init.d/usbipd start
```
