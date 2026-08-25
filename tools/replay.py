#!/usr/bin/env python3
"""Replay a trace captured from the Connect IQ simulator and render it with
the pixel-exact renderer, so we can see what the watch is actually doing.

  python3 tools/replay.py /tmp/pactrace2.log
"""
import sys
from PIL import Image, ImageDraw
import maze as M
import render as R

LOG = sys.argv[1] if len(sys.argv) > 1 else "/tmp/pactrace2.log"
TIME, DATE = "21:47", "SUN 24 AUG"

rows = [l.strip().split("|") for l in open(LOG) if l.startswith("T|")]
if not rows:
    raise SystemExit("no trace lines in " + LOG)

ALL_DOT = {(c, r) for r in range(M.ROWS) for c in range(M.COLS) if M.MAZE[r][c] == "."}
ALL_PWR = {(c, r) for r in range(M.ROWS) for c in range(M.COLS) if M.MAZE[r][c] == "o"}


def compose(rec, dots, pwr):
    fno, state = int(rec[1]), int(rec[2])
    pac = [int(v) for v in rec[3].split(",")]
    gh = [[int(v) for v in rec[i].split(",")] for i in (4, 5, 6, 7)]
    fright = int(rec[10]); lives = int(rec[11]); level = int(rec[12])
    flashing = (state == 3)
    wall = R.FLASH if (flashing and (0 // 4) % 2 == 0) else R.WALL

    img = Image.new("RGB", (R.W, R.H), (16, 16, 16))
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, R.W - 1, R.H - 1], fill=R.BG)
    R.draw_maze(d, dots, wall)

    if not flashing:
        if (fno // 5) % 2 == 0:
            for (c, r) in pwr:
                d.ellipse([R.tileX(c) - R.PWRR, R.tileY(r) - R.PWRR,
                           R.tileX(c) + R.PWRR, R.tileY(r) + R.PWRR], fill=R.DOT)
        flash = 0 < fright < 30 and (fno // 3) % 2 == 0
        if state != 2:
            for i, g in enumerate(gh):
                R.draw_ghost(d, i, g[0], g[1], g[2], g[3], g[4], g[5], flash)
        if state != 4:
            R.draw_pac(d, pac[0], pac[1], pac[2], pac[3],
                       (pac[4] // 3) % 4 if False else ((fno % 12) // 3) % 3 + 0,
                       pac[4] if state == 2 else None)

    R.text(d, TIME, 4, (255, 255, 255), R.W // 2, R.SCOREY)

    # lives + level fruit
    for i in range(min(max(lives - 1, 0), 3)):
        x = R.W // 2 - 34 + i * (R.GR * 2 + 4)
        d.ellipse([x - R.GR, R.LIVESY, x + R.GR, R.LIVESY + R.GR * 2], fill=R.PAC)
    for i in range(min(level, 4)):
        fx = R.W // 2 + 16 + i * (R.GR * 2 + 3)
        d.ellipse([fx - R.GR + 1, R.LIVESY + 2, fx + R.GR - 1, R.LIVESY + R.GR * 2],
                  fill=R.FRUIT)
        d.rectangle([fx - 1, R.LIVESY + R.GR - 4, fx, R.LIVESY + R.GR - 2], fill=(0, 160, 0))

    if state in (0, 4):
        over = state == 4
        th, sh = 49, 21
        tw, dw = R.bm_width(TIME, 7), R.bm_width(DATE, 3)
        bw = max(tw, dw) + 26
        bh = th + sh + 16 + (sh + 6 if over else 0)
        cx, cy = R.W // 2, R.tileY(14)
        top = cy - bh // 2
        d.rectangle([cx - bw // 2, top - 6, cx + bw // 2, top - 6 + bh + 12], fill=R.BG)
        if over:
            R.text(d, "GAME OVER", 3, R.FRUIT, cx, top)
            top += sh + 6
        R.text(d, TIME, 7, R.PAC, cx, top)
        R.text(d, DATE, 3, (255, 255, 255), cx, top + th + 10)
    return img


# Walk the whole trace so the dot field is correct at any frame we pick.
dots, pwr = set(ALL_DOT), set(ALL_PWR)
level = int(rows[0][12])
frames = {}
want = set()
picks = []
for i, rec in enumerate(rows):
    if int(rec[12]) != level:
        level = int(rec[12]); dots, pwr = set(ALL_DOT), set(ALL_PWR)
    ec, er = (int(v) for v in rec[8].split(","))
    if ec >= 0:
        dots.discard((ec, er)); pwr.discard((ec, er))
    frames[i] = (set(dots), set(pwr))

states = [int(r[2]) for r in rows]
frights = [int(r[10]) for r in rows]


def find(pred, n=1, skip=0):
    out = []
    for i, r in enumerate(rows):
        if pred(i, r):
            if skip > 0:
                skip -= 1; continue
            out.append(i)
            if len(out) == n:
                break
    return out


picks += find(lambda i, r: states[i] == 0, 1, 20)                       # READY
picks += find(lambda i, r: states[i] == 1, 1, 120)                      # early play
picks += find(lambda i, r: states[i] == 1 and frights[i] > 0, 1, 10)    # frightened
picks += find(lambda i, r: any(int(r[k].split(',')[5]) == 3 for k in (4,5,6,7)), 1)  # eyes
picks += find(lambda i, r: states[i] == 2, 1, 8)                        # dying
picks += find(lambda i, r: states[i] == 4, 1, 10)                       # GAME OVER
labels = ["READY - clock panel", "play", "power pellet: ghosts flee",
          "eaten ghost, eyes going home", "death animation", "GAME OVER"]

tiles = []
for p, lab in zip(picks, labels):
    dd, pp = frames[p]
    im = compose(rows[p], dd, pp)
    tiles.append((im, "%s  f=%s" % (lab, rows[p][1])))

cols = 3
rowsn = (len(tiles) + cols - 1) // cols
sheet = Image.new("RGB", (R.W * cols + 8 * (cols + 1), (R.H + 20) * rowsn + 8),
                  (55, 55, 55))
sd = ImageDraw.Draw(sheet)
for i, (im, lab) in enumerate(tiles):
    x = 8 + (i % cols) * (R.W + 8)
    y = 8 + (i // cols) * (R.H + 20)
    sheet.paste(im, (x, y))
    sd.text((x + 4, y + R.H + 4), lab, fill=(230, 230, 230))
sheet.save("tools/replay_sheet.png")
print("wrote tools/replay_sheet.png from %d traced frames" % len(rows))
