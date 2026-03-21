#!/usr/bin/env python3
"""
OBD2 Display Service — GL.iNet GL-BE3600 (Slate 7)

Display:  76 × 284 Pixel, RGB565-Framebuffer unter /dev/fb0
Touch:    /dev/input/event* (Standard Linux-Eingabe-Subsystem)
OBD-API:  http://127.0.0.1:8765 (obd_service.py auf diesem Router)

4 Bildschirme (Tap = weiterschalten):
  0 — Status-Übersicht  (WiFi, OBD, USB/IP, Mini-Daten)
  1 — OBD Live (RPM, Speed, Temperatur — große Zahlen)
  2 — Kraftstoff / Batterie (Fuel Trim, Load, Throttle-Balken)
  3 — Steuerung (CDP+ binden, OBD-Service neu starten)
"""

import os, sys, time, struct, json, select, threading, subprocess
from urllib.request import urlopen
from urllib.error import URLError

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print('[display] FEHLER: Pillow nicht installiert.', file=sys.stderr)
    print('[display] Installieren: pip3 install --target /mnt/usb/obd-pkgs Pillow', file=sys.stderr)
    sys.exit(1)

# ── Konstanten ───────────────────────────────────────────────────────────────
DISPLAY_W       = 76
DISPLAY_H       = 284
FB_PATH         = '/dev/fb0'
OBD_API         = 'http://127.0.0.1:8765'
REFRESH_HZ      = 1.0   # Sekunden zwischen Framebuffer-Updates

# Linux Input Event — AArch64 (64-Bit): struct input_event = 24 Bytes
# struct timeval: tv_sec(8B) + tv_usec(8B) = 16B; dann type(2) code(2) value(4)
INPUT_EVENT_SIZE = 24
INPUT_EVENT_FMT  = 'qqHHi'   # q=int64, H=uint16, i=int32

# Linux Input-Typen + Codes (relevant für Touch)
EV_SYN    = 0x00
EV_KEY    = 0x01
EV_ABS    = 0x03
BTN_TOUCH = 0x14a
ABS_X     = 0x00
ABS_Y     = 0x01

# Farbpalette (RGB888 — wird bei FB-Write zu RGB565 konvertiert)
BLACK  = (0,   0,   0)
WHITE  = (255, 255, 255)
GRAY   = (100, 100, 100)
LGRAY  = (180, 180, 180)

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
    """
    Liest Linux-Input-Events von /dev/input/event*.
    Unterstützt:
      - Vollständiger Touchscreen (EV_ABS + BTN_TOUCH)
      - Diskrete Taste-Knöpfe  (EV_KEY: UP/DOWN/ENTER)
    """
    _SEARCH_DEVS = [f'/dev/input/event{i}' for i in range(8)]

    def __init__(self, on_tap, on_long_press=None):
        self.on_tap        = on_tap
        self.on_long_press = on_long_press
        self._stop         = threading.Event()
        self._touch_down_t = 0.0
        self._touch_y      = DISPLAY_H // 2

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
        if ev_type == EV_ABS and ev_code == ABS_Y:
            self._touch_y = ev_val

        elif ev_type == EV_KEY and ev_code == BTN_TOUCH:
            if ev_val == 1:                         # Finger drauf
                self._touch_down_t = time.monotonic()
            elif ev_val == 0:                        # Finger weg
                duration = time.monotonic() - self._touch_down_t
                if 0.0 < duration < 0.5:
                    self.on_tap(self._touch_y)
                elif duration >= 1.0 and self.on_long_press:
                    self.on_long_press(self._touch_y)

        # Diskrete Tasten-Codes (falls GL-BE3600 Knöpfe statt Touchscreen hat)
        elif ev_type == EV_KEY and ev_val == 1:
            if   ev_code in (0x67, 0x103):          # KEY_UP / KEY_PAGEUP
                self.on_tap(10)
            elif ev_code in (0x6c, 0x69):           # KEY_DOWN / KEY_PAGEDOWN
                self.on_tap(DISPLAY_H - 10)
            elif ev_code in (0x1c, 0x160, 0x8b):    # KEY_ENTER / KEY_OK / KEY_MENU
                self.on_tap(DISPLAY_H // 2)


# ── UI-Renderer ──────────────────────────────────────────────────────────────
class DisplayUI:
    def __init__(self):
        self.screen = SCR_STATUS
        self._load_fonts()

    # ── Fonts laden (Pillow ≥10.1 oder Fallback) ─────────────────────────────
    def _load_fonts(self):
        try:
            self.fs  = ImageFont.load_default(size=9)   # Klein  (~9px hoch)
            self.fm  = ImageFont.load_default(size=11)  # Mittel (~11px hoch)
            self.fl  = ImageFont.load_default(size=14)  # Groß   (~14px hoch)
            self.fxl = ImageFont.load_default(size=26)  # XL     (~26px hoch)
        except TypeError:
            # Pillow < 10.1.0: kein size-Parameter
            f = ImageFont.load_default()
            self.fs = self.fm = self.fl = self.fxl = f

    # ── Touch-Handler ─────────────────────────────────────────────────────────
    def on_tap(self, touch_y: int):
        if self.screen == SCR_CONTROLS:
            zone_h = (DISPLAY_H - 18) // 3
            zone = (touch_y - 18) // zone_h
            if   zone == 0: self._cmd_bind_cdp()
            elif zone == 1: self._cmd_restart_obd()
            else:           self.screen = SCR_STATUS
        else:
            self.screen = (self.screen + 1) % NUM_SCREENS

    def on_long_press(self, touch_y: int):
        """Langer Druck (≥1s): direkt zur Steuerseite."""
        self.screen = SCR_CONTROLS

    # ── Aktionen ──────────────────────────────────────────────────────────────
    @staticmethod
    def _cmd_bind_cdp():
        try:
            subprocess.run(['usbip', 'bind', '-b', '1-1'],
                           capture_output=True, timeout=5)
        except Exception as e:
            print(f'[display] bind CDP+: {e}', file=sys.stderr)

    @staticmethod
    def _cmd_restart_obd():
        try:
            subprocess.run(['/etc/init.d/obd-monitor', 'restart'],
                           capture_output=True, timeout=10)
        except Exception as e:
            print(f'[display] restart obd: {e}', file=sys.stderr)

    # ── Hilfs-Zeichenfunktionen ───────────────────────────────────────────────
    def _header(self, d: ImageDraw.ImageDraw, text: str, y: int = 0):
        """Invertierter Titelbalken (weiß auf schwarz)."""
        d.rectangle([0, y, DISPLAY_W - 1, y + 15], fill=WHITE)
        tw = self._tw(d, text, self.fm)
        d.text(((DISPLAY_W - tw) // 2, y + 2), text, font=self.fm, fill=BLACK)

    def _sep(self, d: ImageDraw.ImageDraw, y: int):
        d.line([(1, y), (DISPLAY_W - 2, y)], fill=GRAY, width=1)

    def _screen_dots(self, d: ImageDraw.ImageDraw):
        """Bildschirm-Indikatoren unten."""
        dots = ''.join('● ' if i == self.screen else '○ ' for i in range(NUM_SCREENS))
        d.text((2, DISPLAY_H - 13), dots.strip(), font=self.fs, fill=GRAY)

    @staticmethod
    def _tw(d: ImageDraw.ImageDraw, text: str, font) -> int:
        """Textbreite in Pixel."""
        try:
            bb = d.textbbox((0, 0), text, font=font)
            return bb[2] - bb[0]
        except AttributeError:
            return len(text) * 6   # Fallback-Schätzung

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

    # ── Bildschirm 0 — Status-Übersicht ──────────────────────────────────────
    def _render_status(self, status: dict, data: dict) -> Image.Image:
        img = Image.new('RGB', (DISPLAY_W, DISPLAY_H), BLACK)
        d   = ImageDraw.Draw(img)
        y   = 0

        self._header(d, 'OBD MANAGER', y); y += 17
        self._sep(d, y); y += 4

        # Netzwerk
        ip = self._wifi_ip()
        ok_sym  = lambda ok: ('✓' if ok else '✗')
        ok_col  = lambda ok: (WHITE if ok else GRAY)

        d.text((2, y), f'WiFi {ok_sym(bool(ip))}', font=self.fs, fill=ok_col(bool(ip))); y += 12
        if ip:
            d.text((4, y), f'.{ip.split(".")[-1]}', font=self.fs, fill=GRAY); y += 12
        else:
            y += 12

        self._sep(d, y); y += 4

        # OBD + USB/IP
        obd_ok   = status.get('connected', False)
        proto    = (status.get('protocol') or '')[:9]
        usbip_ok = self._usbip_ok()

        d.text((2, y), f'OBD  {ok_sym(obd_ok)}', font=self.fs, fill=ok_col(obd_ok)); y += 12
        if proto:
            d.text((4, y), proto, font=self.fs, fill=GRAY); y += 11
        d.text((2, y), f'USB  {ok_sym(usbip_ok)} CDP+', font=self.fs, fill=ok_col(usbip_ok)); y += 12
        self._sep(d, y); y += 4

        # Live-Daten (kompakt)
        rows = [
            ('RPM', self._fmt(data, 'rpm',             '{:.0f}')),
            ('SPD', self._fmt(data, 'speed',           '{:.0f}') + ' km/h'),
            ('TMP', self._fmt(data, 'coolant_temp',    '{:.0f}') + '\u00b0C'),
            ('BAT', self._fmt(data, 'battery_voltage', '{:.1f}') + 'V'),
        ]
        for label, val in rows:
            d.text((2, y), f'{label}', font=self.fs, fill=GRAY)
            tw = self._tw(d, val, self.fs)
            d.text((DISPLAY_W - tw - 2, y), val, font=self.fs, fill=WHITE)
            y += 12

        self._sep(d, y); y += 4

        d.text((2, y), f'LOD {self._fmt(data, "engine_load", "{:.0f}")}%', font=self.fs, fill=GRAY); y += 11
        d.text((2, y), f'THR {self._fmt(data, "throttle",    "{:.0f}")}%', font=self.fs, fill=GRAY); y += 11

        self._screen_dots(d)
        d.text((DISPLAY_W // 2 - 10, DISPLAY_H - 13), 'tap▶', font=self.fs, fill=GRAY)
        return img

    # ── Bildschirm 1 — OBD Live (große Zahlen) ───────────────────────────────
    def _render_obd(self, status: dict, data: dict) -> Image.Image:
        img = Image.new('RGB', (DISPLAY_W, DISPLAY_H), BLACK)
        d   = ImageDraw.Draw(img)
        y   = 0

        self._header(d, 'OBD LIVE', y); y += 17

        def big_row(label: str, key: str, unit: str, fmt: str = '{:.0f}'):
            nonlocal y
            self._sep(d, y); y += 4
            d.text((2, y), label, font=self.fs, fill=GRAY); y += 11
            val  = self._fmt(data, key, fmt)
            tw   = self._tw(d, val, self.fxl)
            d.text(((DISPLAY_W - tw) // 2, y), val, font=self.fxl, fill=WHITE); y += 28
            d.text((2, y), unit, font=self.fs, fill=GRAY); y += 13

        big_row('RPM',     'rpm',          'rpm')
        big_row('SPEED',   'speed',        'km/h')
        big_row('COOLANT', 'coolant_temp', '\u00b0C')

        self._sep(d, y)
        self._screen_dots(d)
        return img

    # ── Bildschirm 2 — Kraftstoff & Batterie ─────────────────────────────────
    def _render_fuel(self, status: dict, data: dict) -> Image.Image:
        img = Image.new('RGB', (DISPLAY_W, DISPLAY_H), BLACK)
        d   = ImageDraw.Draw(img)
        y   = 0

        self._header(d, 'FUEL / BAT', y); y += 17
        self._sep(d, y); y += 4

        def row(label: str, key: str, unit: str, fmt: str = '{:.1f}'):
            nonlocal y
            d.text((2, y), label, font=self.fs, fill=GRAY)
            val = self._fmt(data, key, fmt) + unit
            tw  = self._tw(d, val, self.fs)
            d.text((DISPLAY_W - tw - 2, y), val, font=self.fs, fill=WHITE)
            y += 12

        row('SHORT TRM', 'short_fuel_trim', '%', '{:+.1f}')
        row('LONG TRM',  'long_fuel_trim',  '%', '{:+.1f}')
        self._sep(d, y); y += 4
        row('LOAD',      'engine_load',     '%', '{:.0f}')
        row('THROTTLE',  'throttle',        '%', '{:.0f}')
        self._sep(d, y); y += 4
        row('BATTERY',   'battery_voltage', 'V', '{:.1f}')
        self._sep(d, y); y += 6

        # Throttle-Balken
        thr = data.get('throttle')
        if thr is not None:
            d.text((2, y), 'THR', font=self.fs, fill=GRAY); y += 11
            bar_max = DISPLAY_W - 4
            bar_w   = max(1, int((float(thr) / 100.0) * bar_max))
            d.rectangle([2, y, 2 + bar_w, y + 9], fill=WHITE)
            d.rectangle([2, y, DISPLAY_W - 2, y + 9], outline=GRAY, width=1)
            d.text((4, y), f'{thr:.0f}%', font=self.fs, fill=BLACK if bar_w > 20 else GRAY)
            y += 13

        self._screen_dots(d)
        return img

    # ── Bildschirm 3 — Steuerung ──────────────────────────────────────────────
    def _render_controls(self, status: dict, data: dict) -> Image.Image:
        img = Image.new('RGB', (DISPLAY_W, DISPLAY_H), BLACK)
        d   = ImageDraw.Draw(img)

        self._header(d, 'STEUERUNG', 0)

        zone_h = (DISPLAY_H - 18) // 3
        zones  = [
            ('CDP+',    'BINDEN',    'USB/IP bind'),
            ('OBD',     'RESTART',   'Service neu'),
            ('\u2190',  'ZURUCK',    'Status'),
        ]

        for i, (icon, title, subtitle) in enumerate(zones):
            y0 = 18 + i * zone_h
            y1 = y0 + zone_h - 3
            yc = y0 + (zone_h - 28) // 2    # vertikal zentriert

            d.rectangle([2, y0 + 1, DISPLAY_W - 2, y1], outline=WHITE, width=1)

            # Icon oben, Titel darunter
            iw = self._tw(d, icon,  self.fl)
            tw = self._tw(d, title, self.fm)
            d.text(((DISPLAY_W - iw) // 2, yc),      icon,  font=self.fl, fill=WHITE)
            d.text(((DISPLAY_W - tw) // 2, yc + 16), title, font=self.fm, fill=LGRAY)

        d.text((2, DISPLAY_H - 13), 'tap = aktion', font=self.fs, fill=GRAY)
        return img

    # ── Öffentlicher Render-Einstiegspunkt ────────────────────────────────────
    def render(self, status: dict, data: dict) -> Image.Image:
        try:
            if   self.screen == SCR_STATUS:   return self._render_status(status, data)
            elif self.screen == SCR_OBD:      return self._render_obd(status, data)
            elif self.screen == SCR_FUEL:     return self._render_fuel(status, data)
            elif self.screen == SCR_CONTROLS: return self._render_controls(status, data)
        except Exception as e:
            # Fallback: Fehlermeldung anzeigen
            img = Image.new('RGB', (DISPLAY_W, DISPLAY_H), BLACK)
            d   = ImageDraw.Draw(img)
            d.text((2, 2), 'RENDER ERR', font=ImageFont.load_default(), fill=WHITE)
            d.text((2, 14), str(e)[:10], font=ImageFont.load_default(), fill=GRAY)
            return img
        return self._render_status(status, data)


# ── Haupt-Programm ───────────────────────────────────────────────────────────
def _stop_gl_screen():
    subprocess.run(['/etc/init.d/gl_screen', 'stop'], capture_output=True, timeout=5)

def _start_gl_screen():
    subprocess.run(['/etc/init.d/gl_screen', 'start'], capture_output=True, timeout=5)


def main():
    print('[display] GL-BE3600 OBD2 Display startet...')
    print(f'[display] Framebuffer: {FB_PATH}  ({DISPLAY_W}×{DISPLAY_H}px, RGB565)')
    print(f'[display] OBD-API:     {OBD_API}')

    if not os.path.exists(FB_PATH):
        print(f'[display] FEHLER: {FB_PATH} nicht gefunden — kein Framebuffer?', file=sys.stderr)
        sys.exit(1)

    # gl_screen anhalten (Framebuffer freigeben)
    print('[display] Stoppe gl_screen...')
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
        print('[display] Starte gl_screen wieder...')
        _start_gl_screen()
        print('[display] Fertig.')


if __name__ == '__main__':
    main()
