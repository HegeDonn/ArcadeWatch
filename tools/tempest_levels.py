"""Tempest level shapes.

A level is a rim: a list of points the tube's near edge passes through. The
far end is the same outline shrunk toward the centre, which is what gives the
tube its cross-section. So the rim is the level -- a circle, a square, a plus,
a pinwheel, or an open strip you cannot wrap around.

Shapes are defined by their corners, and each edge is then split into a fixed
number of pieces. Corners are always kept -- resampling evenly along the
perimeter instead loses them, and a plus with its corners rounded off is just
a blob. Segment counts therefore vary per level, exactly as they do in the
cabinet. Coordinates are normalised to +/-1000.
"""
import math


def subdivide(corners, per_edge, closed=True):
    """Split every edge into per_edge pieces, keeping the corners themselves."""
    pts = []
    n = len(corners)
    last = n if closed else n - 1
    for i in range(last):
        x0, y0 = corners[i]
        x1, y1 = corners[(i + 1) % n]
        for k in range(per_edge):
            t = k / float(per_edge)
            pts.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
    if not closed:
        pts.append(corners[-1])
    return pts


def circle(n=16, r=1000):
    return [(r * math.cos(2 * math.pi * i / n - math.pi / 2),
             r * math.sin(2 * math.pi * i / n - math.pi / 2)) for i in range(n)]


def star(points=8, outer=1000, inner=420):
    out = []
    for i in range(points * 2):
        r = outer if i % 2 == 0 else inner
        a = math.pi * i / points - math.pi / 2
        out.append((r * math.cos(a), r * math.sin(a)))
    return out


def square(s=880):
    return subdivide([(-s, -s), (s, -s), (s, s), (-s, s)], 4)


def plus(a=330, b=980):
    return [(-a, -b), (a, -b), (a, -a), (b, -a), (b, a), (a, a),
            (a, b), (-a, b), (-a, a), (-b, a), (-b, -a), (-a, -a)]


def vee(w=980, d=720):
    """Open: a trough with walls at each end, so you cannot wrap around."""
    return subdivide([(-w, -d), (-w * 0.42, d), (w * 0.42, d), (w, -d)],
                     4, closed=False)


LEVELS = [
    ("circle",   circle(),   True),
    ("square",   square(),   True),
    ("plus",     plus(),     True),
    ("pinwheel", star(8),    True),
    ("vee",      vee(),      False),
]


def segments(pts, closed):
    return len(pts) if closed else len(pts) - 1


def selftest():
    for name, pts, closed in LEVELS:
        assert len(pts) >= 8, "%s has too few points" % name
        for x, y in pts:
            assert -1100 <= x <= 1100 and -1100 <= y <= 1100, "%s out of range" % name
    return True


def preview(pts, closed, w=41, h=21):
    grid = [[" "] * w for _ in range(h)]
    ring = list(pts) + ([pts[0]] if closed else [])
    for i in range(len(ring) - 1):
        x0, y0 = ring[i]
        x1, y1 = ring[i + 1]
        steps = max(2, int(math.hypot(x1 - x0, y1 - y0) / 40))
        for t in range(steps + 1):
            f = t / float(steps)
            gx = int((x0 + (x1 - x0) * f) / 1000 * (w // 2 - 1) + w // 2)
            gy = int((y0 + (y1 - y0) * f) / 1000 * (h // 2 - 1) + h // 2)
            if 0 <= gx < w and 0 <= gy < h:
                grid[gy][gx] = "*"
    return ["   " + "".join(r) for r in grid]


if __name__ == "__main__":
    selftest()
    for name, pts, closed in LEVELS:
        print("%-9s %2d points, %2d segments, %s"
              % (name, len(pts), segments(pts, closed),
                 "closed" if closed else "OPEN"))
