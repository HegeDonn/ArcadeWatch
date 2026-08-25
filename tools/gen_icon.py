#!/usr/bin/env python3
"""56x56 launcher icon: Pac-Man about to eat a pellet."""
from PIL import Image, ImageDraw

S = 56
img = Image.new("RGBA", (S * 8, S * 8), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
c, r = S * 8 // 2 - 60, S * 8 // 2 - 40
d.pieslice([c - r, c + 40 - r, c + r, c + 40 + r], 32, 328, fill=(255, 255, 0, 255))
d.ellipse([S * 8 - 130, S * 8 // 2 - 26, S * 8 - 78, S * 8 // 2 + 26],
          fill=(255, 184, 174, 255))
img.resize((S, S), Image.LANCZOS).save("resources/drawables/launcher_icon.png")
print("wrote resources/drawables/launcher_icon.png (%dx%d)" % (S, S))
