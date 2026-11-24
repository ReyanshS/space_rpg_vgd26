# art_wall_sides.py: draws every wall piece that goes with the team's front
# wall faces (Assets/images/tiles/team/wall.png).
#
#   Assets/images/tiles/team/wall_sides.png    47 tiles of 32 x 32 (8 per row)
#   Assets/images/tiles/team/wall_sides.json   which neighbours are floor, per tile
#
# The game is top down at a slant: you see the FRONT of a wall when the floor is
# below it (the team's panels with windows and computers). Every other wall you
# see from above: just its top. Those are drawn here in the team's 3D style
# (wall.png is their "Wall-tilemap3d v2"): the top of a wall is a flat dark grey,
# the same as the band along the top of every front panel. Where a wall top
# meets the floor there's one light rim (2 px) with a short shadow inside it, the
# same steps the 3D panels use where their top meets the panel. So side walls,
# bottom walls and the tops of the front walls are all one dark surface.
#
# Which piece? A wall tile has 8 neighbours. Each side (N, E, S, W) is floor or
# not; a corner (NE, SE, SW, NW) only matters when both sides next to it are
# wall (otherwise the side's rim already covers it). That gives exactly 47
# different pieces: the classic "blob" tile set. Every pixel is coloured by how
# far it is from the nearest floor, so all 47 join up with each other.
# The JSON lists each tile's open (floor) neighbours. tools/build_team_tiles.gd
# reads it to set up Godot's terrain (paint walls with one brush), and
# tools/retile_walls.py reads it to pick pieces when it converts a level.
# Run from the project folder:  python3 tools/art_wall_sides.py
import json
from PIL import Image

OUT = 'Assets/images/tiles/team/wall_sides.png'
OUT_JSON = 'Assets/images/tiles/team/wall_sides.json'
T = 32
COLS = 8
RIM = (124, 126, 138, 255)     # the edge (the rim of the team's front panels)
TOP = (53, 55, 59, 255)        # the top of a wall (the dark band on the team's 3D panels)
# from the floor outwards: distance in pixels -> colour. The rim, then the shadow
# steps the 3D panels use between their rim and their top band, then the top.
STEPS = [RIM, RIM, (30, 31, 33, 255), (37, 39, 41, 255), (45, 47, 50, 255), (50, 52, 56, 255)]

# the 8 neighbours: name -> (column, row) in a 3 x 3 window (the tile itself is (1, 1))
DIRS = {'N': (1, 0), 'NE': (2, 0), 'E': (2, 1), 'SE': (2, 2),
        'S': (1, 2), 'SW': (0, 2), 'W': (0, 1), 'NW': (0, 0)}
CORNER_SIDES = {'NE': ('N', 'E'), 'SE': ('S', 'E'), 'SW': ('S', 'W'), 'NW': ('N', 'W')}


def canonical(open_dirs):
    """Drop the corners that don't matter: a corner counts as floor only when
    both sides next to it are wall."""
    out = set()
    for d in open_dirs:
        if d in CORNER_SIDES:
            a, b = CORNER_SIDES[d]
            if a in open_dirs or b in open_dirs:
                continue
        out.add(d)
    return frozenset(out)


def all_pieces():
    """Every different wall piece, in sheet order: solid first, then fewer
    open sides before more."""
    seen = set()
    for bits in range(256):
        names = [d for i, d in enumerate(DIRS) if bits >> i & 1]
        seen.add(canonical(names))
    order = list(DIRS)
    return sorted(seen, key=lambda s: (len(s), sorted(order.index(d) for d in s)))


def tile(open_dirs):
    """Draws one wall tile whose `open_dirs` neighbours are floor.
    Every pixel looks at how far it is from the nearest floor (counting diagonal
    steps as 1: "Chebyshev distance"), so neighbouring tiles always line up."""
    im = Image.new('RGBA', (T, T), TOP)
    px = im.load()
    squares = [(DIRS[d][0] * T - T, DIRS[d][1] * T - T) for d in open_dirs]   # floor tiles, in this tile's pixels

    def dist(x, y):
        best = 99
        for (sx, sy) in squares:
            dx = max(sx - x, x - (sx + T - 1), 0)
            dy = max(sy - y, y - (sy + T - 1), 0)
            best = min(best, max(dx, dy))
        return best

    for y in range(T):
        for x in range(T):
            d = dist(x, y)                 # 1 = touching the floor
            if d - 1 < len(STEPS):
                px[x, y] = STEPS[d - 1]
    return im


if __name__ == '__main__':
    pieces = all_pieces()
    rows = (len(pieces) + COLS - 1) // COLS
    sheet = Image.new('RGBA', (COLS * T, rows * T), (0, 0, 0, 0))
    info = []
    for i, p in enumerate(pieces):
        x, y = i % COLS, i // COLS
        sheet.paste(tile(p), (x * T, y * T))
        info.append({'x': x, 'y': y, 'open': [d for d in DIRS if d in p]})
    sheet.save(OUT)
    json.dump(info, open(OUT_JSON, 'w'), indent=1)
    print(f'{OUT}: {len(pieces)} wall pieces ({sheet.width}x{sheet.height}), {OUT_JSON}')
