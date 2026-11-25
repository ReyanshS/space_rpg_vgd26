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
# After those 47 come the pieces that sit next to a front panel (see FLOOR /
# PANEL below): only the ones the levels use, so run this again after big map
# changes, then tools/build_team_tiles.gd and tools/retile_walls.py.
# The JSON lists each tile's open neighbours: "open" = floor, and "panel_top" /
# "panel" = a front panel's top row / lower rows. tools/retile_walls.py reads
# it to pick the piece for every wall.
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


# A neighbour that isn't wall is one of these. A front panel (the team's wall
# faces) counts like floor for the rim, so the top edge skirting of a front wall
# wraps round the corner and runs down beside it to the floor. Next to a
# panel's TOP row the rim lines up with the panel's own skirting line (wall.png:
# rows 16 and 17 of each panel's first row; its face starts at PANEL_EDGE).
FLOOR, PANEL_TOP, PANEL = 'floor', 'panel_top', 'panel'
PANEL_EDGE = 18


def canonical(open_dirs):
    """Drop the corners that don't matter: a corner counts only when both sides
    next to it are wall. `open_dirs` is a dict direction -> what's there
    (or a list of directions, all floor). Returns a hashable key."""
    if not isinstance(open_dirs, dict):
        open_dirs = {d: FLOOR for d in open_dirs}
    out = {}
    for d, what in open_dirs.items():
        if d in CORNER_SIDES:
            a, b = CORNER_SIDES[d]
            if a in open_dirs or b in open_dirs:
                continue
        out[d] = what
    return frozenset(out.items())


def base_pieces():
    """The 47 pieces with only floor round them, in sheet order: solid first,
    then fewer open sides before more."""
    seen = set()
    for bits in range(256):
        names = [d for i, d in enumerate(DIRS) if bits >> i & 1]
        seen.add(canonical(names))
    order = list(DIRS)
    return sorted(seen, key=lambda s: (len(s), sorted(order.index(d) for d, _ in s)))


def needed_pieces(levels):
    """Pieces next to front panels that these levels use (after the 47 basic
    ones, in a fixed order)."""
    from retile_walls import tileset_kinds, read_layout, wall_keys, TILESET
    kinds_of = tileset_kinds(TILESET)
    keys = set()
    for path in levels:
        cells = read_layout(open(path, encoding='utf-8').read())[0]
        keys |= set(wall_keys(cells, kinds_of).values())
    order = list(DIRS)
    extra = [k for k in keys if any(w != FLOOR for _, w in k)]
    return sorted(extra, key=lambda s: sorted((order.index(d), w) for d, w in s))


def tile(key):
    """Draws one wall tile. `key` lists its open neighbours and what they are.
    Every pixel looks at how far it is from the nearest floor or panel face
    (counting diagonal steps as 1: "Chebyshev distance"), so neighbouring
    tiles always line up."""
    im = Image.new('RGBA', (T, T), TOP)
    px = im.load()
    rects = []                         # open neighbours, in this tile's pixels: (x0, y0, x1, y1)
    for d, what in key:
        sx, sy = DIRS[d][0] * T - T, DIRS[d][1] * T - T
        top = sy + (PANEL_EDGE if what == PANEL_TOP else 0)
        rects.append((sx, top, sx + T - 1, sy + T - 1))

    def dist(x, y):
        best = 99
        for (x0, y0, x1, y1) in rects:
            dx = max(x0 - x, x - x1, 0)
            dy = max(y0 - y, y - y1, 0)
            best = min(best, max(dx, dy))
        return best

    for y in range(T):
        for x in range(T):
            d = dist(x, y)                 # 1 = touching the floor
            if d - 1 < len(STEPS):
                px[x, y] = STEPS[d - 1]
    return im


if __name__ == '__main__':
    import glob, sys
    sys.path.insert(0, 'tools')
    pieces = base_pieces() + needed_pieces(sorted(glob.glob('Levels/level_*.tscn')))
    rows = (len(pieces) + COLS - 1) // COLS
    sheet = Image.new('RGBA', (COLS * T, rows * T), (0, 0, 0, 0))
    info = []
    for i, p in enumerate(pieces):
        x, y = i % COLS, i // COLS
        sheet.paste(tile(p), (x * T, y * T))
        what = dict(p)
        entry = {'x': x, 'y': y, 'open': [d for d in DIRS if what.get(d) == FLOOR]}
        for kind in (PANEL_TOP, PANEL):
            if kind in what.values():
                entry[kind] = [d for d in DIRS if what.get(d) == kind]
        info.append(entry)
    sheet.save(OUT)
    json.dump(info, open(OUT_JSON, 'w'), indent=1)
    print(f'{OUT}: {len(pieces)} wall pieces ({len(pieces) - 47} next to front panels), {OUT_JSON}')
