"""The authentic 28x31 Pac-Man playfield, shared by every tool here.

Legend
  #  wall            .  dot            o  power pellet
  -  ghost-house door        (space) open, no dot
Row 14 is the wrap tunnel: open at both ends.
"""

MAZE = [
    "############################",  # 0
    "#............##............#",  # 1
    "#.####.#####.##.#####.####.#",  # 2
    "#o####.#####.##.#####.####o#",  # 3
    "#.####.#####.##.#####.####.#",  # 4
    "#..........................#",  # 5
    "#.####.##.########.##.####.#",  # 6
    "#.####.##.########.##.####.#",  # 7
    "#......##....##....##......#",  # 8
    "######.##### ## #####.######",  # 9
    "     #.##### ## #####.#     ",  # 10
    "     #.##          ##.#     ",  # 11
    "     #.## ###--### ##.#     ",  # 12
    "######.## #      # ##.######",  # 13
    "          #      #          ",  # 14  <- tunnel row
    "######.## #      # ##.######",  # 15
    "     #.## ######## ##.#     ",  # 16
    "     #.##          ##.#     ",  # 17
    "     #.## ######## ##.#     ",  # 18
    "######.## ######## ##.######",  # 19
    "#............##............#",  # 20
    "#.####.#####.##.#####.####.#",  # 21
    "#.####.#####.##.#####.####.#",  # 22
    "#o..##................##..o#",  # 23
    "###.##.##.########.##.##.###",  # 24
    "###.##.##.########.##.##.###",  # 25
    "#......##....##....##......#",  # 26
    "#.##########.##.##########.#",  # 27
    "#.##########.##.##########.#",  # 28
    "#..........................#",  # 29
    "############################",  # 30
]

COLS = 28
ROWS = 31

WALLS = "#-"


def is_wall(c, r):
    if r < 0 or r >= ROWS:
        return True
    if c < 0 or c >= COLS:
        return False          # tunnel mouths are open, not wall
    return MAZE[r][c] in WALLS


def validate():
    """Fail loudly on a malformed maze; report dot counts + connectivity."""
    errs = []
    for r, row in enumerate(MAZE):
        if len(row) != COLS:
            errs.append("row %d is %d cols, want %d" % (r, len(row), COLS))
    if len(MAZE) != ROWS:
        errs.append("maze is %d rows, want %d" % (len(MAZE), ROWS))
    if errs:
        raise SystemExit("MAZE MALFORMED:\n  " + "\n  ".join(errs))

    dots = sum(row.count(".") for row in MAZE)
    pwr = sum(row.count("o") for row in MAZE)

    # Flood-fill every walkable tile from Pac-Man's start (13.5, 23) -> tile 14,23
    open_tiles = {(c, r) for r in range(ROWS) for c in range(COLS)
                  if MAZE[r][c] not in WALLS}
    seen, stack = set(), [(14, 23)]
    while stack:
        c, r = stack.pop()
        if (c, r) in seen or (c, r) not in open_tiles:
            continue
        seen.add((c, r))
        for dc, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nc, nr = c + dc, r + dr
            if nc < 0:
                nc = COLS - 1          # wrap tunnel
            elif nc >= COLS:
                nc = 0
            stack.append((nc, nr))

    orphans = open_tiles - seen
    # The ghost house interior is walled off behind the door -- expected.
    house = {(c, r) for c in range(10, 18) for r in range(12, 16)}
    # Blank margins beside the tunnel rows are black void, not playfield.
    # Row 14 is the wrap tunnel -- its wide margins are corridor, not void.
    void = {(c, r) for r in range(9, 20) if r != 14 for c in range(COLS)
            if MAZE[r][c] == ' ' and (c < 6 or c > 21)}
    orphans -= void
    real_orphans = orphans - house
    return {
        "dots": dots, "power": pwr, "open": len(open_tiles),
        "reachable": len(seen), "orphans": sorted(real_orphans),
    }


if __name__ == "__main__":
    info = validate()
    print("dots=%(dots)d power=%(power)d open=%(open)d reachable=%(reachable)d"
          % info)
    print("unreachable (excl. ghost house):", info["orphans"] or "none")


# ---------------------------------------------------------------------------
# Wall outlines.
#
# The outline is the boundary between wall and open tiles, inset into the wall
# side. Drawing one line per tile edge costs 732 calls -- over the vivoactive
# 5's ~700-call watchdog -- so collinear edges merge into runs here, at build
# time.
#
# The subtlety is the ends. A run spanning whole tiles overshoots its corner by
# `inset` in both directions, and two such runs meeting at a corner cross in a
# little plus sign. So each end is adjusted by one inset:
#
#   convex corner  (the wall stops here)      -> pull the end IN by inset,
#                                                so it meets the perpendicular
#                                                run exactly on the corner
#   concave corner (the wall turns and goes on) -> push the end OUT by inset,
#                                                so it reaches the run coming
#                                                the other way
#
# Records are [type, a, b, fixed, s, e] with s and e in {+1, -1}: the sign of
# the inset to apply at each end. Kept here rather than in the generator so
# the offline renderer and the watch cannot drift apart.
#
#   type 0 top edge     y = fixed*C + inset        x = a*C + s*inset .. (b+1)*C + e*inset
#   type 1 bottom edge  y = (fixed+1)*C - inset    x likewise
#   type 2 left edge    x = fixed*C + inset        y = a*C + s*inset .. (b+1)*C + e*inset
#   type 3 right edge   x = (fixed+1)*C - inset    y likewise

def _solid(c, r):
    return 0 <= r < ROWS and 0 <= c < COLS and MAZE[r][c] == "#"


def wall_runs():
    out = []

    for r in range(ROWS):
        for kind, dr in ((0, -1), (1, 1)):          # top edge, bottom edge
            c = 0
            while c < COLS:
                if _solid(c, r) and not _solid(c, r + dr):
                    c0 = c
                    while c < COLS and _solid(c, r) and not _solid(c, r + dr):
                        c += 1
                    c1 = c - 1
                    s = -1 if _solid(c0 - 1, r) else 1
                    e = 1 if _solid(c1 + 1, r) else -1
                    out.append((kind, c0, c1, r, s, e))
                else:
                    c += 1

    for c in range(COLS):
        for kind, dc in ((2, -1), (3, 1)):          # left edge, right edge
            r = 0
            while r < ROWS:
                if _solid(c, r) and not _solid(c + dc, r):
                    r0 = r
                    while r < ROWS and _solid(c, r) and not _solid(c + dc, r):
                        r += 1
                    r1 = r - 1
                    s = -1 if _solid(c, r0 - 1) else 1
                    e = 1 if _solid(c, r1 + 1) else -1
                    out.append((kind, r0, r1, c, s, e))
                else:
                    r += 1

    return out
