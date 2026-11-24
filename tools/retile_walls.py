# retile_walls.py: swaps a level's old walls for the team's new wall tiles.
#
#     python3 tools/retile_walls.py Levels/level_1.tscn [--preview out.png] [--dry]
#
# The old walls were plain grey "wall" tiles that level.gd turned into a picture
# by itself (a face panel above floor, a roof everywhere else). This script
# repaints every wall on the Layout as single tiles you can see and edit:
#   - FRONT FACES: a wall column that stands 3 tiles tall right above floor gets
#     the team's front panels (wall.png). Each run of such columns becomes one
#     panel with a cap on both ends: 6 wide = the power strip panel, 10 wide =
#     windows or computers, any other width = a panel stretched to fit (middle
#     columns repeated). Shorter walls (1 or 2 tall) have no face: you see them
#     from above, like the side walls.
#   - EVERY OTHER WALL: one of the 47 wall pieces (wall_sides.png, drawn by
#     tools/art_wall_sides.py), picked by which of its 8 neighbours are floor,
#     so the edge always follows the floor and everything else fades to dark.
# Walls the team painted as front panels themselves (source 2) are kept.
# Floor under a face isn't touched: once the wall above is a team tile, the
# game draws plain floor there (no more light strip).
# Run it again after big map changes: it only rewrites walls.
import base64, json, re, struct, sys
sys.path.insert(0, 'tools')

TILESET = 'Assets/images/tiles/layout_tileset.tres'
SRC_FACE, SRC_SIDES = 2, 3
# what isn't floor for a wall's edge: nothing, other walls and open space
# (space stays dark, the starfield shows round it)
CLOSED = {'', 'wall', 'space', '?'}
DOORS = {'door', 'fuse_door', 'main_door'}
NEIGHBOURS = {'N': (0, -1), 'NE': (1, -1), 'E': (1, 0), 'SE': (1, 1),
              'S': (0, 1), 'SW': (-1, 1), 'W': (-1, 0), 'NW': (-1, -1)}
# the team's front panels in wall.png: first row of each, and its columns
PANEL_ROW = {'power': 0, 'windows': 3, 'computers': 6}


def tileset_kinds(path):
    """(source id, atlas x, atlas y) -> kind (same as map_from_scene.py)."""
    text = open(path, encoding='utf-8').read()
    ids = {m.group(2): int(m.group(1)) for m in re.finditer(r'sources/(\d+) = SubResource\("([^"]+)"\)', text)}
    out = {}
    for block in re.split(r'\n(?=\[sub_resource )', text):
        m = re.match(r'\[sub_resource type="TileSetAtlasSource" id="([^"]+)"\]', block)
        if not m or m.group(1) not in ids:
            continue
        for k in re.finditer(r'(\d+):(\d+)/0/custom_data_0 = "(\w*)"', block):
            out[(ids[m.group(1)], int(k.group(1)), int(k.group(2)))] = k.group(3)
    return out


def read_layout(scene):
    """The Layout's cells: (x, y) -> [source, atlas x, atlas y, alternative], and the header bytes."""
    start = scene.index('[node name="Layout"')
    m = re.compile(r'tile_map_data = PackedByteArray\(([^)]*)\)').search(scene, start)
    raw = m.group(1).strip()
    data = base64.b64decode(raw.strip('"')) if raw.startswith('"') else bytes(int(v) for v in raw.split(','))
    cells = {}
    for i in range(2, len(data) - 11, 12):
        x, y, s, ax, ay, alt = struct.unpack('<hhHHHH', data[i:i + 12])
        cells[(x, y)] = [s, ax, ay, alt]
    return cells, data[:2], m


def write_layout(scene, cells, header, m):
    data = header + b''.join(struct.pack('<hhHHHH', x, y, *v) for (x, y), v in sorted(cells.items(), key=lambda kv: (kv[0][1], kv[0][0])))
    if m.group(1).strip().startswith('"'):
        packed = 'PackedByteArray("' + base64.b64encode(data).decode('ascii') + '")'
    else:
        packed = 'PackedByteArray(' + ', '.join(str(b) for b in data) + ')'
    return scene[:m.start()] + 'tile_map_data = ' + packed + scene[m.end():]


def panel_columns(style, w):
    """Which columns of a panel picture make a panel `w` tiles wide."""
    if style == 'power':          # cap, strip..., lightning (2 columns), strip..., cap
        a = (w - 4) // 2
        return [0] + [1] * a + [2, 3] + [4] * (w - 4 - a) + [5]
    if style == 'computers':
        if w == 10:
            return list(range(10))
        p = (w - 6) // 2          # cap, 2 monitors, plain..., console (2 columns), plain..., cap
        return [0, 1, 2] + [3] * p + [4, 5] + [6] * (w - 6 - p) + [9]
    # windows: cap, then windows and plain panels taking turns (mirrored, so the
    # panel looks the same from both ends), cap
    # (an even number of middle columns puts a plain panel in the centre, so two
    # windows never end up side by side)
    n = w - 2
    parity = 0 if n % 2 else 1 - (n // 2 - 1) % 2
    return [0] + [1 if min(i, n - 1 - i) % 2 == parity else 2 for i in range(n)] + [9]


def pick_style(w, x, y):
    if w == 6 or w == 4:
        return 'power'                           # (4 wide: too narrow for windows to show)
    if w == 10:
        return 'computers' if (x + y) % 2 == 0 else 'windows'
    h = (x * 7 + y * 13) % 3                     # a bit of variety from place to place
    if h == 0 and w >= 7:
        return 'computers'
    if h == 1 and w >= 4:
        return 'power'
    return 'windows'


def retile(cells, kinds_of):
    kind = {c: kinds_of.get(tuple(v[:3]), '?') for c, v in cells.items()}
    k = lambda c: kind.get(c, '')
    # 1. front faces: depth 1 = wall right above floor (not a door, not space), up to 3
    depth = {}
    ys = sorted({c[1] for c in kind}, reverse=True)
    for y in ys:
        for c in [c for c in kind if c[1] == y]:
            if k(c) != 'wall' or cells[c][0] == SRC_FACE:
                continue
            below = k((c[0], c[1] + 1))
            if below not in CLOSED and below not in DOORS:
                depth[c] = 1
            elif below == 'wall' and depth.get((c[0], c[1] + 1), 0) in (1, 2):
                depth[c] = depth[(c[0], c[1] + 1)] + 1
    full = {c for c, d in depth.items() if d == 1 and depth.get((c[0], c[1] - 1)) == 2 and depth.get((c[0], c[1] - 2)) == 3}
    faces = {}
    runs = 0
    for c in sorted(full, key=lambda c: (c[1], c[0])):
        if (c[0] - 1, c[1]) in full:
            continue                                  # not the left end of a run
        w = 0
        while (c[0] + w, c[1]) in full:
            w += 1
        if w < 2:
            continue                                  # one column alone: no room for a panel's two caps
        style = pick_style(w, c[0], c[1])
        for i, col in enumerate(panel_columns(style, w)):
            for r in range(3):
                faces[(c[0] + i, c[1] - 2 + r)] = [SRC_FACE, col, PANEL_ROW[style] + r, 0]
        runs += 1
    # 2. every other wall: the piece whose edges match the floor round it
    pieces = {frozenset(p['open']): (p['x'], p['y']) for p in json.load(open('Assets/images/tiles/team/wall_sides.json'))}
    from art_wall_sides import canonical
    changed = 0
    for c in list(cells):
        if k(c) != 'wall' or cells[c][0] == SRC_FACE:
            continue
        if c in faces:
            cells[c] = faces[c]
        else:
            open_dirs = [d for d, (dx, dy) in NEIGHBOURS.items() if k((c[0] + dx, c[1] + dy)) not in CLOSED]
            x, y = pieces[canonical(open_dirs)]
            cells[c] = [SRC_SIDES, x, y, 0]
        changed += 1
    return changed, runs, len(faces)


def preview(cells, kinds_of, out):
    """A picture of the whole map: team tiles as they look, floor plain, the rest as palette icons."""
    from PIL import Image
    T = 32
    sheets = {0: 'Assets/images/tiles/layout_tiles.png', 1: 'Assets/images/tiles/team/ground.png',
              2: 'Assets/images/tiles/team/wall.png', 3: 'Assets/images/tiles/team/wall_sides.png',
              4: 'Assets/images/tiles/team/objects.png', 5: 'Assets/images/tiles/team/start_anim.png',
              6: 'Assets/images/tiles/team/goal_anim.png', 7: 'Assets/images/tiles/team/node_anim.png'}
    img = {s: Image.open(p).convert('RGBA') for s, p in sheets.items()}
    floor = Image.open('Assets/images/tiles/floor.png').convert('RGBA').crop((0, 0, T, T))
    xs = [c[0] for c in cells]
    ys = [c[1] for c in cells]
    x0, y0 = min(xs), min(ys)
    im = Image.new('RGBA', ((max(xs) - x0 + 1) * T, (max(ys) - y0 + 1) * T), (18, 18, 22, 255))
    for (x, y), (s, ax, ay, alt) in cells.items():
        kind = kinds_of.get((s, ax, ay), '')
        at = ((x - x0) * T, (y - y0) * T)
        if s == 0 and kind not in ('wall', 'space'):
            im.alpha_composite(floor, at)
            if kind == 'floor':
                continue
        if kind == 'space':
            continue
        im.alpha_composite(img[s].crop((ax * T, ay * T, ax * T + T, ay * T + T)), at)
    im.save(out)


if __name__ == '__main__':
    path = sys.argv[1]
    scene = open(path, encoding='utf-8').read()
    kinds_of = tileset_kinds(TILESET)
    cells, header, m = read_layout(scene)
    changed, runs, face_cells = retile(cells, kinds_of)
    print(f'{path}: {changed} walls repainted ({runs} front panels, {face_cells} face tiles)')
    if '--preview' in sys.argv:
        preview(cells, kinds_of, sys.argv[sys.argv.index('--preview') + 1])
    if '--dry' not in sys.argv:
        open(path, 'w', encoding='utf-8', newline='\n').write(write_layout(scene, cells, header, m))
