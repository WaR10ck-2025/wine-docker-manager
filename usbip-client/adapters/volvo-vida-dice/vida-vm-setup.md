# VIDA DiCE via USB/IP + Windows-VM — Setup Guide

## Übersicht

Dieser Guide beschreibt wie der VIDA DiCE über USB/IP vom GL.iNet Router
an eine Windows-VM weitergeleitet wird, um VIDA 2014D zu nutzen.

**Architektur:**
```
Auto (OBD2-Port)
  ↓ OBD2-Stecker
Volvo DiCE (USB)
  ↓ USB-Kabel
GL.iNet Router (USB-Host)
  ↓ USB/IP (TCP/IP Netzwerk)
Windows-PC (usbipd-win)
  ↓ virtuelles USB-Gerät
VIDA 2014D → Tiefdiagnose
```

---

## Voraussetzungen

- VIDA DiCE (original Volvo Hardware)
- GL.iNet Router mit USB/IP (kmod-usbip installiert)
- Windows 10/11 oder Windows-VM
- VIDA 2014D installiert (Volvo Diagnostics)
- usbipd-win installiert auf Windows

---

## Schritt 1: DiCE auf Router binden

```bash
# DiCE einstecken, dann auf dem Router:
sh bind-dice.sh bind

# Verify
usbip list -l | grep 17aa:d1ce
```

---

## Schritt 2: Windows — usbipd-win installieren

```powershell
# Via winget
winget install usbipd

# Verify
usbipd list
```

---

## Schritt 3: DiCE importieren (Windows)

```powershell
# DiCE-Gerät auf Router finden
usbipd list --remote 192.168.10.194

# DiCE importieren
usbipd attach --remote 192.168.10.194 --busid <BUSID>

# Verify: DiCE sollte in Gerätemanager erscheinen
devmgmt.msc
```

---

## Schritt 4: VIDA 2014D starten

1. VIDA 2014D öffnen
2. Interface auswählen: **DiCE** (nicht VCI)
3. Verbindungstest → DiCE sollte als verbunden angezeigt werden
4. Fahrzeug-Identifikation durchführen (VIN)
5. Diagnose-Funktionen nutzen

---

## Empfohlene Alternative: GODIAG GD101 + vdash

Für neue Hardware-Anschaffungen empfehlen wir statt DiCE den **GODIAG GD101**
kombiniert mit **vdash** (modernes VIDA-Ersatz-Tool):

```
Vorteile gegenüber DiCE + VIDA:
  ✅ Günstiger (~€30-60 vs ~€150-300)
  ✅ vdash ist schneller als VIDA 2014D
  ✅ Keine VIDA-Aktivierung nötig
  ✅ FTDI-basiert → USB/IP problemlos
```

→ Siehe [../godiag-gd101/vdash-setup.md](../godiag-gd101/vdash-setup.md)

---

## Troubleshooting

### DiCE wird nicht erkannt
```bash
# Auf Router prüfen
lsusb | grep "17aa:d1ce"
dmesg | tail -20

# USB/IP Module geladen?
lsmod | grep usbip
```

### VIDA zeigt "Interface nicht verfügbar"
- usbipd-win Gerät prüfen: `usbipd list`
- DiCE-Treiber neu installieren (Volvo VIDA DVD)
- VM-Neustart

### USB/IP Verbindung bricht ab
```bash
# Auf Windows: reconnect
usbipd detach --busid <BUSID>
usbipd attach --remote 192.168.10.194 --busid <BUSID>
```
