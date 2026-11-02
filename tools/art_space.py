# art_space.py - draws the pixel art added for Level 2 (the spacewalk) and the power cells.
#
# Everything is drawn pixel by pixel in code (no downloads). It ADDS to the existing sheets
# without touching their original pictures: it keeps the first 12 icons of layout_tiles.png
# and the first 9 pictures of puzzle_tiles.png and draws the new ones after them, so running
# it twice gives the same result.
#
#   layout_tiles.png  +4 palette icons: 12 cell, 13 hull, 14 space, 15 airlock
#   puzzle_tiles.png  +3 pictures:      9 gangway (retracted), 10 gangway (extended), 11 airlock pad
#   hull.png          3 hull plates (outside floor): plain, scuffed, vent
#   space/planet.png, space/nebula.png  background art for the starfield
#
# Run from the project folder:   python tools/art_space.py
import numpy as np
from PIL import Image

T = 32
rng = np.random.default_rng(11)

NAVY = (5, 9, 34, 255)
PAD_GREY = (109, 119, 130, 255)
CLEAR = (0, 0, 0, 0)


def tile():
    return Image.new('RGBA', (T, T), CLEAR)


def rect(im, x0, y0, x1, y1, col):
    """Fill pixels x0..x1, y0..y1 (inclusive)."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 0 <= x < im.width and 0 <= y < im.height:
                im.putpixel((x, y), col)


def outline(im, x0, y0, x1, y1, col):
    rect(im, x0, y0, x1, y0, col)
    rect(im, x0, y1, x1, y1, col)
    rect(im, x0, y0, x0, y1, col)
    rect(im, x1, y0, x1, y1, col)


def pad_base(border):
    """The rounded pad shape every puzzle tile uses: navy outline, grey inside, coloured border."""
    im = tile()
    rect(im, 1, 0, 30, 31, NAVY)
    rect(im, 0, 1, 31, 30, NAVY)
    rect(im, 2, 1, 29, 30, PAD_GREY)
    rect(im, 1, 2, 30, 29, PAD_GREY)
    outline(im, 3, 3, 28, 28, border)
    rect(im, 4, 2, 27, 2, border)
    rect(im, 4, 29, 27, 29, border)
    rect(im, 2, 4, 2, 27, border)
    rect(im, 29, 4, 29, 27, border)
    return im


def battery(im, cx, top, body, dark, cap):
    """A small battery: 8 wide x 13 tall, lightning stripe in the middle."""
    x0 = cx - 4
    rect(im, x0 + 2, top, x0 + 5, top + 1, cap)               # the + cap
    rect(im, x0, top + 2, x0 + 7, top + 13, dark)              # outline
    rect(im, x0 + 1, top + 3, x0 + 6, top + 12, body)          # body
    rect(im, x0 + 1, top + 3, x0 + 1, top + 12, tuple(min(255, c + 50) for c in body[:3]) + (255,))
    for (x, y) in [(4, 5), (3, 6), (2, 7), (3, 7), (4, 7), (5, 7), (4, 8), (3, 9)]:
        im.putpixel((x0 + x, top + y + 1), dark)


# ------------------------------------------------------------------ hull plates (outside floor)
HULL = (146, 154, 167)
HULL_HI = (176, 184, 196)
HULL_LO = (104, 110, 122)
HULL_SEAM = (62, 66, 76)


def hull_plate(variant):
    im = Image.new('RGBA', (T, T), HULL + (255,))
    rect(im, 0, 0, 31, 0, HULL_HI + (255,))
    rect(im, 0, 0, 0, 31, HULL_HI + (255,))
    rect(im, 1, 30, 31, 30, HULL_LO + (255,))
    rect(im, 30, 1, 30, 30, HULL_LO + (255,))
    rect(im, 0, 31, 31, 31, HULL_SEAM + (255,))
    rect(im, 31, 0, 31, 31, HULL_SEAM + (255,))
    for (x, y) in [(3, 3), (27, 3), (3, 27), (27, 27)]:          # rivets
        rect(im, x, y, x + 1, y + 1, (92, 98, 109, 255))
        im.putpixel((x, y), (196, 202, 212, 255))
    if variant == 1:                                              # scuffs
        for _ in range(7):
            x, y = int(rng.integers(6, 25)), int(rng.integers(6, 25))
            for k in range(int(rng.integers(2, 5))):
                if x + k < 31:
                    im.putpixel((x + k, y + (k // 2)), (124, 131, 143, 255))
    if variant == 2:                                              # vent grill
        rect(im, 9, 10, 22, 21, (88, 94, 106, 255))
        for y in (11, 14, 17, 20):
            rect(im, 10, y, 21, y + 1, (40, 44, 54, 255))
        rect(im, 9, 9, 22, 9, HULL_LO + (255,))
        rect(im, 9, 22, 22, 22, HULL_HI + (255,))
    return im


# ------------------------------------------------------------------ new puzzle pictures
def gangway_retracted():
    """No catwalk yet: you just see space, a dashed outline and two red lights."""
    im = tile()
    dash = (255, 190, 70, 150)
    for y in range(0, 32, 4):
        rect(im, 3, y, 3, y + 1, dash)
        rect(im, 28, y, 28, y + 1, dash)
    for y in (1, 29):
        rect(im, 14, y, 17, y + 1, (40, 10, 10, 255))
        rect(im, 15, y, 16, y + 1, (235, 60, 50, 255))
    return im


def gangway_extended():
    """A metal catwalk running top to bottom, with yellow rails on both sides."""
    im = tile()
    rect(im, 3, 0, 28, 31, (66, 72, 84, 255))
    for y in range(0, 32, 4):
        rect(im, 6, y, 25, y, (44, 48, 58, 255))
    for x in range(8, 26, 5):
        rect(im, x, 0, x, 31, (52, 57, 68, 255))
    for x0 in (2, 26):
        rect(im, x0, 0, x0 + 3, 31, (30, 26, 14, 255))
        rect(im, x0 + 1, 0, x0 + 2, 31, (232, 190, 64, 255))
        for y in range(2, 32, 8):
            rect(im, x0 + 1, y, x0 + 2, y + 1, (140, 108, 30, 255))
    return im


def airlock_pad():
    """Stand here to cycle the airlock: a pad with a yellow/black hazard ring."""
    im = pad_base((255, 196, 60, 255))
    c = 15.5
    for y in range(T):
        for x in range(T):
            d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5
            if 7.5 <= d <= 10.5:
                stripe = int((np.arctan2(y - c, x - c) + np.pi) / (2 * np.pi) * 12) % 2
                im.putpixel((x, y), (250, 200, 50, 255) if stripe else (30, 28, 30, 255))
            elif d < 7.5:
                im.putpixel((x, y), (70, 78, 92, 255))
    # pressure arrows pointing outwards (air leaving)
    for (x, y) in [(15, 11), (16, 11), (14, 12), (17, 12), (15, 19), (16, 19), (14, 18), (17, 18),
                   (11, 15), (11, 16), (12, 14), (12, 17), (20, 15), (20, 16), (19, 14), (19, 17)]:
        im.putpixel((x, y), (230, 240, 255, 255))
    rect(im, 15, 15, 16, 16, (230, 240, 255, 255))
    return im


# ------------------------------------------------------------------ new palette icons (editor only)
def icon_cell(floor_icon):
    im = floor_icon.copy()
    battery(im, 16, 8, (250, 214, 70, 255), (50, 34, 6, 255), (220, 220, 230, 255))
    return im


def icon_hull():
    im = hull_plate(0)
    for k in range(0, 32, 6):                                     # diagonal hatch = "outside"
        for i in range(8):
            x, y = k + i, 31 - i
            if 0 <= x < 32:
                im.putpixel((x, y), (120, 170, 220, 255))
    return im


def icon_space():
    im = Image.new('RGBA', (T, T), (10, 14, 36, 255))
    for (x, y, b) in [(5, 6, 255), (20, 3, 180), (26, 14, 255), (11, 19, 160), (3, 26, 200), (18, 26, 255), (28, 28, 150)]:
        im.putpixel((x, y), (b, b, 255, 255))
    rect(im, 14, 11, 14, 13, (200, 210, 255, 255))
    rect(im, 13, 12, 15, 12, (200, 210, 255, 255))
    outline(im, 0, 0, 31, 31, (40, 60, 120, 255))
    return im


# ------------------------------------------------------------------ background art
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0


def dither_levels(v, levels, x, y):
    """Pick one of `levels` shades for brightness v (0..1), dithering between neighbours."""
    s = v * (levels - 1)
    base = int(np.floor(s))
    return min(levels - 1, base + (1 if (s - base) > BAYER[y % 4, x % 4] else 0))


def planet(size=168):
    im = Image.new('RGBA', (size, size), CLEAR)
    r = size / 2 - 6
    c = size / 2
    light = np.array([-0.55, -0.6, 0.58])
    light = light / np.linalg.norm(light)
    band_cols = [(64, 52, 110), (92, 70, 140), (126, 94, 160), (170, 120, 150), (110, 150, 190), (80, 110, 170)]
    for y in range(size):
        for x in range(size):
            dx, dy = (x - c) / r, (y - c) / r
            d2 = dx * dx + dy * dy
            if d2 <= 1.0:
                dz = (1 - d2) ** 0.5
                lam = max(0.0, dx * light[0] + dy * light[1] + dz * light[2])
                lat = dy + 0.035 * np.sin(dx * 5 + 1.3) + 0.015 * np.sin(dx * 13 + dy * 4)
                band = band_cols[int((lat + 1) * 6.5) % len(band_cols)]
                level = dither_levels(min(1.0, lam * 1.1), 5, x, y)
                k = [0.1, 0.28, 0.55, 0.8, 1.0][level]
                im.putpixel((x, y), tuple(int(min(255, ch * k)) for ch in band) + (255,))
            elif d2 <= 1.1:                                       # thin atmosphere rim
                lam = max(0.0, dx * light[0] + dy * light[1])
                if lam > 0.05 and dither_levels(lam, 3, x, y) > 0:
                    im.putpixel((x, y), (140, 190, 255, 140))
    return im


def nebula(w=360, h=200):
    def noise(scale):
        g = rng.random((h // scale + 2, w // scale + 2))
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((w + scale * 2, h + scale * 2), Image.BICUBIC)
        return np.asarray(img, dtype=float)[:h, :w] / 255.0
    n = noise(60) * 0.55 + noise(25) * 0.3 + noise(10) * 0.15
    yy, xx = np.mgrid[0:h, 0:w]
    mask = np.exp(-(((xx - w * 0.55) / (w * 0.42)) ** 2 + ((yy - h * 0.5) / (h * 0.38)) ** 2))
    v = np.clip((n - 0.38) * 2.2, 0, 1) * mask
    im = Image.new('RGBA', (w, h), CLEAR)
    cols = [(60, 40, 120), (110, 50, 140), (60, 110, 170)]
    for y in range(h):
        for x in range(w):
            lvl = dither_levels(float(v[y, x]), 4, x, y)
            if lvl > 0:
                col = cols[min(2, int(n[y, x] * 3.2) % 3)]
                im.putpixel((x, y), col + ([0, 40, 75, 110][lvl],))
    return im


def main():
    layout = Image.open('Assets/images/tiles/layout_tiles.png').convert('RGBA').crop((0, 0, 12 * T, T))
    floor_icon = layout.crop((0, 0, T, T))
    new_layout = Image.new('RGBA', (16 * T, T), CLEAR)
    new_layout.paste(layout, (0, 0))
    for i, im in enumerate([icon_cell(floor_icon), icon_hull(), icon_space(), airlock_pad()]):
        new_layout.paste(im, ((12 + i) * T, 0))
    new_layout.save('Assets/images/tiles/layout_tiles.png')

    puzzle = Image.open('Assets/images/tiles/puzzle_tiles.png').convert('RGBA').crop((0, 0, 9 * T, T))
    new_puzzle = Image.new('RGBA', (12 * T, T), CLEAR)
    new_puzzle.paste(puzzle, (0, 0))
    for i, im in enumerate([gangway_retracted(), gangway_extended(), airlock_pad()]):
        new_puzzle.paste(im, ((9 + i) * T, 0))
    new_puzzle.save('Assets/images/tiles/puzzle_tiles.png')

    hull = Image.new('RGBA', (3 * T, T), CLEAR)
    for i in range(3):
        hull.paste(hull_plate(i), (i * T, 0))
    hull.save('Assets/images/tiles/hull.png')

    import os
    os.makedirs('Assets/images/space', exist_ok=True)
    planet().save('Assets/images/space/planet.png')
    nebula().save('Assets/images/space/nebula.png')
    print('ok')


if __name__ == '__main__':
    main()
