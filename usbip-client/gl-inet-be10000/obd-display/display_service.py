#!/usr/bin/env python3
"""
OBD2 Display Service — GL.iNet GL-BE10000 (Slate 7 Pro)

Display:  2.8" Touchscreen, Querformat 320×240 px
          Framebuffer unter /dev/fb0 (RGB565)
          Auflösung via ENV-Variablen konfigurierbar:
            FB_WIDTH  (Standard: 320 — TODO: verify on hardware)
            FB_HEIGHT (Standard: 240 — TODO: verify on hardware)
Touch:    /dev/input/event* (Standard Linux-Eingabe-Subsystem)
OBD-API:  http://127.0.0.1:8765 (obd_service.py auf diesem Router)

PROTOTYPE: Display-Auflösung noch nicht auf echter Hardware verifiziert.
           Bei falscher Darstellung: FB_WIDTH / FB_HEIGHT anpassen.

Unterschied zu GL-E5800:
  - DISPLAY_W=320, DISPLAY_H=240 (Querformat statt Hochformat)
  - Kein 5G Modem → Status-Screen ohne Modem-Anzeige
  - Kein gl_screen zu erwarten (TODO: verify on hardware)

4 Bildschirme (Tap = weiterschalten):
  0 — Status-Übersicht  (WiFi, OBD, USB/IP)
  1 — OBD Live (RPM, Speed, Temperatur)
  2 — Kraftstoff / Batterie
  3 — Steuerung (Adapter binden, OBD-Service neu starten)
"""

import os, sys, time, struct, json, select, threading, subprocess
from urllib.request import urlopen
from urllib.error import URLError

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print('[display] FEHLER: Pillow nicht installiert.', file=sys.stderr)
    print('[display] Installieren: /opt/obd-venv/bin/pip install Pillow', file=sys.stderr)
    sys.exit(1)

# ── Konstanten ───────────────────────────────────────────────────────────────
# GL-BE10000: 2.8" Display, Querformat 320×240
# TODO: verify on hardware — cat /sys/class/graphics/fb0/virtual_size
DISPLAY_W       = int(os.environ.get('FB_WIDTH',  320))
DISPLAY_H       = int(os.environ.get('FB_HEIGHT', 240))
FB_PATH         = os.environ.get('FB_PATH', '/dev/fb0')
OBD_API         = 'http://127.0.0.1:8765'
REFRESH_HZ      = 1.0

# Linux Input Event — AArch64 (64-Bit): struct input_event = 24 Bytes
INPUT_EVENT_SIZE = 24
INPUT_EVENT_FMT  = 'qqHHi'
EV_SYN    = 0x00
EV_KEY    = 0x01
EV_ABS    = 0x03
BTN_TOUCH = 0x14a
ABS_X     = 0x00
ABS_Y     = 0x01

# Farbpalette
BLACK  = (0,   0,   0)
WHITE  = (255, 255, 255)
GRAY   = (100, 100, 100)
LGRAY  = (180, 180, 180)
GREEN  = (50,  200,  50)
RED    = (220,  50,  50)
BLUE   = (50,  100, 220)

# Bildschirm-IDs
SCR_STATUS   = 0
SCR_OBD      = 1
SCR_FUEL     = 2
SCR_CONTROLS = 3
NUM_SCREENS  = 4


# ── OBD2-Daten-Abfrage (Hintergrund-Thread) ──────────────────────────────────
class OBDClient:
    def __init__(self):
        self.status: dict = {'connected': False, 'protocol': None, 'port': None, 'error': None}
        self.data:   dict = {}
        self._lock = threading.Lock()
        self._stop = threading.Event()

    def start(self):
        threading.Thread(target=self._poll_loop, daemon=True, name='obd-poll').start()

    def stop(self):
        self._stop.set()

    def get(self) -> tuple:
        with self._lock:
            return dict(self.status), dict(self.data)

    def _fetch(self, path: str) -> dict:
        resp = urlopen(f'{OBD_API}{path}', timeout=2)
        return json.loads(resp.read())

    def _poll_loop(self):
        while not self._stop.is_set():
            try:
                status = self._fetch('/obd/status')
                data   = self._fetch('/obd/data')
                with self._lock:
                    self.status = status
                    self.data   = data
            except Exception as e:
                with self._lock:
                    self.status = {'connected': False, 'protocol': None, 'port': None,
                                   'error': str(e)[:60]}
            self._stop.wait(REFRESH_HZ)


# ── Framebuffer-Schreiber ────────────────────────────────────────────────────
def pil_to_rgb565(img: Image.Image) -> bytes:
    """Konvertiert PIL-Image (RGB) zu RGB565-Byte-Stream für /dev/fb0."""
    img = img.convert('RGB')
    buf = bytearray(DISPLAY_W * DISPLAY_H * 2)
    px  = img.load()
    idx = 0
    for y in range(DISPLAY_H):
        for x in range(DISPLAY_W):
            r, g, b = px[x, y]
            rgb565  = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
            struct.pack_into('<H', buf, idx, rgb565)
            idx += 2
    return bytes(buf)


def write_fb(img: Image.Image, fb_path: str = FB_PATH):
    try:
        data = pil_to_rgb565(img)
        with open(fb_path, 'wb') as f:
            f.write(data)
    except OSError as e:
        print(f'[display] FB-Schreib-Fehler: {e}', file=sys.stderr)


def clear_fb():
    try:
        with open(FB_PATH, 'wb') as f:
            f.write(b'\x00' * (DISPLAY_W * DISPLAY_H * 2))
    except OSError:
        pass


# ── Touch-Eingabe (Hintergrund-Thread) ───────────────────────────────────────
class TouchReader:
    _SEARCH_DEVS = [f'/dev/input/event{i}' for i in range(8)]

    def __init__(self, on_tap, on_long_press=None):
        self.on_tap        = on_tap
        self.on_long_press = on_long_press
        self._stop         = threading.Event()
        self._touch_down_t = 0.0
        # Im Querformat: Y-Koordinate für Screen-Wechsel in X-Richtung
        self._touch_x      = DISPLAY_W // 2

    def start(self):
        threading.Thread(target=self._loop, daemon=True, name='touch').start()

    def stop(self):
        self._stop.set()

    def _find_device(self) -> str | None:
        for dev in self._SEARCH_DEVS:
            if os.path.exists(dev):
                return dev
        return None

    def _loop(self):
        dev = self._find_device()
        if not dev:
            print('[display] Touch: Kein /dev/input/event* gefunden', file=sys.stderr)
            return
        try:
            fd = open(dev, 'rb')
        except OSError as e:
            print(f'[display] Touch: {dev} nicht lesbar: {e}', file=sys.stderr)
            return

        print(f'[display] Touch-Eingabe: {dev}')

        while not self._stop.is_set():
            try:
                ready, _, _ = select.select([fd], [], [], 0.1)
                if not ready:
                    continue
                raw = fd.read(INPUT_EVENT_SIZE)
                if len(raw) < INPUT_EVENT_SIZE:
                    continue
                _, _, ev_type, ev_code, ev_val = struct.unpack(INPUT_EVENT_FMT, raw)
                self._handle_event(ev_type, ev_code, ev_val)
            except Exception as e:
                print(f'[display] Touch-Fehler: {e}', file=sys.stderr)
                time.sleep(0.2)
        fd.close()

    def _handle_event(self, ev_type: int, ev_code: int, ev_val: int):
        if ev_type == EV_ABS and ev_code == ABS_X:
            self._touch_x = ev_val

        elif ev_type == EV_KEY and ev_code == BTN_TOUCH:
            if ev_val == 1:
                self._touch_down_t = time.monotonic()
            elif ev_val == 0:
                duration = time.monotonic() - self._touch_down_t
                if 0.0 < duration < 0.5:
                    self.on_tap(self._touch_x)
                elif duration >= 1.0 and self.on_long_press:
                    self.on_long_press(self._touch_x)

        elif ev_type == EV_KEY and ev_val == 1:
            if   ev_code in (0x67, 0x103):
                self.on_tap(10)
            elif ev_code in (0x6c, 0x69):
                self.on_tap(DISPLAY_W - 10)
            elif ev_code in (0x1c, 0x160, 0x8b):
                self.on_tap(DISPLAY_W // 2)


# ── UI-Renderer (Querformat 320×240) ─────────────────────────────────────────
class DisplayUI:
    # GL-BE10000: 320×240 → min(320,240)/240 = 1.0 (keine Skalierung nötig)
    _SCALE = max(1.0, min(DISPLAY_W, DISPLAY_H) / 240.0)

    def __init__(self):
        self.screen = SCR_STATUS
        self._load_fonts()

    def _load_fonts(self):
        s = self._SCALE
        try:
            self.fs  = ImageFont.load_default(size=int(10 * s))
            self.fm  = ImageFont.load_default(size=int(12 * s))
            self.fl  = ImageFont.load_default(size=int(16 * s))
            self.fxl = ImageFont.load_default(size=int(32 * s))
        except TypeError:
            f = ImageFont.load_default()
            self.fs = self.fm = self.fl = self.fxl = f

    def on_tap(self, touch_x: int):
        if self.screen == SCR_CONTROLS:
            zone_w = (DISPLAY_W - 20) // 3
            zone = (touch_x - 20) // zone_w
            if   zone == 0: self._cmd_bind_adapter()
            elif zone == 1: self._cmd_restart_obd()
            else:           self.screen = SCR_STATUS
        else:
            self.screen = (self.screen + 1) % NUM_SCREENS

    def on_long_press(self, touch_x: int):
        self.screen = SCR_CONTROLS

    @staticmethod
    def _cmd_bind_adapter():
        vendor = '0403'; product = 'd6da'
        try:
            with open('/etc/obd-adapter.conf') as f:
                for line in f:
                    if line.startswith('ADAPTER_VENDOR='):
                        vendor = line.split('=')[1].strip().strip('"')
                    elif line.startswith('ADAPTER_PRODUCT='):
                        product = line.split('=')[1].strip().strip('"')
        except OSError:
            pass
        try:
            out = subprocess.check_output(['usbip', 'list', '-l'], timeout=3, text=True)
            for line in out.splitlines():
                if f'{vendor}:{product}' in line and 'busid' in line:
                    busid = line.split('busid')[1].strip().split()[0]
                    subprocess.run(['usbip', 'bind', '-b', busid],
                                   capture_output=True, timeout=5)
                    break
        except Exception as e:
            print(f'[display] bind Adapter: {e}', file=sys.stderr)

    @staticmethod
    def _cmd_restart_obd():
        try:
            subprocess.run(['/etc/init.d/obd-monitor', 'restart'],
                           capture_output=True, timeout=10)
        except Exception as e:
            print(f'[display] restart obd: {e}', file=sys.stderr)

    def _header(self, d: ImageDraw.ImageDraw, text: str) -> int:
        """Querformat-Header: oben, volle Breite."""
        hh = int(18 * self._SCALE)
        d.rectangle([0, 0, DISPLAY_W - 1, hh], fill=WHITE)
        tw = self._tw(d, text, self.fm)
        d.text(((DISPLAY_W - tw) // 2, 3), text, font=self.fm, fill=BLACK)
        return hh + 2

    def _sep_h(self, d: ImageDraw.ImageDraw, y: int):
        d.line([(0, y), (DISPLAY_W, y)], fill=GRAY, width=1)

    def _sep_v(self, d: ImageDraw.ImageDraw, x: int, y0: int, y1: int):
        d.line([(x, y0), (x, y1)], fill=GRAY, width=1)

    def _screen_dots(self, d: ImageDraw.ImageDraw):
        dots = ''.join('● ' if i == self.screen else '○ ' for i in range(NUM_SCREENS))
        d.text((DISPLAY_W - int(len(dots.strip()) * 6 + 4), DISPLAY_H - int(12 * self._SCALE)),
               dots.strip(), font=self.fs, fill=GRAY)

    @staticmethod
    def _tw(d: ImageDraw.ImageDraw, text: str, font) -> int:
        try:
            bb = d.textbbox((0, 0), text, font=font)
            return bb[2] - bb[0]
        except AttributeError:
            return len(text) * 6

    @staticmethod
    def _fmt(data: dict, key: str, fmt: str, fallback: str = '---') -> str:
        v = data.get(key)
        if v is None:
            return fallback
        try:
            return fmt.format(v)
        except (ValueError, TypeError):
            return fallback

    @staticmethod
    def _wifi_ip() -> str | None:
        try:
            import socket
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(('8.8.8.8', 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except Exception:
            return None

    @staticmethod
    def _usbip_ok() -> bool:
        try:
            r = subprocess.run(['usbip', 'list', '-l'],
                               capture_output=True, timeout=2)
            return b'0403:d6da' in r.stdout
        except Exception:
            return False

    def _render_status(self, status: dict, data: dict) -> Image.Image:
        """Querformat-Status: Links Netzwerk/USB, Rechts OBD-Daten."""
        img = Image.new('RGB', (DISPLAY_W, DISPLAY_H), BLACK)
        d   = ImageDraw.Draw(img)
        y   = 0

        y += self._header(d, 'GL-BE10000 OBD') + 2
        lh  = int(14 * self._SCALE)

        # Linke Spalte: Verbindungsstatus
        x_mid = DISPLAY_W // 2
        col_r = x_mid + 4
        lh = int(13 * self._SCALE)

        ip      = self._wifi_ip()
        ok_sym  = lambda ok: ('✓' if ok else '✗')
        ok_col  = lambda ok: (GREEN if ok else GRAY)

        yl = y
        d.text((2, yl), 'WiFi', font=self.fs, fill=LGRAY)
        d.text((40, yl), ok_sym(bool(ip)), font=self.fm, fill=ok_col(bool(ip)))
        if ip:
            d.text((56, yl), f'.{ip.split(".")[-1]}', font=self.fs, fill=GRAY)
        yl += lh

        obd_ok   = status.get('connected', False)
        usbip_ok = self._usbip_ok()
        proto    = (status.get('protocol') or '')[:8]

        d.text((2, yl), 'OBD', font=self.fs, fill=LGRAY)
        d.text((40, yl), ok_sym(obd_ok), font=self.fm, fill=ok_col(obd_ok))
        if proto:
            d.text((56, yl), proto, font=self.fs, fill=GRAY)
        yl += lh

        d.text((2, yl), 'USB', font=self.fs, fill=LGRAY)
        d.text((40, yl), ok_sym(usbip_ok), font=self.fm, fill=ok_col(usbip_ok))
        yl += lh

        # Separator vertikal
        self._sep_v(d, x_mid - 2, y, DISPLAY_H - 15)

        # Rechte Spalte: Live-Daten
        yr = y
        rows = [
            ('RPM', self._fmt(data, 'rpm',             '{:.0f}')),
            ('SPD', self._fmt(data, 'speed',           '{:.0f}') + ' km/h'),
            ('TMP', self._fmt(data, 'coolant_temp',    '{:.0f}') + '\u00b0C'),
            ('BAT', self._fmt(data, 'battery_voltage', '{:.1f}') + 'V'),
            ('LOD', self._fmt(data, 'engine_load',     '{:.0f}') + '%'),
            ('THR', self._fmt(data, 'throttle',        '{:.0f}') + '%'),
        ]
        for label, val in rows:
            d.text((col_r, yr), label, font=self.fs, fill=GRAY)
            tw = self._tw(d, val, self.fs)
            d.text((DISPLAY_W - tw - 2, yr), val, font=self.fs, fill=WHITE)
            yr += lh

        self._screen_dots(d)
        return img

    def _render_obd(self, status: dict, data: dict) -> Image.Image:
        """Querformat OBD-Live: 3 große Werte nebeneinander."""
        img = Image.new('RGB', (DISPLAY_W, DISPLAY_H), BLACK)
        d   = ImageDraw.Draw(img)
        y   = 0

        y += self._header(d, 'OBD LIVE') + 4

        col_w = DISPLAY_W // 3
        cols = [
            ('RPM', 'rpm', 'rpm'),
            ('SPEED', 'speed', 'km/h'),
            ('COOL', 'coolant_temp', '\u00b0C'),
        ]

        for i, (label, key, unit) in enumerate(cols):
            cx = i * col_w
            self._sep_v(d, cx + col_w - 1, y, DISPLAY_H - 14)
            # Label
            lw = self._tw(d, label, self.fs)
            d.text((cx + (col_w - lw) // 2, y), label, font=self.fs, fill=GRAY)
            # Wert
            val = self._fmt(data, key, '{:.0f}')
            vw = self._tw(d, val, self.fxl)
            vy = y + int(14 * self._SCALE)
            d.text((cx + max(0, (col_w - vw) // 2), vy), val, font=self.fxl, fill=WHITE)
            # Einheit
            uw = self._tw(d, unit, self.fs)
            d.text((cx + (col_w - uw) // 2, vy + int(36 * self._SCALE)), unit, font=self.fs, fill=GRAY)

        self._screen_dots(d)
        return img

    def _render_fuel(self, status: dict, data: dict) -> Image.Image:
        img = Image.new('RGB', (DISPLAY_W, DISPLAY_H), BLACK)
        d   = ImageDraw.Draw(img)
        y   = 0
        lh  = int(14 * self._SCALE)

        y += self._header(d, 'FUEL / BAT') + 4
        self._sep_h(d, y); y += 4

        def row(label: str, key: str, unit: str, fmt: str = '{:.1f}'):
            nonlocal y
            d.text((2, y), label, font=self.fs, fill=GRAY)
            val = self._fmt(data, key, fmt) + unit
            tw  = self._tw(d, val, self.fs)
            d.text((DISPLAY_W - tw - 2, y), val, font=self.fs, fill=WHITE)
            y += lh

        row('SHORT TRIM', 'short_fuel_trim', '%', '{:+.1f}')
        row('LONG TRIM',  'long_fuel_trim',  '%', '{:+.1f}')
        self._sep_h(d, y); y += 4
        row('ENGINE LOAD', 'engine_load',    '%', '{:.0f}')
        row('THROTTLE',    'throttle',       '%', '{:.0f}')
        self._sep_h(d, y); y += 4
        row('BATTERY',     'battery_voltage','V', '{:.1f}')
        self._sep_h(d, y); y += 6

        thr = data.get('throttle')
        if thr is not None:
            d.text((2, y), 'THR', font=self.fs, fill=GRAY); y += lh
            bar_max = DISPLAY_W - 4
            bar_w   = max(1, int((float(thr) / 100.0) * bar_max))
            d.rectangle([2, y, 2 + bar_w, y + int(10 * self._SCALE)], fill=WHITE)
            d.rectangle([2, y, DISPLAY_W - 2, y + int(10 * self._SCALE)], outline=GRAY, width=1)
            d.text((4, y), f'{thr:.0f}%', font=self.fs, fill=BLACK if bar_w > 20 else GRAY)

        self._screen_dots(d)
        return img

    def _render_controls(self, status: dict, data: dict) -> Image.Image:
        """Querformat-Controls: 3 Schaltflächen nebeneinander."""
        img = Image.new('RGB', (DISPLAY_W, DISPLAY_H), BLACK)
        d   = ImageDraw.Draw(img)

        hh = self._header(d, 'STEUERUNG')
        zone_w = (DISPLAY_W - 20) // 3
        zones  = [
            ('USB', 'BIND', 'Adapter'),
            ('OBD', 'RST',  'Restart'),
            ('\u2190', 'ZRK', 'Zurück'),
        ]

        for i, (icon, title, subtitle) in enumerate(zones):
            x0 = 10 + i * (zone_w + 2)
            x1 = x0 + zone_w - 2
            d.rectangle([x0, hh + 4, x1, DISPLAY_H - 14], outline=WHITE, width=1)
            yc = hh + 4 + (DISPLAY_H - 14 - hh - 4 - int(28 * self._SCALE)) // 2
            iw = self._tw(d, icon, self.fl)
            tw = self._tw(d, title, self.fm)
            d.text((x0 + (zone_w - iw) // 2, yc),               icon,  font=self.fl, fill=WHITE)
            d.text((x0 + (zone_w - tw) // 2, yc + int(18 * self._SCALE)), title, font=self.fm, fill=LGRAY)

        d.text((2, DISPLAY_H - int(12 * self._SCALE)), 'tap = aktion', font=self.fs, fill=GRAY)
        return img

    def render(self, status: dict, data: dict) -> Image.Image:
        try:
            if   self.screen == SCR_STATUS:   return self._render_status(status, data)
            elif self.screen == SCR_OBD:      return self._render_obd(status, data)
            elif self.screen == SCR_FUEL:     return self._render_fuel(status, data)
            elif self.screen == SCR_CONTROLS: return self._render_controls(status, data)
        except Exception as e:
            img = Image.new('RGB', (DISPLAY_W, DISPLAY_H), BLACK)
            d   = ImageDraw.Draw(img)
            d.text((2, 2), 'RENDER ERR', font=ImageFont.load_default(), fill=WHITE)
            d.text((2, 14), str(e)[:20], font=ImageFont.load_default(), fill=GRAY)
            return img
        return self._render_status(status, data)


# ── GL-Screen Daemon Handling (optional, graceful) ────────────────────────────
def _stop_gl_screen():
    gl_screen = '/etc/init.d/gl_screen'
    if os.path.exists(gl_screen):
        subprocess.run([gl_screen, 'stop'], capture_output=True, timeout=5)
    else:
        # TODO: verify on hardware — gl_screen auf BE10000 vorhanden?
        print('[display] Kein gl_screen-Daemon gefunden (BE10000 — normal)', file=sys.stderr)


def _start_gl_screen():
    gl_screen = '/etc/init.d/gl_screen'
    if os.path.exists(gl_screen):
        subprocess.run([gl_screen, 'start'], capture_output=True, timeout=5)


# ── Haupt-Programm ───────────────────────────────────────────────────────────
def main():
    print(f'[display] GL-BE10000 (Slate 7 Pro) OBD2 Display startet... [PROTOTYPE]')
    print(f'[display] Framebuffer: {FB_PATH}  ({DISPLAY_W}×{DISPLAY_H}px, RGB565, Querformat)')
    print(f'[display] OBD-API:     {OBD_API}')
    print(f'[display] Auflösung aus ENV: FB_WIDTH={DISPLAY_W}, FB_HEIGHT={DISPLAY_H}')
    print(f'[display] TODO: verify on hardware — Auflösung per /sys/class/graphics/fb0/virtual_size prüfen')

    if not os.path.exists(FB_PATH):
        print(f'[display] FEHLER: {FB_PATH} nicht gefunden — kein Framebuffer?', file=sys.stderr)
        sys.exit(1)

    print('[display] Stoppe gl_screen (falls vorhanden)...')
    _stop_gl_screen()
    time.sleep(0.5)
    clear_fb()

    obd   = OBDClient()
    ui    = DisplayUI()
    touch = TouchReader(on_tap=ui.on_tap, on_long_press=ui.on_long_press)

    obd.start()
    touch.start()

    print('[display] Läuft. Tap auf Display zum Weiterschalten.')

    try:
        while True:
            status, data = obd.get()
            img = ui.render(status, data)
            write_fb(img)
            time.sleep(REFRESH_HZ)

    except KeyboardInterrupt:
        print('\n[display] Gestoppt (SIGINT).')
    finally:
        obd.stop()
        touch.stop()
        clear_fb()
        print('[display] Starte gl_screen wieder (falls vorhanden)...')
        _start_gl_screen()
        print('[display] Fertig.')


if __name__ == '__main__':
    main()
