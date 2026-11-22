# art_pillar.py: draws the POLE as a support pillar, a steel column that holds
# the ship's deck up. The wire wraps round it (level.gd, _update_wraps).
#
# Writes (safe to run again, it just redraws the same spots):
#   Assets/images/tiles/pillar.png          32 x 64: the column, standing on its tile.
#                                           Its base is at y 56 (the tile's centre).
#   Assets/images/tiles/pillar_glow.png     32 x 64: only the purple cable ring, so the
#                                           game can make it shine in the dark.
#   Assets/images/tiles/puzzle_tiles.png    frame 3: the steel floor plate under it
#   Assets/images/tiles/layout_tiles.png    frame 5: the palette icon (the pillar seen
#                                           from above, so you know what you paint)
#
# Run from the project folder:   python tools/art_pillar.py
from PIL import Image
from art_barrier import put_frame      # same "paste into frame N" helper as the barrier

T = 'Assets/images/tiles/'
OUTLINE = (5, 9, 34, 255)
PLATE = (115, 122, 131, 255)          # the same grey as the other floor pads
PLATE_DARK = (78, 85, 100, 255)
SCREW = (94, 87, 90, 255)
# the steel column, lit from the top left: light on the left, shade on the right
STEEL = [(178, 186, 200, 255), (146, 155, 171, 255), (116, 124, 140, 255),
         (88, 96, 113, 255), (62, 68, 84, 255)]
BAND = (52, 58, 74, 255)
RIVET = (196, 204, 216, 255)
YELLOW = (255, 206, 60, 255)
BLACK = (32, 26, 22, 255)
PURPLE = (190, 120, 255, 255)
PURPLE_LIGHT = (236, 206, 255, 255)
PURPLE_DARK = (96, 52, 150, 255)

W, H = 32, 64
BASE_Y = 56          # the tile's centre: where the column meets the floor
L, R = 7, 24         # the shaft's left and right edge (18 px wide)


def shade(x: int) -> tuple:
    """Steel colour for column x: a round column, so brightest a bit left of centre."""
    k = (x - L) / (R - L)                  # 0 at the left edge, 1 at the right
    if k < 0.12: return STEEL[2]
    if k < 0.35: return STEEL[0]
    if k < 0.55: return STEEL[1]
    if k < 0.8: return STEEL[2]
    if k < 0.92: return STEEL[3]
    return STEEL[4]


def pillar() -> tuple:
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    px = img.load()
    gx = glow.load()
    top = 11
    # the shaft
    for y in range(top, BASE_Y - 3):
        for x in range(L, R + 1):
            px[x, y] = OUTLINE if x in (L, R) else shade(x)
    # the top: a beam going up into the dark (it holds up the deck above),
    # then a wide bolted bracket where the beam meets the column
    mid = (L + R) // 2
    for y in range(0, 6):
        a = int(255 * (y + 1) / 6)
        for x in range(mid - 4, mid + 6):
            c = OUTLINE if x in (mid - 4, mid + 5) else (STEEL[2] if x < mid + 1 else STEEL[3])
            px[x, y] = (c[0], c[1], c[2], a)
    for y in range(6, top):
        for x in range(L - 3, R + 4):
            edge = y in (6, top - 1) or x in (L - 3, R + 3)
            px[x, y] = OUTLINE if edge else (STEEL[0] if y == 7 else STEEL[2])
    for x in (L - 1, mid, R + 1):
        px[x, 8] = RIVET
    # steel bands with rivets
    for by in (19, 29):
        for x in range(L + 1, R):
            px[x, by] = BAND
            px[x, by + 1] = BAND if x > (L + R) // 2 else STEEL[3]
        for x in (L + 3, (L + R) // 2, R - 3):
            px[x, by - 1] = RIVET
    # the cable ring the wire wraps round (purple: "the wire can catch here")
    ring = 38
    for y in range(ring, ring + 5):
        for x in range(L - 1, R + 2):
            if y in (ring, ring + 4) or x in (L - 1, R + 1):
                px[x, y] = OUTLINE
            else:
                c = PURPLE_LIGHT if y == ring + 1 and x < (L + R) // 2 else (PURPLE if y < ring + 3 else PURPLE_DARK)
                px[x, y] = c
                gx[x, y] = c
    # hazard stripes just above the base
    for y in range(BASE_Y - 11, BASE_Y - 3):
        for x in range(L + 1, R):
            px[x, y] = YELLOW if ((x + y) // 3) % 2 == 0 else BLACK
    for x in range(L, R + 1):
        px[x, BASE_Y - 12] = OUTLINE
    # the foot: a wider bolted flange sitting on the floor plate
    for y in range(BASE_Y - 3, BASE_Y + 3):
        for x in range(L - 3, R + 4):
            edge = y in (BASE_Y - 3, BASE_Y + 2) or x in (L - 3, R + 3)
            px[x, y] = OUTLINE if edge else (STEEL[1] if y == BASE_Y - 2 else STEEL[3])
    for x in (L - 1, R + 1, (L + R) // 2):
        px[x, BASE_Y] = RIVET
    return img, glow


def floor_plate(icon: bool) -> Image.Image:
    """The steel mounting plate on the floor. Its four small lights glow purple in
    the game. The palette icon also shows the round column seen from above."""
    img = Image.new('RGBA', (32, 32), (0, 0, 0, 0))
    px = img.load()
    for y in range(32):
        for x in range(32):
            if x in (0, 31) or y in (0, 31):
                px[x, y] = OUTLINE
            elif x in (2, 29) or y in (2, 29):
                px[x, y] = PLATE_DARK
            else:
                px[x, y] = PLATE
    for x, y in ((4, 4), (27, 4), (4, 27), (27, 27)):
        px[x, y] = SCREW
    # the column's shadow (light from the top left, so it falls to the bottom right)
    for y in range(32):
        for x in range(32):
            if ((x - 18.5) ** 2 + (y - 18.5) ** 2) <= 9.5 ** 2 and px[x, y] == PLATE:
                px[x, y] = PLATE_DARK
    for x, y in ((15, 3), (16, 3), (15, 28), (16, 28), (3, 15), (3, 16), (28, 15), (28, 16)):
        px[x, y] = PURPLE
    if icon:
        for y in range(32):
            for x in range(32):
                d = ((x - 15.5) ** 2 + (y - 15.5) ** 2) ** 0.5
                if d <= 9.5:
                    px[x, y] = OUTLINE if d > 8.5 else (PURPLE if d > 6.5 else (STEEL[0] if x + y < 30 else STEEL[2]))
    return img


if __name__ == '__main__':
    col, glow = pillar()
    col.save(T + 'pillar.png')
    glow.save(T + 'pillar_glow.png')
    print('pillar.png and pillar_glow.png drawn (32x64)')
    put_frame(T + 'puzzle_tiles.png', 3, floor_plate(False))
    put_frame(T + 'layout_tiles.png', 5, floor_plate(True))
