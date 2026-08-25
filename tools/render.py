"""Pixel-exact mirror of PacView.mc, for offline preview.

Every constant here is derived the same way Layout.compute() derives it,
*including Monkey C's integer division*, so what this draws is what the
watch draws. Used by replay.py to render real traces out of the simulator.
"""
from PIL import Image, ImageDraw
import maze as M
import pixfont as F

W = H = 390
COLS, ROWS = M.COLS, M.ROWS

safe = min(W, H) / 2.0 - 2.0
diag = (COLS * COLS + ROWS * ROWS) ** 0.5
CELL = int(2.0 * safe / diag)
OX = (W - COLS * CELL) // 2
OY = (H - ROWS * CELL) // 2
HALF = CELL // 2
INSET = (CELL * 22) // 100 or 1
DOTH = (CELL * 16) // 100 or 1
PWRR = max((CELL * 36) // 100, 2)
SCOREY = max((OY - 28) // 2, 2)
LIVESY = OY + ROWS * CELL + 8
GR = (CELL * 11) // 20
CORNER = max(CELL // 3, 1)

BG = (0, 0, 0); WALL = (0x21, 0x21, 0xDE); FLASH = (255, 255, 255)
DOT = (255, 184, 174); PAC = (255, 255, 0); DOOR = (255, 184, 255)
FRIGHT = (0x21, 0x21, 0xDE); EYE = (255, 255, 255); PUPIL = (0x21, 0x21, 0xDE)
FRUIT = (255, 0, 0)
GHOSTC = [(255, 0, 0), (255, 184, 255), (0, 255, 255), (255, 184, 82)]

DX = [0, -1, 0, 1]
DY = [-1, 0, 1, 0]

tileX = lambda c: OX + c * CELL + HALF
tileY = lambda r: OY + r * CELL + HALF


def bm_width(s, scale):
    """BMFont advances every glyph, last one included -- match that."""
    return sum((F.advance(c) + 1) * scale for c in s)


def text(d, s, scale, color, cx, y):
    x = cx - bm_width(s, scale) // 2
    for ch in s:
        g = F.glyph(ch)
        for ry in range(F.GH):
            for rx in range(F.GW):
                if g[ry][rx] == "#":
                    px, py = x + rx * scale, y + ry * scale
                    d.rectangle([px, py, px + scale - 1, py + scale - 1], fill=color)
        x += (F.advance(ch) + 1) * scale


SEG = M.wall_runs()


def _convex_corners():
    out = []
    for r in range(ROWS + 1):
        for c in range(COLS + 1):
            q = [M._solid(c - 1, r - 1), M._solid(c, r - 1),
                 M._solid(c - 1, r), M._solid(c, r)]
            if sum(q) != 1:
                continue
            k = q.index(True)
            out.append((c, r, -1 if k in (0, 2) else 1, -1 if k in (0, 1) else 1))
    return out


CORNERS = _convex_corners()


def draw_maze(d, dots, wall_color):
    for t, a, b, f, sgn0, sgn1 in SEG:
        lo = a * CELL + sgn0 * INSET
        hi = (b + 1) * CELL + sgn1 * INSET
        if sgn0 > 0:
            lo += CORNER
        if sgn1 < 0:
            hi -= CORNER
        if hi < lo:
            continue
        if t == 0:
            y = OY + f * CELL + INSET
            d.line([OX + lo, y, OX + hi, y], fill=wall_color)
        elif t == 1:
            y = OY + (f + 1) * CELL - INSET
            d.line([OX + lo, y, OX + hi, y], fill=wall_color)
        elif t == 2:
            x = OX + f * CELL + INSET
            d.line([x, OY + lo, x, OY + hi], fill=wall_color)
        else:
            x = OX + (f + 1) * CELL - INSET
            d.line([x, OY + lo, x, OY + hi], fill=wall_color)

    for c, r, sx, sy in CORNERS:
        x = OX + c * CELL + sx * INSET
        y = OY + r * CELL + sy * INSET
        d.line([x + sx * CORNER, y, x, y + sy * CORNER], fill=wall_color)

    for r in range(ROWS):
        for c in range(COLS):
            if M.MAZE[r][c] == "-":
                y = tileY(r)
                d.line([OX + c * CELL, y, OX + (c + 1) * CELL, y], fill=DOOR, width=2)
    for (c, r) in dots:
        d.rectangle([tileX(c) - DOTH, tileY(r) - DOTH,
                     tileX(c) + DOTH, tileY(r) + DOTH], fill=DOT)


def pix(tx, ty, dr, prog):
    return (tileX(tx) + DX[dr] * prog * CELL // 16,
            tileY(ty) + DY[dr] * prog * CELL // 16)


def draw_pac(d, tx, ty, dr, prog, mouth_open, death=None):
    import math
    px, py = pix(tx, ty, dr, prog)
    if death is not None:
        f = min(death / 26.0, 1.0)
        half = f * math.pi
        if f >= 0.98:
            return
    else:
        half = mouth_open * 0.36
    d.ellipse([px - GR, py - GR, px + GR, py + GR], fill=PAC)
    if half <= 0.01:
        return
    a = [-math.pi / 2, math.pi, math.pi / 2, 0.0][dr]
    reach = GR + 2
    d.polygon([(px, py)] + [(px + int(reach * math.cos(a + k)),
                             py + int(reach * math.sin(a + k)))
                            for k in (-half, 0, half)], fill=BG)


def draw_ghost(d, who, tx, ty, dr, prog, mode, state, flash=False):
    px, py = pix(tx, ty, dr, prog)
    eyes = state in (3, 4)
    if not eyes:
        body = GHOSTC[who] if mode != 2 else (FLASH if flash else FRIGHT)
        d.ellipse([px - GR, py - 1 - GR, px + GR, py - 1 + GR], fill=body)
        d.rectangle([px - GR, py - 1, px + GR, py + GR - 1], fill=body)
        d.rectangle([px - GR + 1, py + GR - 1, px - GR + 2, py + GR], fill=BG)
        d.rectangle([px + GR - 2, py + GR - 1, px + GR - 1, py + GR], fill=BG)
    if mode == 2 and not eyes:
        d.rectangle([px - 3, py - 2, px - 2, py - 1], fill=EYE)
        d.rectangle([px + 2, py - 2, px + 3, py - 1], fill=EYE)
        return
    d.rectangle([px - 3, py - 2, px - 2, py], fill=EYE)
    d.rectangle([px + 1, py - 2, px + 2, py], fill=EYE)
    ex = 1 if dr == 3 else 0
    ey = 1 if dr == 2 else (-1 if dr == 0 else 0)
    d.rectangle([px - 3 + ex, py - 1 + ey, px - 3 + ex, py - 1 + ey], fill=PUPIL)
    d.rectangle([px + 1 + ex, py - 1 + ey, px + 1 + ex, py - 1 + ey], fill=PUPIL)
