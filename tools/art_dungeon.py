# art_dungeon.py: the tiles for the dungeon parts of a level.
#   FUSE DOOR   a door with an amber bar and a fuse slot: it opens if you carry a fuse
#   MAIN DOOR   a heavy door with a red bar and three lamp sockets (the game lights
#               one lamp for each part of the deck you power: puzzle_tile.gd)
#   SOCKET      a floor socket the cable clamp can be dropped into
# and the palette icons you paint with, including the FUSE and the CLAMP pickups
# (in the game those two draw themselves: pickup.gd).
#
# Writes (safe to run again):
#   Assets/images/tiles/puzzle_tiles.png  frames 14 fuse door, 15 main door, 16 socket
#   Assets/images/tiles/layout_tiles.png  frames 18 fuse, 19 fuse door, 20 main door,
#                                         21 socket, 22 clamp
# The palette also needs these in layout_tileset.tres (18:0 "fuse" ... 22:0 "clamp").
# Run from the project folder:   python tools/art_dungeon.py
from PIL import Image
from art_barrier import put_frame

T = 'Assets/images/tiles/'
OUTLINE = (5, 9, 34, 255)
PLATE = (115, 122, 131, 255)
PLATE_DARK = (78, 85, 100, 255)
SCREW = (94, 87, 90, 255)
AMBER = (255, 190, 70, 255)
PURPLE = (190, 120, 255, 255)
PURPLE_DARK = (96, 52, 150, 255)


def recolor(tile: Image.Image, tint: tuple) -> Image.Image:
    """Turn the green bar of the normal door into another colour, keeping its shading."""
    out = tile.copy()
    px = out.load()
    for y in range(32):
        for x in range(32):
            r, g, b, a = px[x, y]
            if a and g > r + 25 and g > b:                 # a green pixel
                lum = g / 255.0
                px[x, y] = (min(255, int(tint[0] * lum * 1.15)), min(255, int(tint[1] * lum * 1.15)),
                            min(255, int(tint[2] * lum * 1.15)), a)
    return out


def fuse_icon(px, cx: int, top: int, h: int = 14):
    """A fuse: a glass tube with a glowing wire inside and metal caps at both ends."""
    for y in range(top, top + h):
        for x in range(cx - 3, cx + 4):
            edge = x in (cx - 3, cx + 3) or y in (top, top + h - 1)
            cap = y < top + 3 or y > top + h - 4
            px[x, y] = OUTLINE if edge else ((196, 204, 218, 255) if cap else (60, 40, 20, 255))
    for y in range(top + 3, top + h - 3):
        px[cx, y] = AMBER
    px[cx - 1, top + 4] = (255, 235, 190, 255)


def fuse_door(door: Image.Image) -> Image.Image:
    img = recolor(door, (255, 170, 50))
    px = img.load()
    fuse_icon(px, 16, 9, 14)
    return img


def main_door(door: Image.Image) -> Image.Image:
    img = recolor(door, (255, 70, 55))
    px = img.load()
    # a steel plate above the bar with three dark lamp sockets
    for y in range(4, 10):
        for x in range(6, 26):
            px[x, y] = OUTLINE if y in (4, 9) or x in (6, 25) else PLATE_DARK
    for lx in (10, 16, 22):
        for dy in range(-1, 2):
            for dx in range(-1, 2):
                px[lx + dx, 6 + dy + 1] = (30, 20, 25, 255)
    # and the bar is doubled: heavier than a normal door
    for y in range(19, 22):
        for x in range(2, 30):
            if px[x, y - 6][3] and px[x, y - 6] != PLATE and px[x, y - 6][0] > 150:
                px[x, y] = px[x, y - 6]
    return img


def plate() -> Image.Image:
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
    return img


def socket() -> Image.Image:
    img = plate()
    px = img.load()
    for y in range(32):
        for x in range(32):
            d = ((x - 15.5) ** 2 + (y - 15.5) ** 2) ** 0.5
            if d <= 8.5:
                px[x, y] = OUTLINE if d > 7.5 else (PURPLE if d > 6.0 else ((20, 18, 30, 255) if d > 2.0 else PURPLE_DARK))
    return img


def clamp_icon() -> Image.Image:
    """Palette icon for the clamp pickup: a short purple cable post with jaws."""
    img = plate()
    px = img.load()
    for y in range(8, 25):
        for x in range(12, 20):
            edge = x in (12, 19) or y in (8, 24)
            px[x, y] = OUTLINE if edge else (PURPLE if x < 16 else PURPLE_DARK)
    for x in range(10, 22):                       # the jaws at the top
        px[x, 8] = OUTLINE
        px[x, 9] = (230, 210, 255, 255) if 11 <= x <= 20 else OUTLINE
    return img


def fuse_pickup_icon() -> Image.Image:
    img = plate()
    fuse_icon(img.load(), 16, 9, 15)
    return img


if __name__ == '__main__':
    sheet = Image.open(T + 'puzzle_tiles.png').convert('RGBA')
    door = sheet.crop((7 * 32, 0, 8 * 32, 32))
    fd, md, so = fuse_door(door), main_door(door), socket()
    put_frame(T + 'puzzle_tiles.png', 14, fd)
    put_frame(T + 'puzzle_tiles.png', 15, md)
    put_frame(T + 'puzzle_tiles.png', 16, so)
    put_frame(T + 'layout_tiles.png', 18, fuse_pickup_icon())
    put_frame(T + 'layout_tiles.png', 19, fd)
    put_frame(T + 'layout_tiles.png', 20, md)
    put_frame(T + 'layout_tiles.png', 21, so)
    put_frame(T + 'layout_tiles.png', 22, clamp_icon())
