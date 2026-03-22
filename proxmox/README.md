# Wine Manager — Proxmox Deployment (Option 2)

> **Optionale Alternative** zu Umbrel/Docker-only.
> Jeder Service läuft als **eigener LXC-Container** auf Proxmox VE 8.x.
> Docker läuft *innerhalb* der LXCs — bestehende `install.sh`-Skripte bleiben unverändert.

---

## LXC-Karte (Vollständig)

```
Proxmox VE 8.x  (192.168.10.147 — bisherige Umbrel-IP)
│
├──── INFRASTRUKTUR ──────────────────────────────────────────────────
│
├── LXC  10: reverse-proxy       192.168.10.140  Nginx Proxy Manager :81
│   └── Port 80/443 → routing zu allen Services
│
├── LXC  20: casaos-dashboard    192.168.10.141  CasaOS UI           :80
│   └── Nur Dashboard — keine Docker-Services, verbindet Proxmox API
│
├──── OPENCLAW SERVICES ──────────────────────────────────────────────
│
├── LXC 101: setup-repair-agent  192.168.10.101  Python FastAPI  :8007
├── LXC 102: pionex-mcp-server   192.168.10.102  Python FastAPI  :8000
├── LXC 103: voice-assistant     192.168.10.103  Python API      :8000
├── LXC 104: n8n                 192.168.10.104  Node.js         :5678
├── LXC 105: sv-niederklein      192.168.10.105  Nginx + React   :3001
├── LXC 106: schuetzenverein     192.168.10.106  Nginx + React   :3002
├── LXC 107: deployment-hub      192.168.10.107  Node.js         :8100
├── LXC 108: yubikey-auth        192.168.10.108  Python + USB    :8110
│   └── USB-Passthrough: YubiKey (1050:0407) via /dev/hidraw*
│
├──── WINE MANAGER ───────────────────────────────────────────────────
│
├── LXC 200: wine-desktop        192.168.10.200  Wine + VNC      :5900/:8090
├── LXC 201: wine-api            192.168.10.201  FastAPI         :4000
├── LXC 202: wine-ui             192.168.10.202  Nginx React     :3000
│
├──── OBD2 / USB ─────────────────────────────────────────────────────
│
├── LXC 210: usbipd              192.168.10.210  usbipd nativ    :3240
└── VM  100: windows-obd2        192.168.10.220  Windows 10 KVM
    └── USB-Passthrough: FTDI 0403:d6da (Autocom CDP+)
```

---

## Architektur-Prinzipien

| Frage | Entscheidung |
|---|---|
| Docker inside LXC? | ✅ Ja — `nesting=1` pro LXC, `install.sh` bleibt unverändert |
| Netzwerk | Feste IPs 192.168.10.x/24, kein shared Docker bridge |
| Inter-Service Kommunikation | Via IP-Adressen direkt (statt Docker Container-Namen) |
| Reverse Proxy | LXC 10: Nginx Proxy Manager |
| App Store Dashboard | LXC 20: CasaOS (verbindet Proxmox API, kein Docker Socket) |
| USB-Passthrough (OBD2) | Native KVM USB-Passthrough an VM 100 (kein 3-Layer-Problem) |
| USB-Passthrough (YubiKey) | `/dev/hidraw*` via LXC-cgroup in LXC 108 |

---

## Warum Proxmox statt Umbrel?

```
Umbrel (Docker-only):           Proxmox (LXC + KVM):
────────────────────            ────────────────────────────
Docker Desktop                  Proxmox VE Type-1 Hypervisor
  └─ Wine Container               ├─ LXC 200: wine-desktop
  └─ KVM-in-Docker (!)            ├─ LXC 201: wine-api
      └─ Windows VM               ├─ VM 100:  Windows VM (native KVM)
          └─ USB (3 Layer)             └─ USB (direkt, 1 Layer)
```

**Hauptproblem Umbrel:** Windows VM läuft als QEMU/KVM *innerhalb* Docker → 3-Layer USB-Passthrough, `privileged:true`, keine KVM-Acceleration.

**Proxmox-Lösung:** VM 100 bekommt nativen KVM-Zugriff + direktes USB-Passthrough.

---

## Ressourcen-Planung

| LXC | Dienst | RAM | Disk | Cores |
|---|---|---|---|---|
| LXC 10 | Nginx Proxy Manager | 256 MB | 4 GB | 1 |
| LXC 20 | CasaOS Dashboard | 512 MB | 8 GB | 1 |
| LXC 101 | Setup-Repair Agent | 256 MB | 4 GB | 1 |
| LXC 102 | Pionex MCP Server | 512 MB | 8 GB | 1 |
| LXC 103 | Voice Assistant | 512 MB | 8 GB | 1 |
| LXC 104 | n8n | 1024 MB | 16 GB | 2 |
| LXC 105 | SV Niederklein | 256 MB | 4 GB | 1 |
| LXC 106 | Schützenverein | 256 MB | 4 GB | 1 |
| LXC 107 | Deployment Hub | 512 MB | 8 GB | 1 |
| LXC 108 | YubiKey Auth | 256 MB | 4 GB | 1 |
| LXC 200 | Wine Desktop | 2048 MB | 16 GB | 2 |
| LXC 201 | Wine API | 512 MB | 8 GB | 1 |
| LXC 202 | Wine UI | 256 MB | 4 GB | 1 |
| LXC 210 | usbipd | 128 MB | 2 GB | 1 |
| VM 100 | Windows OBD2 | 3072 MB | 64 GB | 2 |
| **Gesamt** | | **~11 GB RAM** | **~163 GB Disk** | |

---

## Netzwerk-Änderungen (openclaw-net → IPs)

Bestehende `docker-compose.yml` nutzen Container-Namen für Service-Discovery.
Auf Proxmox kommunizieren Services direkt per IP.

**Zu ändernde Env-Variablen:**

| Service | Alt (Container-Name) | Neu (IP) |
|---|---|---|
| wine-api → wine-desktop | `WINE_CONTAINER=wine-desktop` | Via Docker exec innerhalb LXC 200/201 |
| OBD Monitor | `OBD_MONITOR_HOST=192.168.10.194` | unverändert (externer Mini-PC) |
| USBIP Remote | `USBIP_REMOTE_HOST=192.168.10.194` | unverändert |

---

## Schnellstart

```bash
# 1. Auf dem Proxmox-Host als root:
git clone https://github.com/WaR10ck-2025/wine-docker-manager.git /opt/wine-manager
cd /opt/wine-manager/proxmox

# 2. Alle LXCs + VM anlegen (dauert ~10 Min):
bash scripts/install-all.sh

# 3. Verifizieren:
for ID in 10 20 101 102 103 104 105 106 107 108 200 201 202 210; do
  echo "LXC $ID: $(pct status $ID 2>/dev/null || echo 'nicht vorhanden')"
done

# 4. Dashboard öffnen:
# CasaOS:          http://192.168.10.141
# Nginx Proxy Mgr: http://192.168.10.140:81
# Wine Manager UI: http://192.168.10.202:3000
```

---

## Dateien

```
proxmox/
├── README.md                             # Diese Datei
├── MIGRATION.md                          # Umbrel → Proxmox Schritt-für-Schritt
├── docker-compose.proxmox.yml            # Override: usbip-server + windows-vm deaktiviert
│
├── config/
│   ├── ip-plan.md                        # Vollständige IP-Tabelle
│   ├── usbipd.service                    # systemd Unit für LXC 210
│   ├── yubikey-usb-passthrough.md        # HID /dev/hidraw* in LXC 108
│   └── usb-passthrough-obd2.md          # FTDI 0403:d6da an VM 100
│
└── scripts/
    ├── install-all.sh                    # Master-Skript
    ├── install-lxc-reverse-proxy.sh      # LXC 10
    ├── install-lxc-casaos.sh             # LXC 20
    ├── install-lxc-setup-repair.sh       # LXC 101
    ├── install-lxc-pionex.sh             # LXC 102
    ├── install-lxc-voice.sh              # LXC 103
    ├── install-lxc-n8n.sh               # LXC 104
    ├── install-lxc-sv-niederklein.sh     # LXC 105
    ├── install-lxc-schuetzenverein.sh    # LXC 106
    ├── install-lxc-deployment-hub.sh     # LXC 107
    ├── install-lxc-yubikey.sh            # LXC 108
    ├── install-lxc-wine-desktop.sh       # LXC 200
    ├── install-lxc-wine-api.sh           # LXC 201
    ├── install-lxc-wine-ui.sh            # LXC 202
    ├── install-lxc-usbipd.sh             # LXC 210
    └── setup-windows-vm.md              # VM 100 Anleitung
```
