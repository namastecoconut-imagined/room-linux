"""The pixel display's Bluetooth protocol (iDotMatrix, 32 × 32): the bytes for each command and each picture.

Pure functions, the same bytes as pixelcontrol.html (the web app this was ported from). Every message starts with its
own length, little-endian. A still goes up as a plain 8-bit RGB PNG, an animation as a GIF with one palette for all its
frames (the display reloads colours per frame otherwise, and flickers). LEDs show dark and mid tones brighter than a
screen does, so pictures and colours are corrected (tune) before they're sent.
"""
import struct
import zlib

SERVICE = "{000000fa-0000-1000-8000-00805f9b34fb}"
WRITE = "{0000fa02-0000-1000-8000-00805f9b34fb}"
READ = "{0000fa03-0000-1000-8000-00805f9b34fb}"
CHUNK = 4096
N = 32
PALETTE = ["#ffffff", "#ff4d2e", "#ff9f1c", "#ffd23f", "#3ddc84", "#2ec4ff", "#3a5bff", "#9b5de5", "#ff5ea8", "#8a8f93", "#000000"]


def _clamp(v, a, b):
    return max(a, min(b, int(v)))


def rgb(colour):
    """'#rrggbb' → (r, g, b)"""
    return tuple(int(colour[i:i + 2], 16) for i in (1, 3, 5))


# ---- commands
def power(on): return bytes([5, 0, 7, 1, 1 if on else 0])
def brightness(pct): return bytes([5, 0, 4, 128, _clamp(pct, 5, 100)])
def flip(on): return bytes([5, 0, 6, 128, 1 if on else 0])
def colour(r, g, b): return bytes([7, 0, 2, 2, r, g, b])
def image_mode(): return bytes([5, 0, 4, 1, 1])


def effect(style, colours):
    flat = [v for c in colours for v in c]
    return bytes([6 + len(colours), 0, 3, 2, style, 90, len(colours), *flat])


def set_time(t):
    """t: time.struct_time (local). The display forgets its clock when unplugged; its answer carries its details."""
    return bytes([11, 0, 1, 128, t.tm_year % 100, t.tm_mon, t.tm_mday, t.tm_wday + 1, t.tm_hour, t.tm_min, t.tm_sec])


def clock(style, date, h24, r, g, b):
    return bytes([8, 0, 6, 1, _clamp(style, 0, 7) | (128 if date else 0) | (64 if h24 else 0), r, g, b])


def eco(on, start, end, light):
    """Night dimming, by the display itself: from start to end (minutes into the day) at light %."""
    return bytes([10, 0, 2, 128, 1 if on else 0, start // 60 % 24, start % 60, end // 60 % 24, end % 60, _clamp(light, 0, 100)])


def is_brightness_ack(d): return len(d) >= 5 and d[0] == 5 and d[2] == 4 and d[3] == 128


# the display's own timers and scoreboard (they keep running by themselves)
def countdown(mode, minutes, seconds):
    """mode: 0 off · 1 start · 2 pause · 3 resume"""
    return bytes([7, 0, 8, 128, mode, _clamp(minutes, 0, 99), _clamp(seconds, 0, 59)])


def chrono(mode):
    """mode: 0 reset · 1 start · 2 pause · 3 continue"""
    return bytes([5, 0, 9, 128, mode])


def score(a, b):
    a, b = _clamp(a, 0, 999), _clamp(b, 0, 999)
    return bytes([8, 0, 10, 128, a & 255, a >> 8, b & 255, b >> 8])


# ---- what it says back
def is_upload_ack(d): return len(d) >= 5 and d[0] == 5 and d[1] == 0 and d[3] == 0 and d[2] <= 2


def details(d):
    """The answer to set_time: firmware, screen size, whether it's locked — or None."""
    if len(d) >= 9 and d[2] == 1 and d[3] == 128:
        return {"firmware": f"{d[4]}.{d[5]:02d}", "size": {1: 16, 3: 32, 4: 64}.get(d[7], 0), "locked": d[8] == 1}
    return None


# ---- pictures
def png_payloads(data):
    count = -(-len(data) // CHUNK)
    head = struct.pack("<H", (len(data) + count) & 0xFFFF)
    return [head + bytes([0, 0, 2 if i else 0]) + struct.pack("<I", len(data)) + data[i:i + CHUNK]
            for i in range(0, len(data), CHUNK)]


def gif_payloads(data):
    total, crc = struct.pack("<I", len(data)), struct.pack("<I", zlib.crc32(data))
    out = []
    for i in range(0, len(data), CHUNK):
        piece = data[i:i + CHUNK]
        out.append(struct.pack("<H", len(piece) + 16) + bytes([1, 0, 2 if i else 0]) + total + crc + bytes([5, 0, 13]) + piece)
    return out


def png(rgba):
    """One frame (N*N*4 bytes, RGBA) as a plain 8-bit RGB PNG."""
    def chunk(kind, body):
        body = kind + body
        return struct.pack(">I", len(body) - 4) + body + struct.pack(">I", zlib.crc32(body))
    raw = bytearray()
    for y in range(N):
        raw.append(0)
        row = rgba[y * N * 4:(y + 1) * N * 4]
        for x in range(N):
            raw += row[x * 4:x * 4 + 3]
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", N, N, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b""))


def _lzw(indices):
    """GIF's LZW at 8 bits a pixel, in sub-blocks."""
    clear, end = 256, 257
    out, acc, nbits, size = bytearray(), 0, 0, 9

    def emit(code):
        nonlocal acc, nbits
        acc |= code << nbits
        nbits += size
        while nbits >= 8:
            out.append(acc & 255)
            acc >>= 8
            nbits -= 8
    table, nxt = {}, 258
    emit(clear)
    w = indices[0]
    for c in indices[1:]:
        key = (w << 8) | c
        if key in table:
            w = table[key]
            continue
        emit(w)
        if nxt < 4096:
            table[key] = nxt
            if nxt == (1 << size) and size < 12:
                size += 1
            nxt += 1
        else:                               # table full: start again
            emit(clear)
            table, nxt, size = {}, 258, 9
        w = c
    emit(w)
    emit(end)
    if nbits:
        out.append(acc & 255)
    blocks = bytearray([8])
    for i in range(0, len(out), 255):
        piece = out[i:i + 255]
        blocks.append(len(piece))
        blocks += piece
    blocks.append(0)
    return bytes(blocks)


def gif(frames, delay_ms):
    """Frames (each N*N*4 RGBA bytes) as a looping GIF: one palette for them all, each frame drawn over the last.
    delay_ms: one number for every frame, or a list with one for each."""
    shift = 0
    while True:                             # at most 256 colours: drop low bits until they fit (art is one hue: it fits)
        seen = {}
        for f in frames:
            for i in range(0, len(f), 4):
                seen.setdefault((f[i] >> shift, f[i + 1] >> shift, f[i + 2] >> shift), len(seen))
        if len(seen) <= 256:
            break
        shift += 1
    bits = max(1, (max(2, len(seen)) - 1).bit_length())
    table = bytearray(3 * (1 << bits))
    for (r, g, b), i in seen.items():
        table[i * 3:i * 3 + 3] = bytes([min(255, r << shift), min(255, g << shift), min(255, b << shift)])
    out = bytearray(b"GIF89a" + struct.pack("<HHBBB", N, N, 0x80 | 0x70 | (bits - 1), 0, 0) + bytes(table))
    out += b"\x21\xff\x0bNETSCAPE2.0\x03\x01\x00\x00\x00"
    delays = delay_ms if isinstance(delay_ms, (list, tuple)) else [delay_ms] * len(frames)
    for f, ms in zip(frames, delays):
        cs = max(2, int(ms / 10 + 0.5))
        idx = bytes(seen[(f[i] >> shift, f[i + 1] >> shift, f[i + 2] >> shift)] for i in range(0, len(f), 4))
        out += b"\x21\xf9\x04\x04" + struct.pack("<H", cs) + b"\x00\x00"
        out += b"\x2c" + struct.pack("<HHHH", 0, 0, N, N) + b"\x00" + _lzw(idx)
    out += b"\x3b"
    return bytes(out)


# ---- colour correction (the web app's "Balanced": vividness 1.3, contrast curve 1.8)
TUNE = {"exp": 100, "gamma": 18, "lift": 0, "sat": 13, "r": 100, "g": 100, "b": 100}
TUNES = {"balanced": TUNE, "bright": dict(TUNE, exp=140, gamma=15, lift=4, sat=15), "deep": dict(TUNE, exp=110, gamma=22, sat=14),
         "off": dict(TUNE, gamma=10, sat=10)}


def _c255(v):
    return 0 if v < 0 else 255 if v > 255 else int(round(v))


class Tuner:
    def __init__(self, t=None):
        self.t = dict(TUNE, **(t or {}))
        g = self.t["gamma"] / 10
        self.curve = [int(round(255 * (i / 255) ** g)) for i in range(256)]

    def one(self, r, g, b):
        t = self.t
        s, e = t["sat"] / 10, t["exp"] / 100
        if s != 1:
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            r, g, b = lum + (r - lum) * s, lum + (g - lum) * s, lum + (b - lum) * s
        r, g, b = self.curve[_c255(r * e)], self.curve[_c255(g * e)], self.curve[_c255(b * e)]
        k = t["lift"]
        if k and r + g + b > 0:
            m = (255 - k) / 255
            r, g, b = (k + r * m if r else 0), (k + g * m if g else 0), (k + b * m if b else 0)
        return _c255(r * t["r"] / 100), _c255(g * t["g"] / 100), _c255(b * t["b"] / 100)

    def frame(self, rgba):
        out, memo = bytearray(len(rgba)), {}
        for i in range(0, len(rgba), 4):
            key = (rgba[i], rgba[i + 1], rgba[i + 2])
            c = memo.get(key)
            if c is None:
                c = memo[key] = self.one(*key)
            out[i], out[i + 1], out[i + 2], out[i + 3] = c[0], c[1], c[2], 255
        return bytes(out)
