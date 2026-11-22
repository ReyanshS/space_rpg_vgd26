# art_pillar.py: draws the POLE as a support pillar, a steel column that holds
# the ship's deck up. The wire wraps round it (level.gd, _update_wraps).
#
# Writes (safe to run again, it just redraws the same spots):
#   Assets/images/tiles/pillar.png          32 x 64: the column, standing on its tile.
#                                           Its foot is at y 56 (the tile's centre).
#   Assets/images/tiles/pillar_glow.png     32 x 64: only the purple light ring, so the
#                                           game can make it shine in the dark.
#   Assets/images/tiles/puzzle_tiles.png    frame 3: the steel floor plate under it
#   Assets/images/tiles/layout_tiles.png    frame 5: the palette icon (the pillar seen
#                                           from above, so you know what you paint)
#
# Three designs to choose from (the team picked "octagon"):
#   octagon   a gunmetal column with eight sides, bolted collars and a heavy plinth
#   girder    an H shaped steel girder with cross bracing
#   round     a round column with a pipe running up its side
# Run from the project folder:   python tools/art_pillar.py [octagon|girder|round]
import sys
from PIL import Image
from art_barrier import put_frame      # same "paste into frame N" helper as the barrier

T = 'Assets/images/tiles/'
OUTLINE = (5, 9, 34, 255)
PLATE = (115, 122, 131, 255)          # the same grey as the other floor pads
PLATE_DARK = (78, 85, 100, 255)
PLATE_DEEP = (58, 63, 76, 255)
SCREW = (94, 87, 90, 255)
# gunmetal, lit from the top left: [highlight, light, mid, dark, deep]
STEEL = [(178, 188, 206, 255), (132, 142, 162, 255), (96, 104, 122, 255),
         (70, 76, 92, 255), (46, 50, 64, 255)]
BOLT = (196, 204, 218, 255)
PURPLE_HOT = (246, 226, 255, 255)
PURPLE = (190, 120, 255, 255)
PURPLE_DARK = (96, 52, 150, 255)

W, H = 32, 64
FOOT = 56            # the tile's centre: where the column stands on the floor


class Canvas:
    """A 32 x 64 picture plus a second one for the parts that glow."""
    def __init__(self):
        self.img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        self.glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        self.px = self.img.load()
        self.gx = self.glow.load()

    def put(self, x, y, c, glow=False):
        if 0 <= x < W and 0 <= y < H:
            self.px[x, y] = c
            if glow:
                self.gx[x, y] = c

    def rect(self, x0, y0, x1, y1, c):
        """Fill x0..x1, y0..y1 (both ends included)."""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, c)

    def box(self, x0, y0, x1, y1, fill):
        """A filled box with a dark outline."""
        self.rect(x0, y0, x1, y1, OUTLINE)
        self.rect(x0 + 1, y0 + 1, x1 - 1, y1 - 1, fill)


def girder_top(cv, x0, x1):
    """The beam the pillar holds up, fading into the dark above the screen."""
    for y in range(0, 7):
        a = int(255 * (y + 2) / 9)
        for x in range(x0, x1 + 1):
            if x in (x0, x1):
                c = OUTLINE
            elif x in (x0 + 1, x0 + 2):
                c = STEEL[1]
            elif x in (x1 - 1, x1 - 2):
                c = STEEL[3]
            else:
                c = STEEL[4]                       # the beam's recessed middle (its web)
            cv.put(x, y, (c[0], c[1], c[2], a))


def capital(cv, x0, x1, y0):
    """A wide bolted block where the column meets the beam: top face, front face."""
    cv.box(x0, y0, x1, y0 + 6, STEEL[2])
    cv.rect(x0 + 1, y0 + 1, x1 - 1, y0 + 2, STEEL[1])          # top face catches the light
    cv.rect(x0 + 1, y0 + 1, x1 - 1, y0 + 1, STEEL[0])
    cv.rect(x1 - 2, y0 + 3, x1 - 1, y0 + 5, STEEL[3])          # right end in shade
    for x in (x0 + 2, (x0 + x1) // 2, x1 - 3):
        cv.put(x, y0 + 4, BOLT)


def plinth(cv, x0, x1, y0, y1):
    """The heavy foot: a top face and a front face with bolts."""
    cv.box(x0, y0, x1, y1, STEEL[3])
    cv.rect(x0 + 1, y0 + 1, x1 - 1, y0 + 3, STEEL[1])          # top face
    cv.rect(x0 + 1, y0 + 1, x1 - 1, y0 + 1, STEEL[0])
    cv.rect(x0 + 1, y0 + 4, x1 - 1, y0 + 4, OUTLINE)            # edge between the faces
    cv.rect(x1 - 2, y0 + 5, x1 - 1, y1 - 1, STEEL[4])          # right side in shade
    for x in (x0 + 2, x1 - 3):
        cv.put(x, y0 + 7, BOLT)


def light_ring(cv, x0, x1, y0):
    """The recessed purple light strip: the spot the wire catches on."""
    cv.rect(x0, y0, x1, y0 + 4, OUTLINE)
    for x in range(x0 + 1, x1):
        cv.put(x, y0 + 1, PURPLE_HOT if x < (x0 + x1) // 2 else PURPLE, True)
        cv.put(x, y0 + 2, PURPLE, True)
        cv.put(x, y0 + 3, PURPLE_DARK, True)


def octagon() -> Canvas:
    cv = Canvas()
    L, R = 9, 22                        # the shaft
    girder_top(cv, 11, 20)
    capital(cv, 6, 25, 6)
    # an eight sided column: a lit bevel, the front face, a shaded bevel
    for y in range(13, 47):
        for x in range(L - 1, R + 2):
            if x in (L - 1, R + 1):
                c = OUTLINE
            elif x <= L:
                c = STEEL[1]
            elif x <= L + 2:
                c = STEEL[0] if x == L + 1 else STEEL[1]
            elif x >= R:
                c = STEEL[4]
            elif x >= R - 2:
                c = STEEL[3]
            else:
                c = STEEL[2]
            cv.put(x, y, c)
    # panel seams with rivets
    for y in (24, 35):
        for x in range(L, R + 1):
            cv.put(x, y, STEEL[4])
            cv.put(x, y + 1, STEEL[1] if x < R - 2 else STEEL[3])
        for x in (L + 2, (L + R) // 2 + 1, R - 2):
            cv.put(x, y - 2, BOLT)
    # two bolted collars
    for y0 in (15, 39):
        cv.box(L - 2, y0, R + 2, y0 + 3, STEEL[3])
        cv.rect(L - 1, y0 + 1, R + 1, y0 + 1, STEEL[1])
        for x in (L, (L + R) // 2, R):
            cv.put(x, y0 + 2, BOLT)
    light_ring(cv, L - 1, R + 1, 44)
    plinth(cv, 5, 26, 48, 59)
    return cv


def girder() -> Canvas:
    cv = Canvas()
    girder_top(cv, 10, 21)
    capital(cv, 6, 25, 6)
    # an H shaped girder seen from the front: two flanges and a recessed web
    for y in range(13, 47):
        for x in range(8, 24):
            if x in (8, 23):
                c = OUTLINE
            elif x <= 11:
                c = STEEL[0] if x == 9 else STEEL[1]
            elif x >= 20:
                c = STEEL[3] if x < 22 else STEEL[4]
            else:
                c = STEEL[4]
            cv.put(x, y, c)
        for x in (12, 19):
            cv.put(x, y, OUTLINE)
    # cross bracing in the web
    for k in range(0, 34):
        y = 13 + k
        x = 13 + (k % 12) // 2 if (k // 12) % 2 == 0 else 18 - (k % 12) // 2
        cv.put(x, y, STEEL[2])
    for y in (20, 33):
        for x in range(9, 23):
            cv.put(x, y, STEEL[2] if x < 20 else STEEL[3])
        cv.put(10, y, BOLT)
        cv.put(21, y, BOLT)
    light_ring(cv, 7, 24, 43)
    plinth(cv, 5, 26, 48, 59)
    return cv


def round_column() -> Canvas:
    cv = Canvas()
    L, R = 9, 21
    girder_top(cv, 11, 20)
    capital(cv, 6, 25, 6)
    ramp = [STEEL[1], STEEL[0], STEEL[0], STEEL[1], STEEL[1], STEEL[2], STEEL[2], STEEL[2],
            STEEL[3], STEEL[3], STEEL[4]]
    for y in range(13, 47):
        for x in range(L - 1, R + 2):
            if x in (L - 1, R + 1):
                c = OUTLINE
            else:
                c = ramp[min(len(ramp) - 1, (x - L) * len(ramp) // (R - L + 1))]
            cv.put(x, y, c)
    for y in (22, 31):
        for x in range(L, R + 1):
            cv.put(x, y, STEEL[4])
    # a pipe running up the right side, held by brackets
    for y in range(13, 48):
        cv.put(R + 2, y, OUTLINE)
        cv.put(R + 3, y, STEEL[2])
        cv.put(R + 4, y, OUTLINE)
    for y in (18, 28, 38):
        cv.rect(R + 1, y, R + 4, y + 1, STEEL[3])
        cv.put(R + 3, y, BOLT)
    light_ring(cv, L - 1, R + 1, 41)
    plinth(cv, 5, 27, 48, 59)
    return cv


def floor_plate(icon: bool) -> Image.Image:
    """The steel mounting plate on the floor, with a soft dark patch where the
    pillar stands. Its four small lights glow purple in the game. The palette
    icon also shows the pillar seen from above."""
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
    # contact shadow: the plinth sits on the top half; its shadow spills down-right
    for y in range(32):
        for x in range(32):
            if 6 <= x <= 27 and 14 <= y <= 27 and px[x, y] == PLATE:
                d = max(abs(x - 17) / 11.0, abs(y - 20) / 7.0)
                px[x, y] = PLATE_DEEP if d < 0.75 else PLATE_DARK
    for x, y in ((15, 3), (16, 3), (15, 28), (16, 28), (3, 15), (3, 16), (28, 15), (28, 16)):
        px[x, y] = PURPLE
    if icon:
        # the pillar from above: an eight sided steel top with a purple ring round it
        for y in range(32):
            for x in range(32):
                dx, dy = abs(x - 15.5), abs(y - 15.5)
                d = max(dx, dy, (dx + dy) / 1.4)
                if d <= 10.5:
                    px[x, y] = OUTLINE if d > 9.6 else (PURPLE if d > 7.6 else (STEEL[1] if x + y < 30 else STEEL[3]))
        for x, y in ((12, 12), (19, 12), (12, 19), (19, 19)):
            px[x, y] = BOLT
    return img


DESIGNS = {'octagon': octagon, 'girder': girder, 'round': round_column}

if __name__ == '__main__':
    name = sys.argv[1] if len(sys.argv) > 1 else 'octagon'
    cv = DESIGNS[name]()
    cv.img.save(T + 'pillar.png')
    cv.glow.save(T + 'pillar_glow.png')
    print(f'pillar.png and pillar_glow.png drawn ({name}, 32x64)')
    put_frame(T + 'puzzle_tiles.png', 3, floor_plate(False))
    put_frame(T + 'layout_tiles.png', 5, floor_plate(True))
