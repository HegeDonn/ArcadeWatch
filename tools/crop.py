"""Crop a simulator capture down to exactly the 390x390 watch screen.

Anchors on the maze's outer wall, whose logical extent is fixed: x 70..320
(250 px) and y 56 at the top.

It does NOT look for a known colour, and that is deliberate -- two earlier
versions broke on exactly that. The wall colour is swipeable (six themes),
and the simulator puts the framebuffer through a colour-profile transform, so
0xFF2D95 arrives as roughly (176, 48, 104): not a per-channel scale, so not
worth modelling. Instead the dominant saturated colour in the window interior
*is* the maze by definition -- it is thousands of pixels where window chrome
is tens -- so we find it by histogram and calibrate off that.
"""
import sys
from collections import Counter
from PIL import Image

Q = 8            # histogram bucket size
TOL = 26         # match distance to the winning bucket


def crop(path, out=None):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    y_lo, y_hi = int(h * 0.10), int(h * 0.94)

    hist = Counter()
    for y in range(y_lo, y_hi, 2):
        for x in range(0, w, 2):
            r, g, b = px[x, y]
            if max(r, g, b) > 90 and max(r, g, b) - min(r, g, b) > 60:
                hist[(r // Q * Q, g // Q * Q, b // Q * Q)] += 1
    if not hist:
        return None
    (wr, wg, wb), n = hist.most_common(1)[0]
    if n < 300:
        return None

    xs, ys = [], []
    for y in range(y_lo, y_hi, 2):
        for x in range(0, w, 2):
            r, g, b = px[x, y]
            if abs(r - wr) < TOL and abs(g - wg) < TOL and abs(b - wb) < TOL:
                xs.append(x); ys.append(y)
    if len(xs) < 300:
        return None

    xs.sort(); ys.sort()
    lo = len(xs) // 200                       # trim 0.5% of outliers each end
    x0, x1 = xs[lo], xs[-1 - lo]
    y0 = ys[lo]
    scale = (x1 - x0) / 250.0
    if not (0.3 < scale < 4.0):
        return None
    sx = x0 - 70 * scale
    sy = y0 - 56 * scale
    side = 390 * scale
    if sx < -8 or sy < -8 or sx + side > w + 8 or sy + side > h + 8:
        return None
    return im.crop((int(sx), int(sy), int(sx + side), int(sy + side))) \
             .resize((390, 390), Image.LANCZOS)


if __name__ == "__main__":
    r = crop(sys.argv[1])
    if r is None:
        print("no maze found in", sys.argv[1])
    else:
        r.save(sys.argv[2]); print("wrote", sys.argv[2])
