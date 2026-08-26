"""Invader sprites. HAND-EDITED -- this is the source of truth.

Three ranks, two animation frames each, 6x5, drawn at 2x on the watch.

Deliberately tiny and blocky. The whole formation is redrawn every frame, so
cost is 55 sprites x however many horizontal runs each takes: at 11x8 the
detailed originals came to ~16 runs apiece, or 880 calls, which is over the
vivoactive 5's ~700-call watchdog. At 6x5 they are 6-8 runs, and the
formation lands around 400.

Every row must be W characters.
"""

W, H = 6, 5

# top rank
SQUID = [[
    ".####.",
    "######",
    "##..##",
    ".#..#.",
    "#.##.#",
], [
    ".####.",
    "######",
    "##..##",
    "#.##.#",
    ".#..#.",
]]

# middle ranks
CRAB = [[
    "#....#",
    ".####.",
    "##..##",
    "######",
    "#.##.#",
], [
    "#....#",
    "#####.",
    "##..##",
    "######",
    ".#..#.",
]]

# bottom ranks
OCTO = [[
    ".####.",
    "######",
    "#.##.#",
    ".####.",
    "#.##.#",
], [
    ".####.",
    "######",
    "#.##.#",
    ".####.",
    ".#..#.",
]]

RANKS = [SQUID, CRAB, CRAB, OCTO, OCTO]      # five rows, top to bottom


def runs(art):
    out = []
    for y, row in enumerate(art):
        x = 0
        while x < W:
            if row[x] == "#":
                x0 = x
                while x < W and row[x] == "#":
                    x += 1
                out.append((y, x0, x - 1))
            else:
                x += 1
    return out


def selftest():
    for name, frames in (("SQUID", SQUID), ("CRAB", CRAB), ("OCTO", OCTO)):
        for i, art in enumerate(frames):
            assert len(art) == H, "%s[%d] has %d rows" % (name, i, len(art))
            for y, r in enumerate(art):
                assert len(r) == W, "%s[%d] row %d is %d wide" % (name, i, y, len(r))
    return True


if __name__ == "__main__":
    selftest()
    for name, frames in (("SQUID", SQUID), ("CRAB", CRAB), ("OCTO", OCTO)):
        print("%s  (%d runs / %d runs)" % (name, len(runs(frames[0])), len(runs(frames[1]))))
        for a, b in zip(frames[0], frames[1]):
            print("   " + a.replace(".", " ").replace("#", "█")
                  + "    " + b.replace(".", " ").replace("#", "█"))
        print()
