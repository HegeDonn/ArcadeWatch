"""Pixel icons for the sensor read-outs. HAND-EDITED -- this is the source
of truth, nothing generates it.

Both are filled shapes; the sensor number is knocked *out* of them in black,
which reads far better at 4x than white digits inside a hairline outline.

To change one: edit the art below, keeping every row exactly W characters
('#' lit, '.' empty), then run

    python3 tools/gen_icons_mc.py

The two constraints that matter:
  * W must stay 15 -- that is what fits the 60 px margin beside the maze
    at scale 4. Heights may differ per icon; each is centred independently.
  * The four rows named by *_TEXT_ROWS must each contain an unbroken run of
    at least 9 '#'. That is the 36 px a three-digit reading needs; narrower
    and the digits clip out through the side of the shape.

tools/gen_icon_art.py can propose a starting shape from geometry, but it
writes tools/icons_suggested.py -- it will not clobber this file.
"""

W = 15

HEART = [
    "..###.....###..",
    ".#####...#####.",
    "#######.#######",
    "###############",
    "###############",
    ".#############.",
    "..###########..",
    "...#########...",
    "....#######....",
    ".....#####.....",
    "......###......",
    ".......#.......",
]
HEART_H = 12
HEART_TEXT_ROWS = (3, 6)

BODY = [
    "......###......",
    ".....#####.....",
    "....#######....",
    "....#######....",
    "....#######....",
    ".....#####.....",
    "......###......",
    ".....#####.....",
    "....#######....",
    "...#########...",
    "..###########..",
    ".#############.",
    ".#############.",
    ".#############.",
    ".#############.",
    ".#############.",
]
BODY_H = 16
BODY_TEXT_ROWS = (11, 14)


def runs(art):
    """Merge each row's lit pixels into horizontal runs: (row, x0, x1)."""
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
    for name, art, rows in (("HEART", HEART, HEART_TEXT_ROWS),
                            ("BODY", BODY, BODY_TEXT_ROWS)):
        for i, r in enumerate(art):
            assert len(r) == W, "%s row %d is %d wide, want %d" % (name, i, len(r), W)
        for y in range(rows[0], rows[1] + 1):
            best = run = 0
            for ch in art[y]:
                run = run + 1 if ch == "#" else 0
                best = max(best, run)
            assert best >= 9, ("%s text row %d has only %d solid cells; a "
                               "three-digit number needs 9" % (name, y, best))
    return True


if __name__ == "__main__":
    selftest()
    for name, art in (("HEART", HEART), ("BODY", BODY)):
        print(name, "%dx%d" % (W, len(art)))
        print("     " + "".join(str(c % 10) for c in range(W)))
        for y, r in enumerate(art):
            print("  %2d %s" % (y, r))
        print()
