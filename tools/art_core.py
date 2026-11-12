# art_core.py - draws the CORE tile (Level 3): a round machine socket bolted to
# a floor plate. PIP's core docks on it (rogue_pip.gd draws PIP himself), and
# in Level 3's first room it's the "sync pylon" you practise looping round.
#
# Writes it into two sheets (safe to run again - it just redraws the same spots):
#   Assets/images/tiles/puzzle_tiles.png  frame 13  (what you see in the game)
#   Assets/images/tiles/layout_tiles.png  frame 17  (the icon you paint with:
#                                                    the socket with two little eyes)
# The layout palette also needs the tile in layout_tileset.tres (17:0, kind "core").
#
# Run from the project folder:   python tools/art_core.py
from PIL import Image
from art_barrier import put_frame      # same "paste into frame N" helper as the barrier

T = 'Assets/images/tiles/'
OUTLINE = (5, 9, 34, 255)
PLATE = (115, 122, 131, 255)
PLATE_DARK = (66, 73, 89, 255)
SCREW = (94, 87, 90, 255)
HOUSING = (58, 63, 78, 255)
HOUSING_LIT = (92, 99, 116, 255)
SHADOW = (30, 34, 46, 255)
RING = (90, 230, 140, 255)          # PIP's green
RING_DARK = (40, 120, 80, 255)
GLASS = (14, 24, 26, 255)
LENS = (170, 255, 210, 255)
COPPER = (205, 125, 60, 255)


def core_tile(eyes: bool) -> Image.Image:
    img = Image.new('RGBA', (32, 32), (0, 0, 0, 0))
    px = img.load()
    # the floor plate it's bolted to (same look as the other pads)
    for y in range(32):
        for x in range(32):
            if x in (0, 31) or y in (0, 31):
                px[x, y] = OUTLINE
            else:
                px[x, y] = PLATE
    for x, y in ((3, 3), (28, 3), (3, 28), (28, 28)):
        px[x, y] = SCREW
    # the round housing: a shadow underneath, then the body, lit from the top
    cx, cy = 15.5, 15.0
    for y in range(32):
        for x in range(32):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            ds = ((x - cx) ** 2 + (y - cy - 2) ** 2) ** 0.5
            if d <= 12.5:
                px[x, y] = OUTLINE if d > 11.5 else (HOUSING_LIT if y < cy - 4 else HOUSING)
            elif ds <= 12.5:
                px[x, y] = SHADOW
    # the green ring and the dark glass inside it
    for y in range(32):
        for x in range(32):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if 7.0 < d <= 9.0:
                px[x, y] = RING if y < cy + 2 else RING_DARK
            elif d <= 7.0:
                px[x, y] = GLASS
    # four copper coil studs round the rim
    for sx, sy in ((15, 3), (16, 3), (15, 26), (16, 26), (4, 14), (4, 15), (27, 14), (27, 15)):
        px[sx, sy] = COPPER
    if eyes:
        # palette icon: two of PIP's eyes in the glass, so you know whose core it is
        for ex in (12, 18):
            for dy in range(3):
                px[ex, 13 + dy] = LENS
                px[ex + 1, 13 + dy] = LENS
    else:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if abs(dx) + abs(dy) < 2:
                    px[15 + dx, 15 + dy] = LENS
    return img


if __name__ == '__main__':
    put_frame(T + 'puzzle_tiles.png', 13, core_tile(False))
    put_frame(T + 'layout_tiles.png', 17, core_tile(True))
