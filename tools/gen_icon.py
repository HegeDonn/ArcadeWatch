#!/usr/bin/env python3
"""56x56 launcher icon: Pac-Man about to eat a pellet.

Drawn at 8x and downsampled. Geometry is stated explicitly and then checked,
because the first version computed the pie's bounding box as
[c - r, ...] with c smaller than r -- so its left edge landed at x = -20 and
the circle was clipped flat against the canvas. It looked like a bite taken
out of the back of his head.
"""
from PIL import Image, ImageDraw

S = 56                      # final icon, per the vivoactive 5 device profile
SS = 8                      # supersample factor
W = S * SS

R = 150                     # Pac-Man radius
PR = 26                     # pellet radius
GAP = 40                    # space between his mouth and the pellet
MOUTH = 30                  # half-angle of the mouth, degrees

# Lay the content out left-to-right, then centre the whole group.
content = 2 * R + GAP + 2 * PR
left = (W - content) // 2
cx, cy = left + R, W // 2
px = left + 2 * R + GAP + PR

pac = [cx - R, cy - R, cx + R, cy + R]
pellet = [px - PR, cy - PR, px + PR, cy + PR]
for name, box in (("pac", pac), ("pellet", pellet)):
    assert box[0] >= 0 and box[1] >= 0 and box[2] <= W and box[3] <= W, \
        "%s box %s falls outside the 0..%d canvas and would be clipped" % (name, box, W)

img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
d.pieslice(pac, MOUTH, 360 - MOUTH, fill=(255, 255, 0, 255))
d.ellipse(pellet, fill=(255, 184, 174, 255))

# Nothing lit may touch the border, or something is still being cut off.
a = img.split()[3]
bbox = a.getbbox()
assert bbox[0] > 0 and bbox[1] > 0 and bbox[2] < W and bbox[3] < W, \
    "artwork touches the canvas edge: %s in 0..%d" % (bbox, W)

img.resize((S, S), Image.LANCZOS).save("resources/drawables/launcher_icon.png")
print("wrote resources/drawables/launcher_icon.png (%dx%d)" % (S, S))
print("  pac %s  pellet %s" % (pac, pellet))
print("  margins: left %d, right %d, top %d, bottom %d (all must be > 0)"
      % (bbox[0], W - bbox[2], bbox[1], W - bbox[3]))
