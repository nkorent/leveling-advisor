#!/usr/bin/env python3
"""Generate the addon's textures (pure Python 3, no third-party packages).

Writes uncompressed 32-bit TGA files (64x64, alpha, top-left origin, y down):
  PinShield.tga      map pin: dark shield with a gold rim and a faint inner highlight
  PinShieldGlow.tga  the same shape in gold with a soft outer glow
  BookmarkTab.tga    the book's side tab on the quest log (shown at 36x40): dark body,
                     bronze-gold rim on the top, right and bottom edges, rounded right
                     corners; the left edge is open (it tucks under the frame)

Usage: tools/make-pin-textures.py [output-dir]
       (default: LevelingAdvisor/Media next to this script's repository)
Deterministic: the same bytes on every run.
"""
import math
import struct
import sys
from pathlib import Path

SIZE = 64
SS = 4  # supersampling per axis

GOLD = (255, 209, 0)
FILL = (22, 15, 7, 0.94)
HILITE = (255, 225, 140, 0.25)

RIM_WIDTH = 1.2        # viewBox units
HILITE_WIDTH = 0.8
GLOW_ALPHA = 0.55
GLOW_FALLOFF = 6.0     # pixels
SHIELD_HEIGHT = 62.0   # px, outer height of the shield including its rim
GLOW_SHIELD_HEIGHT = 40.0  # glow texture is shown at 26x29 over a 16x18 pin

# Bookmark tab, in pixels (y down). The 64x64 texture is shown at 36x40, so the body
# fills it; right corners rounded, the left edge is open (it tucks under the frame).
BOOK_X0, BOOK_X1, BOOK_Y0, BOOK_Y1 = 0.0, 62.0, 1.0, 63.0
BOOK_RADIUS = 12.0
BOOK_RIM = 2.0
BOOK_RIM_COLOR = (222, 178, 52)  # bronze-gold
BOOK_TOP = (40, 29, 18)          # near black-brown at the top ...
BOOK_BOTTOM = (24, 17, 10)       # ... and at the bottom
BOOK_ALPHA = 0.9


def bezier(p0, p1, p2, p3, n=24):
    pts = []
    for i in range(1, n + 1):
        t = i / n
        u = 1 - t
        pts.append((
            u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
            u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]))
    return pts


def shield_outline():
    """Closed outline of the mockup's shield, in its 16x18 viewBox."""
    pts = [(8, .8), (14.6, 3), (14.6, 8.3)]
    pts += bezier((14.6, 8.3), (14.6, 12.4), (11.7, 15.3), (8, 17.2))
    pts += bezier((8, 17.2), (4.3, 15.3), (1.4, 12.4), (1.4, 8.3))
    pts += [(1.4, 3)]
    return pts  # closes back to (8, .8)


def highlight_line():
    """Open inner highlight polyline (right half of the shield)."""
    pts = [(8, 2.4), (13, 4.1), (13, 8.2)]
    pts += bezier((13, 8.2), (13, 11.3), (10.9, 13.5), (8, 15.1))
    return pts


def transform(pts, scale):
    """viewBox -> pixels, shield bbox centred in the texture."""
    cx, cy = 8.0, 9.0
    c = SIZE / 2
    return [(c + (x - cx) * scale, c + (y - cy) * scale) for x, y in pts]


def inside(poly, x, y):
    c = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def seg_dist(px, py, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def dist(poly, x, y, closed):
    n = len(poly)
    last = n if closed else n - 1
    return min(seg_dist(x, y, poly[i], poly[(i + 1) % n]) for i in range(last))


def over(dst, src_rgb, src_a):
    """Composite src over dst; both are [r, g, b, a] with straight colour."""
    da = dst[3]
    oa = src_a + da * (1 - src_a)
    if oa <= 0:
        return [0.0, 0.0, 0.0, 0.0]
    return [(src_rgb[i] * src_a + dst[i] * da * (1 - src_a)) / oa for i in range(3)] + [oa]


def supersample(px, py, sample):
    """One pixel: the average of SS x SS samples; sample(x, y) -> [r, g, b, a]."""
    acc = [0.0, 0.0, 0.0, 0.0]  # premultiplied sum
    for sy in range(SS):
        for sx in range(SS):
            c = sample(px + (sx + 0.5) / SS, py + (sy + 0.5) / SS)
            acc[0] += c[0] * c[3]
            acc[1] += c[1] * c[3]
            acc[2] += c[2] * c[3]
            acc[3] += c[3]
    a = acc[3] / (SS * SS)
    if a <= 0:
        return (0, 0, 0, 0)
    return tuple(int(round(acc[i] / acc[3])) for i in range(3)) + (int(round(a * 255)),)


def render_shield():
    s = SHIELD_HEIGHT / (16.4 + RIM_WIDTH)
    outline = transform(shield_outline(), s)
    hi = transform(highlight_line(), s)
    rim_r = RIM_WIDTH * s / 2
    hi_r = HILITE_WIDTH * s / 2
    # Bounding box prefilter (pixels) to keep the pure Python loop fast.
    xs = [p[0] for p in outline]
    ys = [p[1] for p in outline]
    bx0, bx1 = min(xs) - rim_r - 1, max(xs) + rim_r + 1
    by0, by1 = min(ys) - rim_r - 1, max(ys) + rim_r + 1

    def sample(x, y):
        c = [0.0, 0.0, 0.0, 0.0]
        if inside(outline, x, y):
            c = over(c, FILL[:3], FILL[3])
        if dist(outline, x, y, True) <= rim_r:
            c = over(c, GOLD, 1.0)
        if dist(hi, x, y, False) <= hi_r:
            c = over(c, HILITE[:3], HILITE[3])
        return c

    rows = []
    for py in range(SIZE):
        row = []
        for px in range(SIZE):
            if not (bx0 <= px + 1 and px <= bx1 and by0 <= py + 1 and py <= by1):
                row.append((0, 0, 0, 0))
            else:
                row.append(supersample(px, py, sample))
        rows.append(row)
    return rows


def render_glow():
    s = GLOW_SHIELD_HEIGHT / (16.4 + RIM_WIDTH)
    outline = transform(shield_outline(), s)
    rows = []
    for py in range(SIZE):
        row = []
        for px in range(SIZE):
            x, y = px + 0.5, py + 0.5
            if inside(outline, x, y):
                a = GLOW_ALPHA
            else:
                t = dist(outline, x, y, True) / GLOW_FALLOFF
                if t >= 1:
                    a = 0.0
                else:
                    k = 1 - t
                    a = GLOW_ALPHA * k * k * (3 - 2 * k)  # smoothstep falloff
            row.append(GOLD + (int(round(a * 255)),))
        rows.append(row)
    return rows


def bookmark_edge(x, y):
    """Distance from (x, y) to the bookmark's top, right or bottom edge (the
    rounded corners included), or None outside the body. The left edge is
    straight and has no rim."""
    if not (BOOK_X0 <= x < BOOK_X1 and BOOK_Y0 <= y < BOOK_Y1):
        return None
    cx = BOOK_X1 - BOOK_RADIUS
    if x > cx and (y < BOOK_Y0 + BOOK_RADIUS or y > BOOK_Y1 - BOOK_RADIUS):
        cy = BOOK_Y0 + BOOK_RADIUS if y < BOOK_Y0 + BOOK_RADIUS else BOOK_Y1 - BOOK_RADIUS
        d = math.hypot(x - cx, y - cy)
        return None if d > BOOK_RADIUS else BOOK_RADIUS - d
    return min(y - BOOK_Y0, BOOK_Y1 - y, BOOK_X1 - x)


def render_bookmark():
    def sample(x, y):
        edge = bookmark_edge(x, y)
        if edge is None:
            return [0.0, 0.0, 0.0, 0.0]
        t = (y - BOOK_Y0) / (BOOK_Y1 - BOOK_Y0)
        fill = [BOOK_TOP[i] + (BOOK_BOTTOM[i] - BOOK_TOP[i]) * t for i in range(3)]
        c = over([0.0, 0.0, 0.0, 0.0], fill, BOOK_ALPHA)
        if edge < BOOK_RIM:
            c = over(c, BOOK_RIM_COLOR, 1.0)
        return c

    return [[supersample(px, py, sample) for px in range(SIZE)] for py in range(SIZE)]


def tga_bytes(rows):
    # type 2 (uncompressed true colour), 32 bpp, descriptor: 8 alpha bits + top-left origin
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    body = bytearray()
    for row in rows:
        for r, g, b, a in row:
            body += bytes((b, g, r, a))
    return header + bytes(body)


def main(argv):
    out = Path(argv[1]) if len(argv) > 1 else (
        Path(__file__).resolve().parent.parent / "LevelingAdvisor" / "Media")
    out.mkdir(parents=True, exist_ok=True)
    (out / "PinShield.tga").write_bytes(tga_bytes(render_shield()))
    (out / "PinShieldGlow.tga").write_bytes(tga_bytes(render_glow()))
    (out / "BookmarkTab.tga").write_bytes(tga_bytes(render_bookmark()))
    print("wrote", out / "PinShield.tga", out / "PinShieldGlow.tga", out / "BookmarkTab.tga")


if __name__ == "__main__":
    main(sys.argv)
