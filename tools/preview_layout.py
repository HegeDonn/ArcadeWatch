#!/usr/bin/env python3
"""Render the authentic maze on the vivoactive 5's round 390x390 face at
several cell sizes, so we can SEE what the circle costs us before writing
any Monkey C.  Tiles whose centre falls outside the bezel are flagged red.

  python3 tools/preview_layout.py   ->  tools/layout_compare.png
"""
from PIL import Image, ImageDraw
import maze as M

W = H = 390
R = 195.0
SAFE = 193.0          # bezel; a tile centre beyond this is not visible

BG      = (0, 0, 0)
WALL    = (33, 33, 222)
DOT     = (255, 184, 174)
PACMAN  = (255, 255, 0)
DOOR    = (255, 184, 255)
CLIP    = (255, 40, 40)
GHOSTS  = [(255, 0, 0), (255, 184, 255), (0, 255, 255), (255, 184, 82)]

INFO = M.validate()


def solid(c, r):
    return M.is_wall(c, r) and not (r < 0 or r >= M.ROWS)


def render(cell, cy_off, label):
    """cell = px per tile, cy_off = maze centre offset from screen centre."""
    img = Image.new("RGB", (W, H), (18, 18, 18))
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, W - 1, H - 1], fill=BG)

    mw, mh = M.COLS * cell, M.ROWS * cell
    x0 = (W - mw) / 2.0
    y0 = (H - mh) / 2.0 + cy_off

    def px(c, r):
        return x0 + c * cell, y0 + r * cell

    def visible(c, r):
        cx, cyy = x0 + (c + .5) * cell, y0 + (r + .5) * cell
        return ((cx - 195) ** 2 + (cyy - 195) ** 2) ** .5 <= SAFE

    inset = max(1.0, cell * 0.22)
    lw = 1 if cell < 11 else 2
    clipped = 0

    for r in range(M.ROWS):
        for c in range(M.COLS):
            ch = M.MAZE[r][c]
            vis = visible(c, r)
            if ch not in " " and not vis:
                clipped += 1
            ax, ay = px(c, r)
            bx, by = ax + cell, ay + cell
            col = WALL if vis else CLIP

            if ch == "-":                                  # ghost-house door
                d.line([ax, ay + cell / 2, bx, ay + cell / 2],
                       fill=DOOR if vis else CLIP, width=max(2, lw))
            elif ch == "#":
                # Arcade style: draw the BOUNDARY of each wall blob, inset.
                # Two 1-tile walls either side of a corridor therefore render
                # as the game's signature double line.
                if not solid(c, r - 1):
                    d.line([ax, ay + inset, bx, ay + inset], fill=col, width=lw)
                if not solid(c, r + 1):
                    d.line([ax, by - inset, bx, by - inset], fill=col, width=lw)
                if not solid(c - 1, r):
                    d.line([ax + inset, ay, ax + inset, by], fill=col, width=lw)
                if not solid(c + 1, r):
                    d.line([bx - inset, ay, bx - inset, by], fill=col, width=lw)
            elif ch == ".":
                s = max(1.0, cell * 0.16)
                cx, cyy = ax + cell / 2, ay + cell / 2
                d.rectangle([cx - s, cyy - s, cx + s, cyy + s],
                            fill=DOT if vis else CLIP)
            elif ch == "o":
                s = max(2.5, cell * 0.36)
                cx, cyy = ax + cell / 2, ay + cell / 2
                d.ellipse([cx - s, cyy - s, cx + s, cyy + s],
                          fill=DOT if vis else CLIP)

    # Sprites, at their arcade start tiles.
    def sprite(c, r, col, frac=0.86):
        cx, cyy = x0 + (c + .5) * cell, y0 + (r + .5) * cell
        s = cell * frac
        d.ellipse([cx - s / 2, cyy - s / 2, cx + s / 2, cyy + s / 2], fill=col)

    sprite(14, 23, PACMAN, 1.0)                     # Pac-Man start
    for i, (c, r) in enumerate([(14, 11), (14, 14), (12, 14), (16, 14)]):
        sprite(c, r, GHOSTS[i])

    # Caption
    d.rectangle([0, 0, W, 22], fill=(18, 18, 18))
    d.text((6, 6), "%s   cell=%dpx  maze=%dx%d  clipped tiles=%d"
           % (label, cell, mw, mh, clipped), fill=(255, 255, 255))
    return img, clipped


OPTS = [
    (8,  22, "A  8px, pushed down"),
    (9,   0, "B  9px, centred"),
    (11,  0, "C  11px, centred"),
    (13,  0, "D  13px, centred"),
]

imgs = []
for cell, off, label in OPTS:
    im, clip = render(cell, off, label)
    imgs.append(im)
    print("%-22s cell=%2d  maze=%3dx%3d  clipped=%3d / %d tiles"
          % (label, cell, M.COLS * cell, M.ROWS * cell, clip,
             INFO["open"] + (M.COLS * M.ROWS - INFO["open"])))

sheet = Image.new("RGB", (W * 2 + 12, H * 2 + 12), (60, 60, 60))
for i, im in enumerate(imgs):
    sheet.paste(im, ((i % 2) * (W + 12), (i // 2) * (H + 12)))
sheet.save("tools/layout_compare.png")
print("\nwrote tools/layout_compare.png")
