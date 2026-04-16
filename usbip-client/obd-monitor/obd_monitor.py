#!/usr/bin/env python3
"""
OBD2 Live Monitor — SSH Terminal Dashboard
==========================================

Verwendung:
  python3 obd_monitor.py [--port /dev/ttyUSB0] [--debug]
  python3 obd_monitor.py --tcp 192.168.10.213:35000         # ELM327 über TCP (Vgate iCar 2, ELM327-Sim, WiCAN Pro ELM-Mode)

Steuerung im Terminal:
  r  → DTCs aktualisieren
  c  → DTCs löschen (mit Bestätigung)
  q  → Beenden

Protokoll-Erkennung (automatisch, nur bei --port):
  1. ELM327 AT-Probe (für CDP+ Klone mit ELM327-Firmware)
  2. ISO 9141-2 direkt via pyserial (5-Baud Init, für echten Autocom CDP+)

Bei --tcp wird direkt ELM327 über socket://host:port verbunden (python-obd
nutzt pyserial's TCP-URL-Handler transparent). Kein Auto-Detect, kein Fallback.
"""
import argparse
import logging
import sys
import termios
import threading
import tty
from typing import Optional

import time

from rich.columns import Columns
from rich.console import Console, Group
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from protocols.base import DTC, OBDReading
from protocols.elm327 import ELM327Protocol, probe as elm327_probe
from protocols.iso9141 import ISO9141Protocol, _find_port

console = Console()


# ── Protokoll-Erkennung ──────────────────────────────────────────────────────

def detect_and_connect(port: Optional[str], tcp: Optional[str] = None):
    """
    Erkennt Protokoll und verbindet.
    Gibt (protocol_instance, actual_port) oder (None, None) zurück.

    Bei `tcp` (Format "host:port") wird direkt ELM327 über socket:// verbunden,
    ohne Auto-Detect und ohne ISO 9141-2-Fallback.
    """
    if tcp:
        url = f"socket://{tcp}"
        console.print(f"[dim]Verbinde ELM327 via TCP ({url})...[/]")
        proto = ELM327Protocol()
        if proto.connect(url):
            console.print(f"[green]ELM327 (TCP) verbunden ✓[/]")
            return proto, url
        return None, None

    target_port = port or _find_port()
    if not target_port:
        return None, None

    console.print(f"[dim]Teste ELM327 auf {target_port}...[/]")
    if elm327_probe(target_port):
        proto = ELM327Protocol()
        if proto.connect(target_port):
            console.print(f"[green]ELM327 verbunden ✓[/]")
            return proto, target_port

    console.print(f"[dim]Starte ISO 9141-2 (5-Baud Init)...[/]")
    proto = ISO9141Protocol()
    if proto.connect(target_port):
        console.print(f"[green]ISO 9141-2 verbunden ✓[/]")
        return proto, target_port

    return None, None


# ── Dashboard ────────────────────────────────────────────────────────────────

def _fmt(value: Optional[float], unit: str, decimals: int = 0) -> str:
    if value is None:
        return "[dim]--[/]"
    return f"[bright_white]{value:.{decimals}f}[/] [dim]{unit}[/]"


def build_dashboard(
    reading: OBDReading,
    dtcs: list[DTC],
    protocol: str,
    port: str,
    connected: bool,
) -> Panel:
    """Erstellt das rich Dashboard-Panel."""

    # ── Status-Zeile ──
    if connected:
        status = Text.from_markup(
            f"[green]●[/] VERBUNDEN  [dim]│[/]  Protokoll: [cyan]{protocol.upper()}[/]"
            f"  [dim]│[/]  Port: [yellow]{port}[/]"
        )
    else:
        status = Text.from_markup("[red]● GETRENNT[/] — Verbinde...")

    # ── ENGINE-Spalte ──
    eng = Table.grid(padding=(0, 2))
    eng.add_column(style="dim", width=11)
    eng.add_column()
    eng.add_row("RPM",       _fmt(reading.rpm, "rpm"))
    eng.add_row("Kühlmittel", _fmt(reading.coolant_temp, "°C"))
    eng.add_row("Batterie",  _fmt(reading.battery_voltage, "V", 1))
    engine_panel = Panel(eng, title="[bold blue]MOTOR[/]", border_style="blue", padding=(0, 1))

    # ── FAHRT-Spalte ──
    mot = Table.grid(padding=(0, 2))
    mot.add_column(style="dim", width=11)
    mot.add_column()
    mot.add_row("Geschw.",   _fmt(reading.speed, "km/h"))
    mot.add_row("Last",      _fmt(reading.engine_load, "%", 1))
    motion_panel = Panel(mot, title="[bold cyan]FAHRT[/]", border_style="cyan", padding=(0, 1))

    # ── KRAFTSTOFF-Spalte ──
    fuel = Table.grid(padding=(0, 2))
    fuel.add_column(style="dim", width=11)
    fuel.add_column()
    fuel.add_row("Trim Kurz", _fmt(reading.short_fuel_trim, "%", 1))
    fuel.add_row("Trim Lang", _fmt(reading.long_fuel_trim, "%", 1))
    fuel_panel = Panel(fuel, title="[bold yellow]KRAFTSTOFF[/]", border_style="yellow", padding=(0, 1))

    # ── Throttle-Balken ──
    throttle_pct = int(reading.throttle or 0)
    bar_width = 28
    filled = int(bar_width * throttle_pct / 100)
    bar = "[green]" + "█" * filled + "[/][dim]" + "░" * (bar_width - filled) + "[/]"
    throttle_line = Text.from_markup(
        f"  Drosselklappe: {bar}  [bright_white]{throttle_pct}%[/]"
    )

    # ── DTC-Sektion ──
    if not dtcs:
        dtc_content = Text.from_markup("[green]Keine Fehlercodes gespeichert[/]")
    else:
        codes_str = "  ".join(f"[red bold]{d.code}[/]" for d in dtcs)
        dtc_content = Text.from_markup(codes_str)

    dtc_panel = Panel(
        dtc_content,
        title=f"[bold]FEHLERCODES (DTCs)  [dim]{len(dtcs)} Einträge[/][/]",
        border_style="dim",
        padding=(0, 1),
    )

    # ── Tasten-Legende ──
    keys = Text.from_markup(
        "  [dim][[/][bold]r[/][dim]][/] DTCs aktualisieren   "
        "[dim][[/][bold]c[/][dim]][/] DTCs löschen   "
        "[dim][[/][bold]q[/][dim]][/] Beenden"
    )

    content = Group(
        status,
        Text(""),
        Columns([engine_panel, motion_panel, fuel_panel], equal=True),
        Text(""),
        throttle_line,
        Text(""),
        dtc_panel,
        Text(""),
        keys,
    )

    return Panel(
        content,
        title="[bold white]OBD2 LIVE — Autocom CDP+ / Suzuki Wagon R+ 2004[/]",
        border_style="white",
        padding=(0, 1),
    )


# ── Haupt-Loop ───────────────────────────────────────────────────────────────

def run_monitor(port: Optional[str], tcp: Optional[str], debug: bool):
    log_level = logging.DEBUG if debug else logging.WARNING
    logging.basicConfig(level=log_level, format="[%(levelname)s] %(name)s: %(message)s")

    console.print()
    console.print("[bold white]OBD2 Monitor[/] — verbinde mit Fahrzeug...")
    if tcp:
        console.print(f"[dim]TCP-Modus: {tcp}[/]")
    else:
        console.print("[dim]Zündung einschalten (Motor muss nicht laufen)[/]")
    console.print()

    proto, actual_port = detect_and_connect(port, tcp)
    if not proto:
        console.print("[red]Verbindung fehlgeschlagen.[/]")
        console.print("[dim]Prüfen: CDP+ eingesteckt? Zündung an? Port korrekt?[/]")
        sys.exit(1)

    reading = OBDReading()
    dtcs: list[DTC] = []
    stop_event = threading.Event()
    refresh_dtcs = threading.Event()

    # ── Keyboard-Listener (separater Thread) ──
    def keyboard_listener():
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            while not stop_event.is_set():
                ch = sys.stdin.read(1)
                if ch in ("q", "Q", "\x03"):  # q oder Ctrl+C
                    stop_event.set()
                elif ch in ("r", "R"):
                    refresh_dtcs.set()
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

    kb_thread = threading.Thread(target=keyboard_listener, daemon=True)
    kb_thread.start()

    # Initiale DTC-Abfrage
    dtcs = proto.read_dtcs()

    with Live(console=console, refresh_per_second=2, screen=False) as live:
        while not stop_event.is_set():
            if refresh_dtcs.is_set():
                dtcs = proto.read_dtcs()
                refresh_dtcs.clear()

            reading = proto.read_data()
            live.update(build_dashboard(
                reading, dtcs,
                proto.protocol_name,
                actual_port,
                proto.is_connected(),
            ))
            time.sleep(0.5)

    proto.disconnect()
    console.print()
    console.print("[dim]OBD2 Monitor beendet.[/]")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="OBD2 SSH Live Monitor (Autocom CDP+)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--port", help="Serieller Port, z.B. /dev/ttyUSB0 (auto-detect wenn leer)")
    mode.add_argument("--tcp", metavar="HOST:PORT", help="ELM327 via TCP, z.B. 192.168.10.213:35000")
    parser.add_argument("--debug", action="store_true", help="Debug-Ausgabe aktivieren")
    args = parser.parse_args()

    run_monitor(args.port, args.tcp, args.debug)
