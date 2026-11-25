# art_wall_caps.py: the ends of the team's front panels, with the top edge
# skirting wrapped round the corner.
#
#   Assets/images/tiles/team/wall_caps.png   6 tiles: for each panel (power strip,
#                                            windows, computers) its left end,
#                                            then its right end
#
# A front panel's top row has a dark band (the top of the wall) with a light
# skirting line under it. Where the panel ends next to floor (a doorway or a
# corridor beside it), that band used to stop with no edge. These tiles are the
# panel's own end tiles from wall.png, with the band redrawn so the skirting
# turns the corner and runs up the open side, the same way the wall tops do.
# Only the band (the top 18 rows) changes; the rest is the team's picture.
#
# How the band is drawn: every pixel looks at how far it is from the panel
# face below (row 18 down) or the open side, and takes the colour for that
# distance: 2 px of skirting, then the shadow steps, then the dark top. That
# is exactly how the team drew the band (rows 16-17 skirting, 15-12 shadow).
# tools/retile_walls.py puts these on every panel end that has floor beside it.
# Run from the project folder:  python3 tools/art_wall_caps.py
from PIL import Image

SRC = 'Assets/images/tiles/team/wall.png'
OUT = 'Assets/images/tiles/team/wall_caps.png'
T = 32
FACE_TOP = 18                 # the panel's face starts here (its skirting is rows 16 and 17)
RIM = (124, 126, 138, 255)
TOP = (53, 55, 59, 255)
STEPS = [RIM, RIM, (30, 31, 33, 255), (37, 39, 41, 255), (45, 47, 50, 255), (50, 52, 56, 255)]
# (first row of the panel in wall.png, its left end column, its right end column)
PANELS = [(0, 0, 5), (3, 0, 9), (6, 0, 9)]          # power strip, windows, computers


def cap(src, row, col, side):
    """The panel's top end tile with the skirting wrapped round the open side
    (side -1 = left end, floor to its left; +1 = right end)."""
    tile = src.crop((col * T, row * T, col * T + T, row * T + T))
    px = tile.load()
    for y in range(FACE_TOP):
        for x in range(T):
            to_face = FACE_TOP - y                       # distance to the face below
            to_side = x + 1 if side < 0 else T - x       # distance to the open side
            d = min(to_face, to_side)
            px[x, y] = STEPS[d - 1] if d - 1 < len(STEPS) else TOP
    return tile


if __name__ == '__main__':
    src = Image.open(SRC).convert('RGBA')
    sheet = Image.new('RGBA', (6 * T, T), (0, 0, 0, 0))
    for i, (row, left, right) in enumerate(PANELS):
        sheet.paste(cap(src, row, left, -1), ((2 * i) * T, 0))
        sheet.paste(cap(src, row, right, +1), ((2 * i + 1) * T, 0))
    sheet.save(OUT)
    print(f'{OUT}: 6 panel ends')
