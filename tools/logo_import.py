# logo_import.py - turns the big STAR CIRCUIT logo picture into a crisp
# game-sized logo for the title screen.
#
# The source picture (2000 x 1116) is pixel art drawn with big blocky
# "pixels" about 8.2 screen pixels wide, and its see-through background is a
# FAKE: a grey/white checkerboard painted into the picture. This script
#   1. finds the art-pixel grid (where each big pixel starts),
#   2. reads the colour in the MIDDLE of each big pixel -> a small, sharp image,
#   3. keeps only real logo pixels (colourful ones, dark outlines, the white
#      astronaut) - the checkerboard greys and the pale glow haze become
#      transparent,
#   4. removes leftover specks that aren't connected to the logo.
# Result: Assets/images/ui/logo.png (about 244 x 136), shown 1:1 on the title
# screen so its pixels match the game's pixels.
#
#   python tools/logo_import.py <source picture> [scale]
import sys
import numpy as np
from PIL import Image

SRC = sys.argv[1]
SCALE = float(sys.argv[2]) if len(sys.argv) > 2 else 8.2
OUT = 'Assets/images/ui/logo.png'
CHECKER = [(173, 177), (226, 230)]      # the two greys of the fake checkerboard


def best_offset(img: np.ndarray, axis: int) -> float:
    """Where does the grid start? Try offsets and keep the one where most colour
    changes ('edges') land on grid lines."""
    diff = np.abs(np.diff(img, axis=axis)).sum(axis=2) > 60
    edges = np.nonzero(diff.sum(axis=1 - axis) > 3)[0] + 1
    best, best_score = 0.0, -1
    for off in np.arange(0, SCALE, 0.1):
        d = np.abs(((edges - off) / SCALE) - np.round((edges - off) / SCALE))
        score = (d < 0.15).sum()
        if score > best_score:
            best, best_score = off, score
    return best


src = np.asarray(Image.open(SRC).convert('RGB')).astype(int)
H, W, _ = src.shape
ox = best_offset(src, 1)
oy = best_offset(src, 0)
xs = np.arange(ox, W - SCALE / 2, SCALE) + SCALE / 2
ys = np.arange(oy, H - SCALE / 2, SCALE) + SCALE / 2
small = src[np.clip(ys.astype(int), 0, H - 1)][:, np.clip(xs.astype(int), 0, W - 1)]

r, g, b = small[..., 0], small[..., 1], small[..., 2]
hi_c = small.max(axis=2)
lo_c = small.min(axis=2)
colourful = (hi_c - lo_c) >= 70          # letters, wires, stars, planet
dark = hi_c < 110                        # outlines, plugs
# The glow around the wires was painted over the checkerboard, so it came out
# as pale grey-blue haze: anything pale and not very colourful is background.
keep = colourful | dark
# ...except the astronaut, whose suit IS white: keep bright pixels near him.
h, w = keep.shape
ys_i, xs_i = np.mgrid[0:h, 0:w]
astro = (xs_i > w * 0.86) & (ys_i > h * 0.42) & (ys_i < h * 0.72)
checker = np.zeros(keep.shape, bool)
grey = (np.abs(r - g) <= 6) & (np.abs(g - b) <= 6)
for lo, hi in CHECKER:
    checker |= grey & (r >= lo - 3) & (r <= hi + 3)
suit = (hi_c > 225) | ((hi_c > 150) & ~grey)        # white suit, or tinted shading
keep |= astro & ~checker & suit
alpha = np.where(keep, 255, 0)

# keep only the big connected logo, drop lone specks of leftover background
keep = alpha > 0
seen = np.zeros_like(keep)
h, w = keep.shape
for y0 in range(h):
    for x0 in range(w):
        if not keep[y0, x0] or seen[y0, x0]:
            continue
        stack, blob = [(y0, x0)], []
        seen[y0, x0] = True
        while stack:
            y, x = stack.pop()
            blob.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and keep[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        if len(blob) < 12:
            for y, x in blob:
                alpha[y, x] = 0

rgba = np.dstack([small, alpha]).astype(np.uint8)
img = Image.fromarray(rgba, 'RGBA')
img = img.crop(img.getbbox())             # trim the empty border
img.save(OUT)
print(f'grid {SCALE} px, offset ({ox:.1f}, {oy:.1f}) -> {OUT} {img.size}')
