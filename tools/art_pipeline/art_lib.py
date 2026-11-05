#!/usr/bin/env python3
"""art_lib.py — shared code for the AI-assisted art pipeline (tools/art_pipeline/).

Python stdlib only and deterministic: the same input always gives the same bytes.

Nothing here reads a ROM. The style reference that `style_fit` and `originality` compare against is
a numbers-only file (`style_reference.json`) built on the human's machine by
`build_style_reference.py` and kept outside the repository.
"""

import colorsys
import hashlib
import json
import math
import os
import struct
import zlib

INK = (26, 26, 32)  # the stamps' 1-px outline colour, slice-2 plan §12.2 (master-palette mode)
SLATE = (66, 66, 82)  # free-palette fallback outline: dark, but not near-black (the target look avoids near-black)
TILE = 16  # art pixels per tile edge

# ---------------------------------------------------------------------------
# Images: RGBA, 8 bits per channel, row-major in one bytearray
# ---------------------------------------------------------------------------


class Image:
    __slots__ = ("w", "h", "px")

    def __init__(self, w, h, px=None):
        self.w, self.h = w, h
        self.px = px if px is not None else bytearray(w * h * 4)

    def get(self, x, y):
        i = (y * self.w + x) * 4
        p = self.px
        return (p[i], p[i + 1], p[i + 2], p[i + 3])

    def rgb(self, x, y):
        i = (y * self.w + x) * 4
        p = self.px
        return (p[i], p[i + 1], p[i + 2])

    def alpha(self, x, y):
        return self.px[(y * self.w + x) * 4 + 3]

    def opaque(self, x, y):
        return self.px[(y * self.w + x) * 4 + 3] >= 128

    def set(self, x, y, rgba):
        i = (y * self.w + x) * 4
        self.px[i:i + 4] = bytes(rgba)

    def copy(self):
        return Image(self.w, self.h, bytearray(self.px))

    def crop(self, x0, y0, x1, y1):
        out = Image(x1 - x0, y1 - y0)
        for y in range(y0, y1):
            s = (y * self.w + x0) * 4
            d = ((y - y0) * out.w) * 4
            out.px[d:d + out.w * 4] = self.px[s:s + out.w * 4]
        return out

    def scaled(self, k):
        """Nearest-neighbour upscale by an integer factor."""
        out = Image(self.w * k, self.h * k)
        for y in range(self.h):
            row = bytearray()
            for x in range(self.w):
                i = (y * self.w + x) * 4
                row.extend(self.px[i:i + 4] * k)
            for sy in range(k):
                d = ((y * k + sy) * out.w) * 4
                out.px[d:d + len(row)] = row
        return out

    def paste(self, src, ox, oy, only_opaque=True):
        for y in range(src.h):
            ty = oy + y
            if not 0 <= ty < self.h:
                continue
            for x in range(src.w):
                tx = ox + x
                if not 0 <= tx < self.w:
                    continue
                c = src.get(x, y)
                if only_opaque and c[3] < 128:
                    continue
                self.set(tx, ty, c)

    def fill(self, rgba):
        self.px[:] = bytes(rgba) * (self.w * self.h)

    def opaque_count(self):
        return sum(1 for i in range(3, len(self.px), 4) if self.px[i] >= 128)


# ---------------------------------------------------------------------------
# PNG reading and writing
# ---------------------------------------------------------------------------

PNG_SIG = b"\x89PNG\r\n\x1a\n"


def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def read_png(path):
    """Reads an 8- or 16-bit, non-interlaced PNG of any colour type into an RGBA Image."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != PNG_SIG:
        raise ValueError(
            "%s is not a PNG. Convert it first, for example: sips -s format png IN --out OUT.png" % path)
    pos, idat, plte, trns, ihdr = 8, [], None, None, None
    while pos + 8 <= len(data):
        (ln,) = struct.unpack(">I", data[pos:pos + 4])
        tag, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if tag == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", body)
        elif tag == b"PLTE":
            plte = body
        elif tag == b"tRNS":
            trns = body
        elif tag == b"IDAT":
            idat.append(body)
        elif tag == b"IEND":
            break
    if ihdr is None:
        raise ValueError("%s: no IHDR chunk" % path)
    w, h, depth, ctype, _c, _f, interlace = ihdr
    if interlace:
        raise ValueError("%s is interlaced. Re-save it without interlacing (sips -s format png IN --out OUT.png)" % path)
    if ctype == 3 and depth != 8 or ctype != 3 and depth not in (8, 16):
        raise ValueError("%s: unsupported bit depth %d for colour type %d" % (path, depth, ctype))
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    bpp = channels * (depth // 8)
    stride = w * bpp
    raw = zlib.decompress(b"".join(idat))
    img = Image(w, h)
    prev = bytearray(stride)
    p = 0
    out = img.px
    for y in range(h):
        ft = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        if ft == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                upleft = prev[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + _paeth(left, prev[i], upleft)) & 255
        prev = line
        src = line if depth == 8 else line[0::2]  # 16-bit: keep the high byte
        d = y * w * 4
        if ctype == 6:
            out[d:d + w * 4] = src
        elif ctype == 2:
            for x in range(w):
                out[d + x * 4:d + x * 4 + 4] = bytes((src[x * 3], src[x * 3 + 1], src[x * 3 + 2], 255))
        elif ctype == 0:
            for x in range(w):
                v = src[x]
                out[d + x * 4:d + x * 4 + 4] = bytes((v, v, v, 255))
        elif ctype == 4:
            for x in range(w):
                v = src[x * 2]
                out[d + x * 4:d + x * 4 + 4] = bytes((v, v, v, src[x * 2 + 1]))
        else:
            for x in range(w):
                k = src[x]
                r, g, b = plte[k * 3:k * 3 + 3]
                a = trns[k] if trns is not None and k < len(trns) else 255
                out[d + x * 4:d + x * 4 + 4] = bytes((r, g, b, a))
    return img


def write_png(path, img):
    """Writes an RGBA PNG (filter 0, deterministic)."""
    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
    raw = bytearray()
    for y in range(img.h):
        raw.append(0)
        raw.extend(img.px[y * img.w * 4:(y + 1) * img.w * 4])
    d = os.path.dirname(os.path.abspath(path))
    os.makedirs(d, exist_ok=True)
    with open(path, "wb") as f:
        f.write(PNG_SIG + chunk(b"IHDR", struct.pack(">IIBBBBB", img.w, img.h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


# ---------------------------------------------------------------------------
# Colour
# ---------------------------------------------------------------------------


def hexc(s):
    s = s.strip().lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


def hexs(c):
    return "#%02X%02X%02X" % tuple(c[:3])


def redmean(c1, c2):
    """A cheap perceptual RGB distance (0 to about 765)."""
    rm = (c1[0] + c2[0]) / 2.0
    dr, dg, db = c1[0] - c2[0], c1[1] - c2[1], c1[2] - c2[2]
    return math.sqrt((2 + rm / 256.0) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256.0) * db * db)


def hsv(c):
    return colorsys.rgb_to_hsv(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0)


def luma(c):
    return (0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]) / 255.0


def hue_diff(h1, h2):
    d = abs(h1 - h2) % 1.0
    return min(d, 1.0 - d) * 360.0


def to_gba(c):
    """Rounds a colour to the 15-bit (5 bits per channel) colour space of the target look."""
    out = []
    for v in c[:3]:
        v5 = int(round(v * 31 / 255.0))
        out.append((v5 << 3) | (v5 >> 2))
    return tuple(out)


def darkened(c, f):
    return (int(c[0] * f), int(c[1] * f), int(c[2] * f))


def key_affinity(c, key):
    """How strongly a pixel reads as the generation background (magenta or green)."""
    r, g, b = c[:3]
    if key == (255, 0, 255):
        return min(r, b) - g
    if key == (0, 255, 0):
        return g - max(r, b)
    return 255 - int(redmean(c, key) / 3)


def is_key_shade(c, key):
    """A saturated darker shade of the key. Where it touches the background it is a shadow or a fringe the model
    drew there (in the third re-run, the Library carried a dark magenta drop shadow, #52085A, that the converter
    kept as part of it); inside the object it may be real shading, such as a dark roof hole."""
    r, g, b = c[:3]
    if key == (255, 0, 255):
        hi = max(r, b)
        return hi >= 40 and min(r, b) - g >= 0.6 * hi and abs(r - b) <= 0.35 * hi
    if key == (0, 255, 0):
        return g >= 40 and g - max(r, b) >= 0.6 * g
    return False


def is_key(c, key):
    return redmean(c, key) < 110 or key_affinity(c, key) >= 100


def shadows_to_background(raw, key):
    """A copy of the generated image in which every shade of the key that is connected to the background (through
    other shades) becomes the key itself: a shadow or fringe on the background, not part of the object. Shades
    enclosed by the object are left alone. Returns (image, pixels changed)."""
    w, h = raw.w, raw.h
    px = raw.px
    bg = bytearray(w * h)
    shade = bytearray(w * h)
    stack = []
    for i in range(w * h):
        c = (px[4 * i], px[4 * i + 1], px[4 * i + 2], px[4 * i + 3])
        if c[3] < 128 or is_key(c, key):
            bg[i] = 1
        elif is_key_shade(c, key):
            shade[i] = 1
    for i in range(w * h):
        if shade[i]:
            x, y = i % w, i // w
            if (x > 0 and bg[i - 1]) or (x < w - 1 and bg[i + 1]) or (y > 0 and bg[i - w]) or (y < h - 1 and bg[i + w]):
                shade[i] = 2
                stack.append(i)
    while stack:
        i = stack.pop()
        x, y = i % w, i // w
        for j, ok in ((i - 1, x > 0), (i + 1, x < w - 1), (i - w, y > 0), (i + w, y < h - 1)):
            if ok and shade[j] == 1:
                shade[j] = 2
                stack.append(j)
    out = raw.copy()
    changed = 0
    kr, kg, kb = key
    for i in range(w * h):
        if shade[i] == 2:
            out.px[4 * i:4 * i + 4] = bytes((kr, kg, kb, 255))
            changed += 1
    return out, changed


def is_background(c, key):
    """Background: the key colour, or transparent (some local models write their own alpha)."""
    return c[3] < 128 or is_key(c, key)


def load_gpl(path):
    """Reads a GIMP palette: [(rgb, name)]."""
    out = []
    with open(path) as f:
        for line in f:
            s = line.strip()
            if not s or s[0] == "#" or s.startswith(("GIMP", "Name:", "Columns:")):
                continue
            parts = s.split()
            if len(parts) >= 3 and all(p.isdigit() for p in parts[:3]):
                out.append(((int(parts[0]), int(parts[1]), int(parts[2])), " ".join(parts[3:])))
    return out


# ---------------------------------------------------------------------------
# A tiny 3 x 5 font for contact-sheet labels (digits, lower-case letters, - _ . : / %)
# ---------------------------------------------------------------------------

_FONT = {
    "0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111",
    "4": "101101111001001", "5": "111100111001111", "6": "111100111101111", "7": "111001001001001",
    "8": "111101111101111", "9": "111101111001111", "a": "010101111101101", "b": "110101110101110",
    "c": "011100100100011", "d": "110101101101110", "e": "111100110100111", "f": "111100110100100",
    "g": "011100101101011", "h": "101101111101101", "i": "111010010010111", "j": "001001001101010",
    "k": "101101110101101", "l": "100100100100111", "m": "101111111101101", "n": "110101101101101",
    "o": "010101101101010", "p": "110101110100100", "q": "010101101110011", "r": "110101110101101",
    "s": "011100010001110", "t": "111010010010010", "u": "101101101101111", "v": "101101101101010",
    "w": "101101111111101", "x": "101101010101101", "y": "101101010010010", "z": "111001010100111",
    "-": "000000111000000", "_": "000000000000111", ".": "000000000000010", ":": "000010000010000",
    "/": "001001010100100", "%": "101001010100101", " ": "000000000000000",
}


def draw_text(img, x, y, text, rgba=(255, 255, 255, 255), scale=2):
    cx = x
    for ch in text.lower():
        glyph = _FONT.get(ch, _FONT[" "])
        for gy in range(5):
            for gx in range(3):
                if glyph[gy * 3 + gx] == "1":
                    for sy in range(scale):
                        for sx in range(scale):
                            px, py = cx + gx * scale + sx, y + gy * scale + sy
                            if 0 <= px < img.w and 0 <= py < img.h:
                                img.set(px, py, rgba)
        cx += 4 * scale
    return cx


def text_width(text, scale=2):
    return len(text) * 4 * scale


# ---------------------------------------------------------------------------
# Conversion: a large generated image -> a native sprite on the 16-px tile grid
# ---------------------------------------------------------------------------


class ConversionError(Exception):
    """The candidate can't become a valid sprite; the message says why."""


def _foreground_components(img, key, step):
    """Connected foreground regions on a grid sampled every `step` pixels (8-connected).
    Returns [(area_in_samples, (x0, y0, x1, y1) in full-resolution pixels)], largest first."""
    sw, sh = (img.w + step - 1) // step, (img.h + step - 1) // step
    fg = bytearray(sw * sh)
    for sy in range(sh):
        y = min(sy * step, img.h - 1)
        for sx in range(sw):
            x = min(sx * step, img.w - 1)
            c = img.get(x, y)
            if c[3] >= 128 and not is_key(c, key):
                fg[sy * sw + sx] = 1
    seen = bytearray(sw * sh)
    comps = []
    for start in range(sw * sh):
        if not fg[start] or seen[start]:
            continue
        stack = [start]
        seen[start] = 1
        area, x0, y0, x1, y1 = 0, sw, sh, -1, -1
        while stack:
            i = stack.pop()
            area += 1
            cx, cy = i % sw, i // sw
            x0, y0, x1, y1 = min(x0, cx), min(y0, cy), max(x1, cx), max(y1, cy)
            for dy in (-1, 0, 1):
                ny = cy + dy
                if not 0 <= ny < sh:
                    continue
                for dx in (-1, 0, 1):
                    nx = cx + dx
                    if 0 <= nx < sw:
                        j = ny * sw + nx
                        if fg[j] and not seen[j]:
                            seen[j] = 1
                            stack.append(j)
        comps.append((area, (x0 * step, y0 * step, min(img.w, (x1 + 1) * step), min(img.h, (y1 + 1) * step))))
    comps.sort(key=lambda c: (-c[0], c[1]))
    return comps


def _refine_bbox(img, key, bbox, step):
    """Tightens a sampled bounding box to the exact foreground pixels near its edges."""
    x0, y0, x1, y1 = bbox
    ex0, ey0 = max(0, x0 - step), max(0, y0 - step)
    ex1, ey1 = min(img.w, x1 + step), min(img.h, y1 + step)
    rx0, ry0, rx1, ry1 = ex1, ey1, ex0, ey0
    for y in range(ey0, ey1):
        for x in range(ex0, ex1):
            if (x - ex0 < 2 * step or ex1 - x <= 2 * step or y - ey0 < 2 * step or ey1 - y <= 2 * step):
                c = img.get(x, y)
                if c[3] >= 128 and not is_key(c, key):
                    rx0, ry0, rx1, ry1 = min(rx0, x), min(ry0, y), max(rx1, x + 1), max(ry1, y + 1)
    if rx1 <= rx0 or ry1 <= ry0:
        return bbox
    # the interior can only widen the box, never shrink it below the sampled one
    return (min(rx0, x0), min(ry0, y0), max(rx1, x1), max(ry1, y1))


def find_subject(img, key, allow_pieces=False):
    """The object's bounding box, plus any stray regions outside it (a watermark, text, a second
    object). A separate piece counts as part of the object when it lies inside the main shape's box or
    is large; with `allow_pieces` (scattered decals), also when it lies close by.
    Returns (bbox, strays, subject_area_fraction)."""
    step = max(1, int(round(max(img.w, img.h) / 512.0)))
    comps = _foreground_components(img, key, step)
    if not comps:
        raise ConversionError("no foreground: the image is all background colour")
    main_area, main_box = comps[0]
    bx0, by0, bx1, by1 = main_box
    grow_x, grow_y = 0.15 * (bx1 - bx0) + 2 * step, 0.15 * (by1 - by0) + 2 * step
    keep, strays = [main_box], []
    for area, box in comps[1:]:
        tol = 2 * step
        inside = (box[0] >= bx0 - tol and box[2] <= bx1 + tol and box[1] >= by0 - tol and box[3] <= by1 + tol)
        near = (box[0] >= bx0 - grow_x and box[2] <= bx1 + grow_x and box[1] >= by0 - grow_y and box[3] <= by1 + grow_y)
        if inside or area >= 0.25 * main_area or (allow_pieces and near):
            keep.append(box)
        elif area >= max(8, 0.0003 * main_area):
            strays.append({"bbox": box, "area_fraction_of_subject": round(area / float(main_area), 4)})
    x0 = min(b[0] for b in keep)
    y0 = min(b[1] for b in keep)
    x1 = max(b[2] for b in keep)
    y1 = max(b[3] for b in keep)
    total = sum(a for a, _ in comps)
    return _refine_bbox(img, key, (x0, y0, x1, y1), step), strays, main_area / float(total)


def background_report(raw, key, bbox, ring=0.02):
    """How cleanly the generation background surrounds the object. Returns (the share of the picture's
    outer ring, 2% of its size, that is background; the smallest gap between the object and an edge
    of the picture, as a fraction of that dimension). A painted backdrop or a copied layout diagram
    reaches the edge of the picture; a clean generation has background all round."""
    t = max(2, int(round(min(raw.w, raw.h) * ring)))
    n = bg = 0
    for y in range(0, raw.h, 2):
        edge_row = y < t or y >= raw.h - t
        for x in range(0, raw.w, 2):
            if not edge_row and t <= x < raw.w - t:
                continue
            n += 1
            bg += is_background(raw.get(x, y), key)
    x0, y0, x1, y1 = bbox
    margin = min(x0 / float(raw.w), y0 / float(raw.h), (raw.w - x1) / float(raw.w), (raw.h - y1) / float(raw.h))
    return round(bg / float(n), 4), round(margin, 4)


def _block_colour(img, key, sx0, sy0, sx1, sy1):
    """For one target pixel: foreground coverage of its source block, the dominant colour of the
    block's central half (so blurred block borders don't decide it), and how pure that block is."""
    n = fg = 0
    for y in range(sy0, sy1):
        for x in range(sx0, sx1):
            n += 1
            c = img.get(x, y)
            if c[3] >= 128 and not is_key(c, key):
                fg += 1
    if n == 0:
        return 0.0, None, 0.0
    cov = fg / float(n)
    bw, bh = sx1 - sx0, sy1 - sy0
    cx0 = sx0 + bw // 4
    cx1 = max(cx0 + 1, sx1 - bw // 4)
    cy0 = sy0 + bh // 4
    cy1 = max(cy0 + 1, sy1 - bh // 4)
    buckets = {}
    members = []
    for y in range(cy0, cy1):
        for x in range(cx0, cx1):
            c = img.get(x, y)
            if c[3] < 128 or is_key(c, key):
                continue
            k = (c[0] >> 4, c[1] >> 4, c[2] >> 4)
            buckets.setdefault(k, []).append(c)
            members.append(c)
    if not members:
        return cov, None, 0.0
    best = sorted(buckets.items(), key=lambda kv: (-len(kv[1]), kv[0]))[0][1]
    r = sum(c[0] for c in best) // len(best)
    g = sum(c[1] for c in best) // len(best)
    b = sum(c[2] for c in best) // len(best)
    rep = (r, g, b)
    pure = sum(1 for c in members if redmean(c, rep) <= 48) / float(len(members))
    return cov, rep, pure


def downsample(img, key, bbox, w, h, fit="fill", margin=0):
    """Maps the subject's bounding box onto a w x h sprite. `fill` stretches it to the whole
    sprite; `contain` keeps its proportions inside a margin, centred horizontally and resting on the
    bottom edge. Returns (sprite, mean block purity)."""
    x0, y0, x1, y1 = bbox
    bw, bh = x1 - x0, y1 - y0
    if fit == "fill":
        dx0, dy0, dw, dh = 0, 0, w, h
    else:
        s = min((w - 2 * margin) / float(bw), (h - 2 * margin) / float(bh))
        dw, dh = max(1, int(round(bw * s))), max(1, int(round(bh * s)))
        dx0 = (w - dw) // 2
        dy0 = h - margin - dh
    out = Image(w, h)
    purities = []
    for ty in range(dh):
        sy0 = y0 + int(math.floor(ty * bh / float(dh)))
        sy1 = max(sy0 + 1, y0 + int(math.floor((ty + 1) * bh / float(dh))))
        for tx in range(dw):
            sx0 = x0 + int(math.floor(tx * bw / float(dw)))
            sx1 = max(sx0 + 1, x0 + int(math.floor((tx + 1) * bw / float(dw))))
            cov, rep, pure = _block_colour(img, key, sx0, sy0, sx1, sy1)
            if cov >= 0.5 and rep is not None:
                out.set(dx0 + tx, dy0 + ty, rep + (255,))
                purities.append(pure)
    return out, (sum(purities) / len(purities) if purities else 0.0)


def _colour_counts(img):
    counts = {}
    for y in range(img.h):
        for x in range(img.w):
            if img.opaque(x, y):
                c = img.rgb(x, y)
                counts[c] = counts.get(c, 0) + 1
    return counts


def median_cut(counts, k):
    """Deterministic weighted median cut: {colour: count} -> up to k colours."""
    boxes = [sorted(counts.items())]
    while len(boxes) < k:
        best, best_score = None, -1
        for i, box in enumerate(boxes):
            if len(box) < 2:
                continue
            ranges = [max(c[ch] for c, _ in box) - min(c[ch] for c, _ in box) for ch in range(3)]
            score = max(ranges) * sum(n for _, n in box)
            if score > best_score:
                best, best_score = i, score
        if best is None:
            break
        box = boxes.pop(best)
        ranges = [max(c[ch] for c, _ in box) - min(c[ch] for c, _ in box) for ch in range(3)]
        ch = ranges.index(max(ranges))
        box.sort(key=lambda cn: (cn[0][ch], cn[0]))
        total = sum(n for _, n in box)
        acc, cut = 0, 1
        for j, (_c, n) in enumerate(box):
            acc += n
            if acc * 2 >= total:
                cut = min(max(j + 1, 1), len(box) - 1)
                break
        boxes.insert(best, box[cut:])
        boxes.insert(best, box[:cut])
    palette = []
    for box in boxes:
        total = sum(n for _, n in box)
        palette.append(tuple(int(round(sum(c[ch] * n for c, n in box) / float(total))) for ch in range(3)))
    return palette


def cluster_palette(counts, radius=24):
    """Groups near-identical colours (noise around one flat tone) and keeps every clearly different
    colour, however rare — pixel art's outlines and highlights are rare but essential. Most common
    colours seed the groups; each group's colour is its weighted mean."""
    groups = []  # [r_sum, g_sum, b_sum, n, seed]
    for c, n in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
        best, bd = None, None
        for g in groups:
            centre = (g[0] / g[3], g[1] / g[3], g[2] / g[3])
            d = redmean(c, centre)
            if d <= radius and (bd is None or d < bd):
                best, bd = g, d
        if best is None:
            groups.append([c[0] * n, c[1] * n, c[2] * n, n, c])
        else:
            best[0] += c[0] * n
            best[1] += c[1] * n
            best[2] += c[2] * n
            best[3] += n
    return [(int(round(g[0] / g[3])), int(round(g[1] / g[3])), int(round(g[2] / g[3]))) for g in groups]


def nearest(c, palette):
    best, bd = None, None
    for p in palette:
        d = redmean(c, p)
        if bd is None or d < bd or (d == bd and p < best):
            best, bd = p, d
    return best


def remap(img, palette):
    cache = {}
    for y in range(img.h):
        for x in range(img.w):
            if img.opaque(x, y):
                c = img.rgb(x, y)
                if c not in cache:
                    cache[c] = nearest(c, palette)
                img.set(x, y, cache[c] + (255,))


def lift_darks(img, min_v=0.28, to_v=0.30):
    """Raises near-black tones to a deep tinted shade: the target look has almost no near-black.
    Returns the number of pixels changed."""
    changed = 0
    cache = {}
    for y in range(img.h):
        for x in range(img.w):
            if not img.opaque(x, y):
                continue
            c = img.rgb(x, y)
            if c not in cache:
                h, s, v = hsv(c)
                if v >= min_v:
                    cache[c] = None
                elif s < 0.15:
                    cache[c] = to_gba(SLATE)
                else:
                    r, g, b = colorsys.hsv_to_rgb(h, s, to_v)
                    cache[c] = to_gba((int(r * 255), int(g * 255), int(b * 255)))
            if cache[c] is not None:
                img.set(x, y, cache[c] + (255,))
                changed += 1
    return changed


def merge_close_colours(img, min_dist, keep=()):
    """Merges any two colours closer than `min_dist` (the rarer into the commoner), so neighbouring
    tones always read as distinct steps rather than blends. Returns the number of merges."""
    merges = 0
    while True:
        counts = _colour_counts(img)
        cols = sorted(counts)
        pair, best = None, None
        for i in range(len(cols)):
            for j in range(i + 1, len(cols)):
                d = redmean(cols[i], cols[j])
                if d < min_dist and (best is None or d < best):
                    pair, best = (cols[i], cols[j]), d
        if pair is None:
            return merges
        a, b = pair
        if a in keep or (b not in keep and counts[a] > counts[b]) or (b not in keep and counts[a] == counts[b] and a < b):
            victim, target = b, a
        else:
            victim, target = a, b
        for y in range(img.h):
            for x in range(img.w):
                if img.opaque(x, y) and img.rgb(x, y) == victim:
                    img.set(x, y, target + (255,))
        merges += 1


def reduce_colours(img, cap, keep=()):
    """Merges colours into their nearest neighbour, cheapest first, until at most `cap` remain. A merge
    costs the squared distance it moves the colour times the square root of the pixels it changes, so
    near-duplicates go first and a small but clearly different accent (a gold dome, red berries)
    survives. (Merging the least-used colour first dropped such accents.)"""
    counts = _colour_counts(img)
    if len(counts) <= cap:
        return
    alive = set(counts)

    def nearest_alive(v):
        best, bd = None, None
        for c in alive:
            if c == v:
                continue
            d = redmean(v, c)
            if bd is None or d < bd or (d == bd and c < best):
                best, bd = c, d
        return best, bd

    nn = {v: nearest_alive(v) for v in alive}
    merged = {}
    while len(alive) > cap:
        best = None
        for v in alive:
            if v in keep:
                continue
            target, d = nn[v]
            cost = d * d * math.sqrt(counts[v])
            if best is None or cost < best[0] or (cost == best[0] and v < best[1]):
                best = (cost, v, target)
        if best is None:
            break
        _cost, victim, target = best
        alive.discard(victim)
        counts[target] += counts.pop(victim)
        merged[victim] = target
        for c in alive:
            if nn[c][0] == victim:
                nn[c] = nearest_alive(c)
    final = {}
    for c in merged:
        t = c
        while t in merged:
            t = merged[t]
        final[c] = t
    for y in range(img.h):
        for x in range(img.w):
            if img.opaque(x, y):
                t = final.get(img.rgb(x, y))
                if t is not None:
                    img.set(x, y, t + (255,))


def lost_colours(before, img, min_share=0.005, max_dist=80):
    """Colours that covered at least `min_share` of the sprite before the colour cap and have no close
    match left after it (every remaining colour is more than `max_dist` away, a clearly different
    colour rather than a neighbouring shade): accents the reduction dropped. `before` is {colour: pixels}."""
    total = float(sum(before.values()))
    left = sorted(_colour_counts(img))
    out = []
    for c, n in sorted(before.items(), key=lambda kv: (-kv[1], kv[0])):
        if not left or n < max(3, min_share * total):
            continue
        near = nearest(c, left)
        d = redmean(c, near)
        if d > max_dist:
            out.append({"colour": hexs(c), "share": round(n / total, 4), "nearest_left": hexs(near), "distance": round(d, 1)})
    return out


def _neighbours4(img, x, y):
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        yield x + dx, y + dy


def boundary_pixels(img):
    """Opaque pixels with a transparent 4-neighbour or on the image edge."""
    out = []
    for y in range(img.h):
        for x in range(img.w):
            if not img.opaque(x, y):
                continue
            for nx, ny in _neighbours4(img, x, y):
                if not (0 <= nx < img.w and 0 <= ny < img.h) or not img.opaque(nx, ny):
                    out.append((x, y))
                    break
    return out


def pale_edge_share(img):
    """The share of the silhouette's edge pixels that are pale (light and nearly grey). Measured before
    the outline is repaired, it is high when a painted backdrop, a frame, or a copied layout box became
    part of the object, or when the object was drawn with no outline at all."""
    edge = boundary_pixels(img)
    if not edge:
        return 0.0
    pale = 0
    for x, y in edge:
        _h, s, v = hsv(img.rgb(x, y))
        if v >= 0.8 and s <= 0.3:
            pale += 1
    return pale / float(len(edge))


ROOF_HUE = 3  # degrees: the houses' red-brown roof, the hue their colourways recolour


def roof_share(img):
    """The share of opaque pixels in the red-brown roof colours: small for a house that has lost its roof."""
    n = roof = 0
    for y in range(img.h):
        for x in range(img.w):
            if img.opaque(x, y):
                n += 1
                h, s, v = hsv(img.rgb(x, y))
                if s >= 0.35 and v >= 0.4 and hue_diff(h, ROOF_HUE / 360.0) <= 18:
                    roof += 1
    return roof / float(n) if n else 0.0


def outline_dark(img, x, y, bset):
    """True when a silhouette-edge pixel reads as an outline: dark in itself, or clearly darker
    than the pixel inside it (selective outlining, as tinted outlines are in the target look)."""
    c = img.rgb(x, y)
    if hsv(c)[2] <= 0.45:
        return True
    inner = [img.rgb(nx, ny) for nx, ny in _neighbours4(img, x, y)
             if 0 <= nx < img.w and 0 <= ny < img.h and img.opaque(nx, ny) and (nx, ny) not in bset]
    if not inner:
        return False
    return luma(c) <= 0.7 * max(luma(i) for i in inner)


def repair_outline(img, palette, ink=INK):
    """Darkens silhouette-edge pixels that don't read as an outline, using the darkest colour of
    the same hue already in the palette, or ink. Returns the number of pixels changed."""
    bset = set(boundary_pixels(img))
    darks = [p for p in palette if hsv(p)[2] <= 0.45]
    changed = 0
    for (x, y) in sorted(bset, key=lambda p: (p[1], p[0])):
        if outline_dark(img, x, y, bset):
            continue
        c = img.rgb(x, y)
        h, s, _v = hsv(c)
        family = [d for d in darks if hsv(d)[2] >= 0.2 and ((s < 0.2 and hsv(d)[1] < 0.25) or (s >= 0.2 and hsv(d)[1] >= 0.2 and hue_diff(h, hsv(d)[0]) <= 40))]
        target = nearest(darkened(c, 0.4), family) if family else ink
        img.set(x, y, target + (255,))
        changed += 1
    return changed


def clean_specks(img):
    """Removes opaque pixels with no opaque 8-neighbour and fills one-pixel holes. Returns counts."""
    removed = filled = 0
    for y in range(img.h):
        for x in range(img.w):
            if not img.opaque(x, y):
                continue
            alone = True
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if (dx or dy) and 0 <= x + dx < img.w and 0 <= y + dy < img.h and img.opaque(x + dx, y + dy):
                        alone = False
            if alone:
                img.set(x, y, (0, 0, 0, 0))
                removed += 1
    for y in range(1, img.h - 1):
        for x in range(1, img.w - 1):
            if img.opaque(x, y):
                continue
            ns = [img.rgb(nx, ny) for nx, ny in _neighbours4(img, x, y) if img.opaque(nx, ny)]
            if len(ns) == 4:
                best = sorted(set(ns), key=lambda c: (-ns.count(c), c))[0]
                img.set(x, y, best + (255,))
                filled += 1
    return removed, filled


def convert(raw, w, h, mode="free", palette=None, cap=16, key=(255, 0, 255), fit="fill", margin=0,
            aspect_tolerance=0.15, allow_pieces=None, outline=True):
    """Large generated image -> native sprite. `mode` is "free" (an adaptive palette of at most
    `cap` colours in the 15-bit colour space) or "master" (snapped to `palette`, then reduced to
    `cap`). Raises ConversionError when the image can't become a valid sprite."""
    if allow_pieces is None:
        allow_pieces = fit == "contain"
    raw, shadow_px = shadows_to_background(raw, key)
    bbox, strays, main_frac = find_subject(raw, key, allow_pieces)
    bw, bh = bbox[2] - bbox[0], bbox[3] - bbox[1]
    border, gap = background_report(raw, key, bbox)
    report = {"bbox": list(bbox), "strays": strays, "aspect_target": round(w / float(h), 4), "shadow_removed": shadow_px,
              "aspect_subject": round(bw / float(bh), 4), "border_background": border, "subject_margin": gap}
    if fit == "fill":
        dev = abs(math.log((bw / float(bh)) / (w / float(h))))
        report["aspect_deviation"] = round(dev, 4)
        if dev > math.log(1.0 + aspect_tolerance):
            raise ConversionError("the object's proportions are %.2f:1, the footprint needs %.2f:1 (more than %d%% off)"
                                  % (bw / float(bh), w / float(h), int(aspect_tolerance * 100)))
    sprite, purity = downsample(raw, key, bbox, w, h, fit, margin)
    report["block_purity"] = round(purity, 4)
    report["pale_edge_share"] = round(pale_edge_share(sprite), 4)
    if mode == "free":
        pal = sorted(set(to_gba(c) for c in cluster_palette(_colour_counts(sprite))))
    else:
        if not palette:
            raise ValueError("master mode needs a palette")
        pal = list(palette)
    ink = to_gba(SLATE) if mode == "free" else INK
    if mode != "free":
        # group noise around each flat tone first, so a tone between two palette entries maps as a
        # whole instead of speckling
        remap(sprite, cluster_palette(_colour_counts(sprite)))
    remap(sprite, pal)
    report["darks_lifted"] = lift_darks(sprite) if mode == "free" else 0
    before_cap = _colour_counts(sprite)
    reduce_colours(sprite, cap - 1 if mode == "free" else cap, keep=(ink,))
    report["close_colours_merged"] = merge_close_colours(sprite, SOFT_STEP, keep=(ink,))
    specks = clean_specks(sprite)
    used = sorted(_colour_counts(sprite).keys())
    # overlays have no outline: repairing one darkened the grass tufts' light tips
    report["outline_fixed"] = repair_outline(sprite, used if mode == "free" else pal, ink=ink) if outline else 0
    reduce_colours(sprite, cap, keep=(ink,))
    report["specks_removed"], report["holes_filled"] = specks
    report["colours"] = len(_colour_counts(sprite))
    report["lost_colours"] = lost_colours(before_cap, sprite)
    return sprite, report


def recolour_hue(img, src_hue_deg, dst_rgb_base, rows=None, tolerance_deg=25, min_sat=0.25):
    """Moves every pixel of one hue family (in the given rows, if any) to another hue, keeping its
    saturation and brightness relative to the family, then rounds to the 15-bit colour space.
    Used for the house roof colourways."""
    th, ts, tv = hsv(dst_rgb_base)
    out = img.copy()
    for y in range(img.h):
        if rows is not None and not rows[0] <= y < rows[1]:
            continue
        for x in range(img.w):
            if not img.opaque(x, y):
                continue
            c = img.rgb(x, y)
            h, s, v = hsv(c)
            if s < min_sat or hue_diff(h, src_hue_deg / 360.0) > tolerance_deg:
                continue
            r, g, b = colorsys.hsv_to_rgb(th, min(1.0, s * (ts / max(s, 0.01)) ** 0.5), v)
            out.set(x, y, to_gba((int(r * 255), int(g * 255), int(b * 255))) + (255,))
    return out


# ---------------------------------------------------------------------------
# Technical checks (each returns a dict: name, ok, value, target)
# ---------------------------------------------------------------------------


def _check(name, ok, value, target, detail=""):
    return {"name": name, "ok": bool(ok), "value": value, "target": target, "detail": detail}


def door_like(c):
    """Dark (a doorway or shadow) or plain wood (door leaves, boards, posts)."""
    h, s, v = hsv(c)
    return v <= 0.38 or (20 <= h * 360 <= 50 and s >= 0.3 and v <= 0.7)


def technical_checks(img, spec, report=None):
    """The rules every sprite must meet, from the catalogue entry `spec`."""
    w, h = spec["size_px"]
    out = [_check("size", (img.w, img.h) == (w, h), "%dx%d" % (img.w, img.h), "%dx%d" % (w, h))]
    semi = sum(1 for i in range(3, len(img.px), 4) if 0 < img.px[i] < 255)
    out.append(_check("binary_alpha", semi == 0, semi, "0 semi-transparent pixels"))
    counts = _colour_counts(img)
    cap = spec.get("colour_cap", 16)
    out.append(_check("colours", len(counts) <= cap, len(counts), "<= %d" % cap))
    key = hexc(spec.get("key_colour", "#FF00FF"))
    bset = boundary_pixels(img)
    bs = set(bset)
    # the key itself anywhere, or a shade of it on the silhouette's edge (a shadow or fringe the converter kept)
    keyish = sum(n for c, n in counts.items() if is_key(c, key)) + sum(1 for x, y in bset if is_key_shade(img.rgb(x, y), key))
    out.append(_check("no_key_colour", keyish == 0, keyish, "0 pixels near the background key, or a shade of it on the edge"))
    if spec.get("outline", True) and bset:
        dark = sum(1 for (x, y) in bset if outline_dark(img, x, y, bs))
        share = dark / float(len(bset))
        out.append(_check("outline", share >= 0.9, round(share, 3), ">= 0.9 of edge pixels dark"))
    fill = img.opaque_count() / float(w * h)
    mf = spec.get("min_fill", 0.0)
    out.append(_check("fill", fill >= mf, round(fill, 3), ">= %.2f of the footprint opaque" % mf))
    lonely = 0
    for y in range(img.h):
        for x in range(img.w):
            if img.opaque(x, y) and not any(
                    0 <= x + dx < img.w and 0 <= y + dy < img.h and img.opaque(x + dx, y + dy)
                    for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dx or dy):
                lonely += 1
    out.append(_check("no_specks", lonely == 0, lonely, "0 isolated pixels"))
    if spec.get("door"):
        cols = spec.get("door_check_cols") or [spec["door"][0]]
        row = spec["door"][1]
        dark = n = 0
        for col in cols:
            for y in range(row * TILE, (row + 1) * TILE):
                for x in range(col * TILE, (col + 1) * TILE):
                    if 0 <= x < img.w and 0 <= y < img.h:
                        n += 1
                        if img.opaque(x, y) and door_like(img.rgb(x, y)):
                            dark += 1
        share = dark / float(n) if n else 0.0
        need = spec.get("door_dark_share", 0.3)
        out.append(_check("door", share >= need, round(share, 3), ">= %.2f door-like (dark or wood) in the door tile(s)" % need))
    if spec.get("light_check", True):
        score, groups = light_direction(img)
        if groups:
            out.append(_check("light_from_top_left", score >= 0.4, round(score, 3), ">= 0.40 of shaded colour families"))
    if spec.get("symmetric"):
        mism = n = 0
        for y in range(img.h):
            for x in range(img.w // 2):
                n += 1
                if img.opaque(x, y) != img.opaque(img.w - 1 - x, y):
                    mism += 1
        share = mism / float(n)
        out.append(_check("symmetric_silhouette", share <= 0.08, round(share, 3), "<= 0.08 mismatch"))
    if spec.get("max_roof_share") is not None:
        rs = roof_share(img)
        out.append(_check("roof_gone", rs <= spec["max_roof_share"], round(rs, 3),
                          "<= %.2f of the sprite in red-brown roof colours" % spec["max_roof_share"]))
    if report is not None:
        out.append(_check("no_stray_content", not report.get("strays"), len(report.get("strays", [])),
                          "0 separate marks away from the object (a watermark, text, a second object)"))
        bp = report.get("block_purity", 1.0)
        need = spec.get("min_purity", 0.75)
        out.append(_check("drawn_at_pixel_scale", bp >= need, bp, ">= %.2f block purity" % need))
        # Measured on the generated image by the converter; missing from records older than these checks.
        border, margin = report.get("border_background"), report.get("subject_margin")
        out.append(_check("background_clear", border is not None and border >= 0.95 and margin >= 0.01,
                          "not measured" if border is None else "%.3f edge, %.3f gap" % (border, margin),
                          ">= 0.95 of the picture's edge is background, and the object stays >= 0.01 from every edge"))
        limit = spec.get("pale_edge_max", 0.4)
        if limit is not None:
            pe = report.get("pale_edge_share")
            out.append(_check("edge_not_pale", pe is not None and pe <= limit, "not measured" if pe is None else pe,
                              "<= %.2f of the silhouette's edge pale (a backdrop, a frame, or no outline)" % limit))
        lost = report.get("lost_colours")
        out.append(_check("colours_kept", lost == [], "not measured" if lost is None else len(lost),
                          "0 clearly different colours (>= 0.5% of the sprite, > 80 away) dropped by the colour cap",
                          "; ".join("%s (%.1f%%)" % (c["colour"], c["share"] * 100) for c in lost or [])))
    return out


def light_direction(img):
    """Within each colour family (a hue, or the greys), lighter tones should sit up and to the left
    of darker ones. Returns (weighted share of families that agree, number of families judged)."""
    bset = set(boundary_pixels(img))
    stats = {}
    for y in range(img.h):
        for x in range(img.w):
            if not img.opaque(x, y) or (x, y) in bset:
                continue
            c = img.rgb(x, y)
            st = stats.setdefault(c, [0, 0, 0])
            st[0] += 1
            st[1] += x
            st[2] += y
    families = {}
    for c, (n, sx, sy) in stats.items():
        h, s, v = hsv(c)
        if v < 0.2:
            continue
        fam = "grey" if s < 0.18 else "h%d" % int(((h * 360 + 15) % 360) // 30)
        families.setdefault(fam, []).append((v, c, n, sx, sy))
    agree = total = judged = 0
    for fam, cols in families.items():
        if len(cols) < 2:
            continue
        n_all = sum(c[2] for c in cols)
        if n_all < 24:
            continue
        cols.sort()
        half, acc, split = n_all / 2.0, 0, 1
        for i, c in enumerate(cols):
            acc += c[2]
            if acc >= half:
                split = min(max(i + 1, 1), len(cols) - 1)
                break
        dark, light = cols[:split], cols[split:]
        def centroid(group):
            n = sum(c[2] for c in group)
            return (sum(c[3] for c in group) + sum(c[4] for c in group)) / float(n)
        judged += 1
        total += n_all
        if centroid(light) < centroid(dark):
            agree += n_all
    return (agree / float(total) if total else 1.0), judged


# ---------------------------------------------------------------------------
# Style metrics: per 16 x 16 tile, compared with the reference's distribution
# ---------------------------------------------------------------------------

SOFT_STEP = 40  # two different neighbouring colours closer than this read as a blend, not a pixel-art step

METRICS = ("colours_per_tile", "max_colours_per_8x8", "soft_step_ratio", "isolated_ratio", "mean_run",
           "sat_mean", "val_mean", "val_spread", "dark_share")
HARD_METRICS = ("max_colours_per_8x8", "soft_step_ratio", "dark_share", "sat_mean")
# Reported as a warning, but never the one unusual measure a sprite is allowed: every house the image models drew,
# the ones that look right by eye included, sat below the reference brightness band (2026-10-30). Murky art is
# still caught by dark_share and soft_step_ratio, which are hard.
WARNING_ONLY_METRICS = ("val_mean",)
# Which percentiles bound each metric's band. Saturation gets a wider band: the reference does use a
# few strongly saturated roofs, and a narrower band failed some of its own buildings.
BANDS = {"sat_mean": ("1", "99")}
SCALE_FLOOR = {"colours_per_tile": 1.0, "max_colours_per_8x8": 1.0, "soft_step_ratio": 0.02, "isolated_ratio": 0.02,
               "mean_run": 0.5, "sat_mean": 0.05, "val_mean": 0.05, "val_spread": 0.05, "dark_share": 0.02}


def tile_metrics(get_rgb, opaque, x0, y0, min_opaque=0.6):
    """Metrics of one 16 x 16 tile; `get_rgb(x, y)` and `opaque(x, y)` read the picture.
    Returns None when the tile is mostly transparent."""
    cols = []
    n_op = 0
    for y in range(y0, y0 + TILE):
        row = []
        for x in range(x0, x0 + TILE):
            if opaque(x, y):
                row.append(get_rgb(x, y))
                n_op += 1
            else:
                row.append(None)
        cols.append(row)
    if n_op < min_opaque * TILE * TILE:
        return None
    present = [c for row in cols for c in row if c is not None]
    quads = []
    for qy in (0, 8):
        for qx in (0, 8):
            quads.append(len({cols[y][x] for y in range(qy, qy + 8) for x in range(qx, qx + 8) if cols[y][x] is not None}))
    n_diff = n_soft = 0
    for y in range(TILE):
        for x in range(TILE):
            c = cols[y][x]
            if c is None:
                continue
            for nx, ny in ((x + 1, y), (x, y + 1)):
                if nx < TILE and ny < TILE and cols[ny][nx] is not None and cols[ny][nx] != c:
                    n_diff += 1
                    if redmean(c, cols[ny][nx]) < SOFT_STEP:
                        n_soft += 1
    isolated = 0
    for y in range(TILE):
        for x in range(TILE):
            c = cols[y][x]
            if c is None:
                continue
            ns = [cols[ny][nx] for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1))
                  if 0 <= nx < TILE and 0 <= ny < TILE and cols[ny][nx] is not None]
            if len(ns) >= 3 and all(n != c for n in ns):
                isolated += 1
    runs = []
    for row in cols:
        run, prev = 0, None
        for c in row:
            if c is not None and c == prev:
                run += 1
            else:
                if prev is not None and run:
                    runs.append(run)
                run = 1 if c is not None else 0
            prev = c
        if prev is not None and run:
            runs.append(run)
    hs = [hsv(c) for c in present]
    vals = sorted(v for _, _, v in hs)
    p = lambda q: vals[min(len(vals) - 1, int(q * (len(vals) - 1) + 0.5))]
    return {
        "colours_per_tile": len(set(present)),
        "max_colours_per_8x8": max(quads),
        "soft_step_ratio": n_soft / float(n_diff) if n_diff else 0.0,
        "isolated_ratio": isolated / float(n_op),
        "mean_run": sum(runs) / float(len(runs)) if runs else 0.0,
        "sat_mean": sum(s for _, s, _ in hs) / len(hs),
        "val_mean": sum(v for _, _, v in hs) / len(hs),
        "val_spread": p(0.9) - p(0.1),
        "dark_share": sum(1 for v in vals if v < 0.25) / float(len(vals)),
    }


def image_tile_metrics(img, min_opaque=0.6):
    out = []
    for ty in range(img.h // TILE):
        for tx in range(img.w // TILE):
            m = tile_metrics(img.rgb, img.opaque, tx * TILE, ty * TILE, min_opaque)
            if m is not None:
                out.append(m)
    return out


def percentile(sorted_vals, q):
    if not sorted_vals:
        return 0.0
    i = q * (len(sorted_vals) - 1)
    lo, hi = int(math.floor(i)), int(math.ceil(i))
    return sorted_vals[lo] + (sorted_vals[hi] - sorted_vals[lo]) * (i - lo)


def summarise(metric_rows):
    """Per metric: the percentiles the style check uses as its band."""
    out = {}
    for m in METRICS:
        vals = sorted(r[m] for r in metric_rows)
        out[m] = {q: round(percentile(vals, float(q) / 100.0), 4) for q in ("1", "2.5", "5", "25", "50", "75", "95", "97.5", "99")}
    out["_n_tiles"] = len(metric_rows)
    return out


def style_fit(img, ref_group, min_share=0.75, min_metrics_share=0.85):
    """Compares the sprite's tiles with a reference group's bands ([2.5th, 97.5th] percentile).
    A metric passes when at least `min_share` of the sprite's judged tiles fall inside its band.
    The sprite passes when every hard metric passes and at least `min_metrics_share` of all do
    (with nine metrics: at most one soft metric may miss, and it is reported as a warning; a warning-only metric
    is reported but never counted)."""
    rows = image_tile_metrics(img)
    if not rows:
        rows = image_tile_metrics(img, min_opaque=0.3)
    result = {"tiles_judged": len(rows), "metrics": [], "ok": False}
    if not rows:
        result["detail"] = "no tile is opaque enough to judge"
        return result
    passed = 0
    hard_ok = True
    for m in METRICS:
        band = ref_group[m]
        qlo, qhi = BANDS.get(m, ("2.5", "97.5"))
        lo, hi = band[qlo], band[qhi]
        vals = [r[m] for r in rows]
        inside = sum(1 for v in vals if lo - 1e-9 <= v <= hi + 1e-9) / float(len(vals))
        med = percentile(sorted(vals), 0.5)
        ok = inside >= min_share
        passed += ok or m in WARNING_ONLY_METRICS
        if m in HARD_METRICS and not ok:
            hard_ok = False
        result["metrics"].append({"name": m, "ok": ok, "median": round(med, 4), "band": [lo, hi],
                                  "share_inside": round(inside, 3), "hard": m in HARD_METRICS})
    share = passed / float(len(METRICS))
    result["metrics_passed_share"] = round(share, 3)
    result["ok"] = hard_ok and share >= min_metrics_share
    # distance from the reference medians, in units of the band's half-width (with a floor, since
    # some bands are very narrow): lower is closer
    dist = []
    for m in METRICS:
        band = ref_group[m]
        half = max(SCALE_FLOOR[m], (band["97.5"] - band["2.5"]) / 2.0)
        med = percentile(sorted(r[m] for r in rows), 0.5)
        dist.append(abs(med - band["50"]) / half)
    result["style_distance"] = round(sum(dist) / len(dist), 3)
    return result


# ---------------------------------------------------------------------------
# Originality: no tile may be a copy of a reference tile
# ---------------------------------------------------------------------------


def tile_hashes(get_rgb, opaque, x0, y0, min_colours=5, min_edges=40):
    """Fingerprints of one 16 x 16 tile, or None when the tile is transparent in places or too simple
    to judge (a plain fill, two-tone stripes: shared conventions, not something one can copy).
    Returns (average-hash of luminance as int, digest of the colour pattern, brightness levels: each
    pixel's luminance on 8 steps between the tile's darkest and lightest)."""
    cols, lum = [], []
    for y in range(y0, y0 + TILE):
        for x in range(x0, x0 + TILE):
            if not opaque(x, y):
                return None
            c = get_rgb(x, y)
            cols.append(c)
            lum.append(luma(c))
    distinct = set(cols)
    if len(distinct) < min_colours:
        return None
    if max(cols.count(c) for c in distinct) > 0.6 * len(cols):
        return None  # mostly one flat tone: too little detail to call it a copy
    edges = sum(1 for i in range(TILE * TILE) if (i % TILE < TILE - 1 and cols[i] != cols[i + 1])
                or (i + TILE < TILE * TILE and cols[i] != cols[i + TILE]))
    if edges < min_edges:
        return None
    mean = sum(lum) / len(lum)
    bits = 0
    for l in lum:
        bits = (bits << 1) | (1 if l > mean else 0)
    order = {}
    pattern = bytes(order.setdefault(c, len(order)) % 256 for c in cols)
    lo, hi = min(lum), max(lum)
    span = max(1e-6, hi - lo)
    levels = bytes(int(round((l - lo) / span * 7)) for l in lum)
    return bits, hashlib.sha1(pattern).hexdigest()[:16], levels


def flip_h(get_rgb, opaque, x0, y0):
    """A get/opaque pair reading the tile mirrored left-right."""
    return (lambda x, y: get_rgb(2 * x0 + TILE - 1 - x, y)), (lambda x, y: opaque(2 * x0 + TILE - 1 - x, y))


def originality(img, ref_tiles, ref_patterns, prefilter_bits=24, max_diff=24):
    """Checks every tile-sized window on the 8-pixel lattice against the reference. A window is a copy
    when its colour pattern is exactly a reference pattern (a copy or a recolour), or when its
    brightness levels differ from a reference tile's in at most `max_diff` of 256 pixels (a touched-up
    copy). `ref_tiles` is [(average-hash, brightness levels)]."""
    hits = []
    pats = set(ref_patterns)
    for y0 in range(0, img.h - TILE + 1, 8):
        for x0 in range(0, img.w - TILE + 1, 8):
            hv = tile_hashes(img.rgb, img.opaque, x0, y0)
            if hv is None:
                continue
            bits, pat, levels = hv
            if pat in pats:
                hits.append({"at": [x0, y0], "kind": "same colour pattern as a reference tile"})
                continue
            for rb, rlevels in ref_tiles:
                if bin(bits ^ rb).count("1") > prefilter_bits:
                    continue
                diff = sum(1 for a, b in zip(levels, rlevels) if a != b)
                if diff <= max_diff:
                    hits.append({"at": [x0, y0], "kind": "%d of 256 pixels differ from a reference tile" % diff})
                    break
    return hits


# ---------------------------------------------------------------------------
# Small helpers for the command-line tools
# ---------------------------------------------------------------------------


def load_json(path):
    with open(path) as f:
        return json.load(f)


def save_json(path, obj):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f, indent=2, sort_keys=True)
        f.write("\n")


def repo_root():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", ".."))


DEFAULT_REFERENCE = os.path.expanduser("~/.tenth_spring_rom_spike/emerald/style_reference.json")
