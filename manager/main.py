"""
Wine Manager API — FastAPI Backend
Verwaltet Software-Installationen im Wine-Container über docker exec.
"""

import asyncio
import json
import os
import socket
import subprocess
import uuid
from datetime import datetime
from pathlib import Path
from typing import AsyncGenerator

import aiofiles
import httpx
from fastapi import FastAPI, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

app = FastAPI(title="Wine Manager API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOAD_DIR = Path(os.getenv("UPLOAD_DIR", "/uploads"))
WINE_CONTAINER = os.getenv("WINE_CONTAINER", "wine-desktop")
# Pfad zum WINEPREFIX *innerhalb des wine-desktop Containers* (für docker exec)
WINE_CONTAINER_PREFIX = os.getenv("WINE_CONTAINER_PREFIX", "/home/wineuser/.wine")
# Pfad zum WINEPREFIX *im manager-api Container* (zum Lesen installierter Apps)
LOCAL_WINEPREFIX = Path(os.getenv("LOCAL_WINEPREFIX", "/wine-prefix/.wine"))
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

# Laufende Prozesse: pid → asyncio.subprocess.Process
_processes: dict[int, asyncio.subprocess.Process] = {}
# Log-Puffer: pid → Liste von Zeilen
_logs: dict[int, list[str]] = {}


def _docker_exec(cmd: list[str]) -> list[str]:
    """Führt einen Befehl im Wine-Container als wineuser aus."""
    return [
        "docker", "exec", "-u", "wineuser",
        "-e", f"WINEPREFIX={WINE_CONTAINER_PREFIX}",
        "-e", "DISPLAY=:99",
        "-e", "WINEDEBUG=-all",
        WINE_CONTAINER,
        *cmd,
    ]


# ── Upload ──────────────────────────────────────────────────────────────────

@app.post("/upload")
async def upload_installer(file: UploadFile):
    """Lädt einen .exe/.msi Installer in /uploads hoch."""
    allowed = {".exe", ".msi", ".zip"}
    suffix = Path(file.filename).suffix.lower()
    if suffix not in allowed:
        raise HTTPException(400, f"Dateityp nicht erlaubt: {suffix}. Erlaubt: {allowed}")

    dest = UPLOAD_DIR / file.filename
    async with aiofiles.open(dest, "wb") as f:
        while chunk := await file.read(1024 * 1024):  # 1 MB Chunks
            await f.write(chunk)

    return {"filename": file.filename, "size": dest.stat().st_size}


@app.get("/uploads")
def list_uploads():
    """Listet alle hochgeladenen Installer-Dateien."""
    files = []
    for p in sorted(UPLOAD_DIR.iterdir()):
        if p.is_file():
            files.append({"filename": p.name, "size": p.stat().st_size})
    return files


@app.delete("/uploads/{filename}")
def delete_upload(filename: str):
    """Löscht eine hochgeladene Datei."""
    path = UPLOAD_DIR / filename
    if not path.exists():
        raise HTTPException(404, "Datei nicht gefunden")
    path.unlink()
    return {"deleted": filename}


# ── Installation ────────────────────────────────────────────────────────────

@app.post("/install")
async def install_app(filename: str, method: str = "auto"):
    """
    Installiert eine hochgeladene Datei im Wine-Container.
    method: 'auto' (erkennt .msi/.exe), 'wine', 'msiexec', 'winetricks'
    """
    path = UPLOAD_DIR / filename
    if not path.exists():
        raise HTTPException(404, f"Datei nicht gefunden: {filename}")

    container_path = f"/uploads/{filename}"
    suffix = Path(filename).suffix.lower()

    if method == "auto":
        method = "msiexec" if suffix == ".msi" else "wine"

    if method == "msiexec":
        cmd = _docker_exec(["wine", "msiexec", "/i", container_path, "/qb-!"])
    elif method == "winetricks":
        # Winetricks-Komponente (z.B. dotnet48, vcrun2019)
        cmd = _docker_exec(["winetricks", "-q", filename])
    else:
        cmd = _docker_exec(["wine", container_path])

    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    pid = proc.pid
    _processes[pid] = proc
    _logs[pid] = []

    # Log im Hintergrund sammeln
    asyncio.create_task(_collect_logs(pid, proc))

    return {"pid": pid, "cmd": cmd[4:], "filename": filename}


async def _collect_logs(pid: int, proc: asyncio.subprocess.Process):
    """Sammelt stdout/stderr eines Subprozesses in _logs[pid]."""
    async for raw in proc.stdout:
        line = raw.decode(errors="replace").rstrip()
        _logs[pid].append(line)
    await proc.wait()
    _logs[pid].append(f"__EXIT__{proc.returncode}")


@app.get("/logs/{pid}")
async def stream_logs(pid: int):
    """Streamt den Installer-Output als Server-Sent Events."""
    if pid not in _logs:
        raise HTTPException(404, f"Prozess {pid} unbekannt")

    async def generator() -> AsyncGenerator[str, None]:
        sent = 0
        while True:
            lines = _logs.get(pid, [])
            for line in lines[sent:]:
                yield f"data: {json.dumps(line)}\n\n"
                sent += 1
                if line.startswith("__EXIT__"):
                    return
            await asyncio.sleep(0.2)

    return StreamingResponse(generator(), media_type="text/event-stream")


@app.get("/status/{pid}")
def process_status(pid: int):
    """Gibt den aktuellen Status eines Installations-Prozesses zurück."""
    if pid not in _logs:
        raise HTTPException(404, f"Prozess {pid} unbekannt")
    logs = _logs[pid]
    exit_line = next((l for l in logs if l.startswith("__EXIT__")), None)
    return {
        "pid": pid,
        "running": exit_line is None,
        "exit_code": int(exit_line.replace("__EXIT__", "")) if exit_line else None,
        "log_lines": len(logs),
    }


# ── Installierte Apps ───────────────────────────────────────────────────────

@app.get("/apps")
def list_apps():
    """
    Listet installierte Apps aus dem WINEPREFIX.
    Liest Programme aus drive_c/Program Files und drive_c/Program Files (x86).
    """
    prefix_path = LOCAL_WINEPREFIX
    apps = []

    for prog_dir in ["drive_c/Program Files", "drive_c/Program Files (x86)"]:
        base = prefix_path / prog_dir
        if not base.exists():
            continue
        for vendor_dir in sorted(base.iterdir()):
            if not vendor_dir.is_dir():
                continue
            for exe in sorted(vendor_dir.rglob("*.exe")):
                # Relative Pfad für wine-Aufruf
                rel = str(exe.relative_to(prefix_path / "drive_c"))
                apps.append({
                    "name": exe.stem,
                    "vendor": vendor_dir.name,
                    "exe": f"C:\\{rel.replace('/', '\\')}",
                    "path": str(exe),
                })

    return apps


@app.post("/launch")
async def launch_app(exe_path: str):
    """Startet eine installierte App im Wine-Container (sichtbar via noVNC)."""
    cmd = _docker_exec(["wine", exe_path])
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.DEVNULL,
    )
    return {"pid": proc.pid, "exe": exe_path}


# ── Winetricks ──────────────────────────────────────────────────────────────

WINETRICKS_COMMON = [
    "dotnet48", "dotnet40", "dotnet35",
    "vcrun2022", "vcrun2019", "vcrun2017", "vcrun2015",
    "d3dx9", "dxvk", "ie8",
    "corefonts", "mfc42",
]


@app.get("/winetricks/presets")
def winetricks_presets():
    """Gibt eine Liste gängiger Winetricks-Komponenten zurück."""
    return {"presets": WINETRICKS_COMMON}


@app.post("/winetricks/install")
async def winetricks_install(component: str):
    """Installiert eine Winetricks-Komponente (z.B. dotnet48, vcrun2019)."""
    cmd = _docker_exec(["winetricks", "-q", component])
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    pid = proc.pid
    _processes[pid] = proc
    _logs[pid] = []
    asyncio.create_task(_collect_logs(pid, proc))
    return {"pid": pid, "component": component}


# ── USB/IP ──────────────────────────────────────────────────────────────────

USBIP_CONTAINER = os.getenv("USBIP_CONTAINER", "wine-usbip-server")
WINDOWS_VM_CONTAINER = os.getenv("WINDOWS_VM_CONTAINER", "wine-windows-vm")
# IP-Adresse des headless Mini-PCs mit USB/IP Server (leer = nicht konfiguriert)
USBIP_REMOTE_HOST = os.getenv("USBIP_REMOTE_HOST", "")
NANOPI_ETH_HOST = os.getenv("NANOPI_ETH_HOST", "")   # Ethernet-IP des Mini-PCs (optional)
# OBD2 Monitor Service auf dem Mini-PC (Port 8765)
OBD_MONITOR_HOST = os.getenv("OBD_MONITOR_HOST", "")
OBD_MONITOR_PORT = int(os.getenv("OBD_MONITOR_PORT", "8765"))


def _container_running(name: str) -> bool:
    """Prüft ob ein Docker-Container läuft."""
    try:
        result = subprocess.run(
            ["docker", "inspect", "--format", "{{.State.Running}}", name],
            capture_output=True, text=True, timeout=5
        )
        return result.stdout.strip() == "true"
    except Exception:
        return False


@app.get("/usbip/status")
def usbip_status():
    """Status des USB/IP-Servers und gebundener Geräte."""
    running = _container_running(USBIP_CONTAINER)
    devices = []
    if running:
        try:
            result = subprocess.run(
                ["docker", "exec", USBIP_CONTAINER, "usbip", "list", "--exported"],
                capture_output=True, text=True, timeout=5
            )
            devices = [l.strip() for l in result.stdout.splitlines() if l.strip()]
        except Exception:
            pass
    return {"running": running, "container": USBIP_CONTAINER, "devices": devices}


@app.post("/usbip/start")
async def usbip_start():
    """Startet den USB/IP-Server-Container."""
    proc = await asyncio.create_subprocess_exec(
        "docker", "compose", "--profile", "usbip", "up", "-d", "usbip-server",
        cwd="/app",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
    )
    out, _ = await proc.communicate()
    return {"started": proc.returncode == 0, "output": out.decode(errors="replace")}


@app.post("/usbip/stop")
async def usbip_stop():
    """Stoppt den USB/IP-Server-Container."""
    proc = await asyncio.create_subprocess_exec(
        "docker", "stop", USBIP_CONTAINER,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
    )
    out, _ = await proc.communicate()
    return {"stopped": proc.returncode == 0}


def _host_reachable(host: str, port: int = 22, timeout: float = 2.0) -> bool:
    try:
        s = socket.create_connection((host, port), timeout=timeout)
        s.close()
        return True
    except Exception:
        return False


@app.get("/usbip/remote/status")
def usbip_remote_status():
    """Prüft ob der Mini-PC USB/IP-Server (Port 3240) erreichbar ist."""
    if not USBIP_REMOTE_HOST:
        return {"configured": False, "reachable": False, "host": "", "connection_type": None}
    reachable = _host_reachable(USBIP_REMOTE_HOST, 3240)
    # Verbindungstyp ermitteln: Ethernet (Port 22) und/oder WiFi
    eth_up = bool(NANOPI_ETH_HOST) and _host_reachable(NANOPI_ETH_HOST, 22)
    wifi_up = _host_reachable(USBIP_REMOTE_HOST, 22)
    if eth_up and wifi_up:
        connection_type = "both"
    elif eth_up:
        connection_type = "ethernet"
    elif wifi_up:
        connection_type = "wifi"
    else:
        connection_type = None
    return {"configured": True, "reachable": reachable, "host": USBIP_REMOTE_HOST, "connection_type": connection_type}


# ── OBD2 Monitor (Proxy → Mini-PC Port 8765) ────────────────────────────────

def _obd_base_url() -> str:
    return f"http://{OBD_MONITOR_HOST}:{OBD_MONITOR_PORT}"


@app.get("/obd/status")
async def obd_status():
    """OBD2 Verbindungsstatus vom Mini-PC."""
    if not OBD_MONITOR_HOST:
        return {"connected": False, "protocol": None, "port": None, "error": "OBD_MONITOR_HOST nicht konfiguriert"}
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            r = await client.get(f"{_obd_base_url()}/obd/status")
            return r.json()
    except Exception as e:
        return {"connected": False, "protocol": None, "port": None, "error": str(e)}


@app.get("/obd/data")
async def obd_data():
    """Aktueller OBD2-Datensatz (RPM, Geschwindigkeit, Temp. etc.)."""
    if not OBD_MONITOR_HOST:
        raise HTTPException(503, "OBD_MONITOR_HOST nicht konfiguriert")
    async with httpx.AsyncClient(timeout=3.0) as client:
        r = await client.get(f"{_obd_base_url()}/obd/data")
        r.raise_for_status()
        return r.json()


@app.get("/obd/dtcs")
async def obd_dtcs():
    """Gespeicherte Fehlercodes (DTCs) vom Fahrzeug lesen."""
    if not OBD_MONITOR_HOST:
        raise HTTPException(503, "OBD_MONITOR_HOST nicht konfiguriert")
    async with httpx.AsyncClient(timeout=5.0) as client:
        r = await client.get(f"{_obd_base_url()}/obd/dtcs")
        r.raise_for_status()
        return r.json()


@app.post("/obd/clear-dtcs")
async def obd_clear_dtcs():
    """Gespeicherte Fehlercodes löschen (Mode 04)."""
    if not OBD_MONITOR_HOST:
        raise HTTPException(503, "OBD_MONITOR_HOST nicht konfiguriert")
    async with httpx.AsyncClient(timeout=5.0) as client:
        r = await client.post(f"{_obd_base_url()}/obd/clear-dtcs")
        r.raise_for_status()
        return r.json()


@app.get("/obd/stream")
async def obd_stream():
    """SSE-Stream: leitet OBD2-Daten vom Mini-PC weiter (~2Hz)."""
    if not OBD_MONITOR_HOST:
        raise HTTPException(503, "OBD_MONITOR_HOST nicht konfiguriert")

    async def generator() -> AsyncGenerator[str, None]:
        async with httpx.AsyncClient(timeout=None) as client:
            async with client.stream("GET", f"{_obd_base_url()}/obd/stream") as resp:
                async for line in resp.aiter_lines():
                    if line.startswith("data:"):
                        yield f"{line}\n\n"

    return StreamingResponse(generator(), media_type="text/event-stream")


# ── Windows VM ──────────────────────────────────────────────────────────────

@app.get("/windowsvm/status")
def windowsvm_status():
    """Status der Windows-VM."""
    running = _container_running(WINDOWS_VM_CONTAINER)
    return {"running": running, "container": WINDOWS_VM_CONTAINER}


@app.post("/windowsvm/start")
async def windowsvm_start():
    """Startet die Windows-VM."""
    proc = await asyncio.create_subprocess_exec(
        "docker", "compose", "--profile", "windows-vm", "up", "-d", "windows-vm",
        cwd="/app",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
    )
    out, _ = await proc.communicate()
    return {"started": proc.returncode == 0, "output": out.decode(errors="replace")}


@app.post("/windowsvm/stop")
async def windowsvm_stop():
    """Fährt die Windows-VM herunter (graceful shutdown)."""
    proc = await asyncio.create_subprocess_exec(
        "docker", "stop", "--time", "120", WINDOWS_VM_CONTAINER,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
    )
    out, _ = await proc.communicate()
    return {"stopped": proc.returncode == 0}


# ── Fahrzeuge (Vehicle Management) ──────────────────────────────────────────

VEHICLES_FILE = UPLOAD_DIR / "vehicles.json"


def _load_vehicles() -> list[dict]:
    """Lädt Fahrzeugliste aus vehicles.json."""
    if not VEHICLES_FILE.exists():
        return []
    try:
        return json.loads(VEHICLES_FILE.read_text(encoding="utf-8"))
    except Exception:
        return []


def _save_vehicles(vehicles: list[dict]) -> None:
    VEHICLES_FILE.write_text(json.dumps(vehicles, indent=2, ensure_ascii=False), encoding="utf-8")


@app.get("/vehicles")
def list_vehicles():
    """Listet alle gespeicherten Fahrzeuge."""
    return _load_vehicles()


@app.post("/vehicles")
def create_vehicle(data: dict):
    """Erstellt ein neues Fahrzeug."""
    vehicles = _load_vehicles()
    vehicle = {
        "id": str(uuid.uuid4()),
        "name": data.get("name", ""),
        "make": data.get("make", ""),
        "model": data.get("model", ""),
        "year": data.get("year", 0),
        "engine": data.get("engine", ""),
        "obd_protocol": data.get("obd_protocol", "auto"),
        "vin": data.get("vin", ""),
        "notes": data.get("notes", ""),
        "dtc_history": [],
        "created_at": datetime.now().isoformat(),
    }
    vehicles.append(vehicle)
    _save_vehicles(vehicles)
    return vehicle


@app.put("/vehicles/{vehicle_id}")
def update_vehicle(vehicle_id: str, data: dict):
    """Aktualisiert ein bestehendes Fahrzeug."""
    vehicles = _load_vehicles()
    for i, v in enumerate(vehicles):
        if v["id"] == vehicle_id:
            for key in ["name", "make", "model", "year", "engine", "obd_protocol", "vin", "notes"]:
                if key in data:
                    v[key] = data[key]
            vehicles[i] = v
            _save_vehicles(vehicles)
            return v
    raise HTTPException(404, "Fahrzeug nicht gefunden")


@app.delete("/vehicles/{vehicle_id}")
def delete_vehicle(vehicle_id: str):
    """Löscht ein Fahrzeug inkl. DTC-Historie."""
    vehicles = _load_vehicles()
    before = len(vehicles)
    vehicles = [v for v in vehicles if v["id"] != vehicle_id]
    if len(vehicles) == before:
        raise HTTPException(404, "Fahrzeug nicht gefunden")
    _save_vehicles(vehicles)
    return {"deleted": vehicle_id}


@app.post("/vehicles/{vehicle_id}/dtc-session")
def save_dtc_session(vehicle_id: str, data: dict):
    """Speichert eine DTC-Diagnosesitzung bei einem Fahrzeug."""
    vehicles = _load_vehicles()
    for i, v in enumerate(vehicles):
        if v["id"] == vehicle_id:
            session = {
                "date": datetime.now().isoformat(),
                "codes": data.get("codes", []),
                "odometer": data.get("odometer"),
                "notes": data.get("notes", ""),
            }
            v.setdefault("dtc_history", []).append(session)
            vehicles[i] = v
            _save_vehicles(vehicles)
            return session
    raise HTTPException(404, "Fahrzeug nicht gefunden")


@app.delete("/vehicles/{vehicle_id}/dtc-session/{session_index}")
def delete_dtc_session(vehicle_id: str, session_index: int):
    """Löscht eine einzelne DTC-Sitzung."""
    vehicles = _load_vehicles()
    for i, v in enumerate(vehicles):
        if v["id"] == vehicle_id:
            history = v.get("dtc_history", [])
            if session_index < 0 or session_index >= len(history):
                raise HTTPException(404, "Sitzung nicht gefunden")
            history.pop(session_index)
            v["dtc_history"] = history
            vehicles[i] = v
            _save_vehicles(vehicles)
            return {"deleted": session_index}
    raise HTTPException(404, "Fahrzeug nicht gefunden")


# ── Gesundheitsprüfung ──────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {"status": "ok", "wine_container": WINE_CONTAINER}
