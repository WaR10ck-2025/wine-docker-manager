# Volvo VIDA DiCE — Technischer Vergleich + USB/IP Ansatz

## Übersicht

Der **Volvo VIDA DiCE** ist das offizielle Volvo-Diagnose-Interface für VIDA 2014D.

| Eigenschaft         | Wert                                              |
|---------------------|---------------------------------------------------|
| USB VID:PID         | `17aa:d1ce` (SETEK chipset)                       |
| Chipset             | SETEK proprietary                                 |
| Linux-Treiber       | ❌ Nicht verfügbar (Windows-only)                 |
| Protokoll           | J2534 + Volvo D2/GGD proprietary                 |
| python-obd          | ❌ Nicht möglich                                  |
| FastAPI OBD2        | ❌ Kein direkter Zugriff                          |
| Volvo Tiefdiagnose  | ✅ Vollzugriff (Steuergeräte, Coding, Werte)      |
| USB/IP-fähig        | ✅ Möglich (VM-Passthrough)                       |

## Vergleich: DiCE vs GODIAG GD101 für dieses Projekt

| Aspekt            | VIDA DiCE           | GODIAG GD101 (empfohlen) |
|-------------------|---------------------|--------------------------|
| Preis             | ~€150-300           | ~€30-60                  |
| VIDA 2014D        | ✅ Nativ            | ✅ Bestätigt             |
| vdash             | ✅                  | ✅ (bevorzugt)           |
| Linux-Treiber     | ❌                  | ⚠️ FTDI-basiert          |
| USB/IP Forwarding | ✅                  | ✅                       |
| python-obd        | ❌                  | ❌                       |

→ **GODIAG GD101** ist günstiger und für dieses Projekt besser geeignet.
Wähle DiCE nur wenn du ihn bereits besitzt.

## Projektintegration (USB/IP → Windows-VM)

```
GL.iNet Router
  └── USB: DiCE eingesteckt
  └── usbipd: exportiert DiCE (17aa:d1ce)

Windows-PC (native oder VM)
  └── usbipd-win: importiert DiCE
  └── VIDA 2014D: erkennt DiCE als Hardware-Interface
  └── Tiefdiagnose: Steuergeräte, Coding, Adaptionswerte
```

## Einschränkungen im OBD2-FastAPI-Kontext

- `obd_service.py` funktioniert **nicht** mit DiCE (kein Linux-Treiber)
- Kein Live-OBD2-Tab im Frontend bei DiCE-Nutzung
- Nur via Windows-VM nutzbar (kein direkter Python-Zugriff)
- VIDA erfordert Aktivierung (2014D-Lizenz)

## Wann DiCE sinnvoll

- Tiefdiagnose Volvo (Steuergeräte-Coding, Adaptionswerte, Kalibrierung)
- Vollständige VIDA-Funktionalität
- Wenn DiCE bereits vorhanden ist (→ Kosten bereits amortisiert)

## Empfehlung

Für **neue Hardware-Anschaffung** für Volvo-Tiefdiagnose:
→ **GODIAG GD101** (günstiger, VIDA/vdash bestätigt, USB/IP-kompatibel)

Für **vorhandene DiCE**:
→ Via USB/IP + Windows-VM verwenden (bind-dice.sh + vida-vm-setup.md)
