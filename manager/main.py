"""
Wine Manager API — FastAPI Backend
Verwaltet Software-Installationen im Wine-Container über docker exec.
"""

import asyncio
import json
import os
import subprocess
from pathlib import Path
from typing import AsyncGenerator

import aiofiles
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
WINEPREFIX = os.getenv("WINEPREFIX", "/home/wineuser/.wine")
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

# Laufende Prozesse: pid → asyncio.subprocess.Process
_processes: dict[int, asyncio.subprocess.Process] = {}
# Log-Puffer: pid → Liste von Zeilen
_logs: dict[int, list[str]] = {}


def _docker_exec(cmd: list[str]) -> list[str]:
    """Führt einen Befehl im Wine-Container als wineuser aus."""
    return [
        "docker", "exec", "-u", "wineuser",
        "-e", f"WINEPREFIX={WINEPREFIX}",
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
    prefix_path = Path("/wine-prefix/.wine")
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


# ── Gesundheitsprüfung ──────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {"status": "ok", "wine_container": WINE_CONTAINER}
