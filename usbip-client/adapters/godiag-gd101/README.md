# GODIAG GD101 — ★ Empfohlen für Volvo Tiefdiagnose

## Übersicht

Der **GODIAG GD101** ist ein J2534-basierter OBD2-Adapter, der explizit
für Volvo VIDA und vdash getestet und bestätigt wurde.

| Eigenschaft         | Wert                                              |
|---------------------|---------------------------------------------------|
| USB VID:PID         | FTDI-basiert (variiert — via lsusb prüfen)        |
| Chipset             | FTDI oder kompatibel                              |
| Protokoll           | J2534                                             |
| Linux-Treiber       | ⚠️ herstellerabhängig (FTDI: ftdi_sio verfügbar) |
| python-obd          | ❌ J2534 kein direkter Zugriff                    |
| FastAPI OBD2        | ❌ Kein direkter Zugriff                          |
| Volvo VIDA 2014D    | ✅ **Bestätigt** (explizit für Volvo entwickelt)  |
| vdash               | ✅ **Bestätigt** (modernes VIDA-Ersatz-Tool)      |
| Volvo Tiefdiagnose  | ✅ Vollzugriff (Steuergeräte, Coding, Werte)      |
| USB/IP-fähig        | ✅                                                |
| Preis               | ~€30-60 (deutlich günstiger als DiCE)             |

## Warum GD101 besser als VIDA DiCE für dieses Projekt

1. **Günstiger** (~€30-60 vs ~€150-300)
2. **VIDA 2014D bestätigt** — GD101 wurde explizit für Volvo VIDA entwickelt
3. **vdash** — moderner, schneller als VIDA 2014D + GD101
4. **USB/IP-Forwarding** problemlos
5. **FTDI-basiert** — potenziell Linux-tauglicher als DiCE (SETEK)

## Verwendung mit vdash (empfohlen)

**vdash** ist ein modernes Open-Source VIDA-Ersatz-Tool:
```
Vorteile gegenüber VIDA 2014D:
  ✅ Schneller als VIDA
  ✅ Keine Aktivierung nötig
  ✅ Modernes UI
  ✅ Aktive Community
```

→ Vollständige Anleitung: [vdash-setup.md](vdash-setup.md)

## Verwendung mit VIDA 2014D

```
GL.iNet Router
  └── USB: GD101 eingesteckt
  └── usbipd: exportiert GD101

Windows-PC
  └── usbipd-win: importiert GD101
  └── VIDA 2014D oder vdash → Volvo Tiefdiagnose
```

→ USB/IP Setup: [bind-gd101.sh](bind-gd101.sh)

## Limitierungen

- J2534-Protokoll → kein direkter python-obd Zugriff
- Nur Volvo (nicht Multi-Brand wie CDP+)
- Windows-VM für VIDA/vdash nötig
- VID:PID variiert → vor Kauf per lsusb prüfen

## Kaufempfehlung

GODIAG GD101 auf Amazon/eBay: Suche nach "GODIAG GD101 Volvo VIDA DiCE".
Prüfe Bewertungen auf vdash/VIDA-Kompatibilität.
