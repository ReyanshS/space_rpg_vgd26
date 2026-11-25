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
# Walls the team painted as front panels themselves (source 2) are kept, unless
# you add --all (then every wall is repainted, front panels too).
# Floor under a face isn't touched: once the wall above is a team tile, the
# game draws plain floor there (no more light strip).
# Run it again after big map changes: it only rewrites walls.
import base64, json, re, struct, sys
sys.path.insert(0, 'tools')

TILESET = 'Assets/images/tiles/layout_tileset.tres'
SRC_FACE, SRC_SIDES, SRC_CAP, SRC_STRIP = 2, 3, 8, 9
PANELS = (SRC_FACE, SRC_CAP, SRC_STRIP)        # front panel tiles: kept as painted
# panel ends with the skirting round the corner (tools/art_wall_caps.py): index = style * 2 + side
CAP_STYLES = [(0, 5), (3, 9), (6, 9)]          # (first row in wall.png, right end column) per panel
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


def mixed_columns(w):
    """The team's own way of building a front panel (Nov 2026, the panels they
    painted in Level 1): a windows panel top row, a power strip through the
    middle broken by a feature (a window or a monitor, taking turns) between
    the strip's pointed ends, strip bottoms below, and their cap tiles at both
    ends. Returns, per column, the three tiles [source, x, y] top to bottom."""
    W, S = SRC_FACE, SRC_STRIP
    top = lambda i: [W, 1 + i % 2, 3]                          # windows panel top, plain
    strip = lambda i: [top(i), [S, 4, 1], [S, 4, 2]]
    cols = [[[W, 0, 3], [S, 0, 1], [W, 0, 5]]]                  # left end
    n = w - 2
    # features about every 5 tiles, spread evenly, each with room for the strip's
    # pointed ends either side (so never next to an end or another feature)
    k = max(1, round(n / 5)) if n >= 3 else 0
    spots = sorted({round((j + 0.5) * n / k - 0.5) for j in range(k)}) if k else []
    spots = [p for p in spots if 1 <= p <= n - 2]
    body = [strip(i) for i in range(n)]
    for j, p in enumerate(spots):
        if j % 2 == 0:
            body[p] = [[W, 1, 3], [W, 1, 4], [W, 1, 5]]       # a window (windows panel, column 1)
        else:
            body[p] = [[W, 1, 6], [W, 1, 7], [W, 1, 8]]       # a monitor with its wire (computers panel)
        body[p - 1][1] = [S, 2, 1]                            # the strip ends in a point...
        body[p + 1][1] = [S, 3, 1]                            # ...and starts again after it
    cols += body
    cols.append([[W, 9, 3], [S, 5, 1], [W, 9, 5]])            # right end
    return cols


def panel_valid(cells, kind, c):
    """A painted front panel tile still faces a room: right under the panel's
    bottom row there's floor (it isn't left hanging after a map change)."""
    src, ax, ay = cells[c][:3]
    row = 0 if src == SRC_CAP else (ay if src == SRC_STRIP else ay % 3)   # 0 top, 1, 2 bottom
    for i in range(1, 3 - row):
        if kind.get((c[0], c[1] + i), '') != 'wall':
            return False
    below = kind.get((c[0], c[1] + 3 - row), '')
    return below not in CLOSED and below not in DOORS


def pick_style(w, x, y):
    if w >= 4:
        return 'mixed'                           # new panels: built the team's way
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


def retile(cells, kinds_of, keep_faces=True):
    kind = {c: kinds_of.get(tuple(v[:3]), '?') for c, v in cells.items()}
    # painted panels left hanging (no room under them any more): plain wall again
    for c in list(cells):
        if cells[c][0] in PANELS and not panel_valid(cells, kind, c):
            cells[c] = [0, 1, 0, 0]
    keep = lambda c: keep_faces and cells[c][0] in PANELS      # a front panel painted by hand
    k = lambda c: kind.get(c, '')
    # 1. front faces: depth 1 = wall right above floor (not a door, not space), up to 3
    depth = {}
    ys = sorted({c[1] for c in kind}, reverse=True)
    for y in ys:
        for c in [c for c in kind if c[1] == y]:
            if k(c) != 'wall' or keep(c):
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
        if style == 'mixed':
            for i, tiles in enumerate(mixed_columns(w)):
                for r in range(3):
                    faces[(c[0] + i, c[1] - 2 + r)] = tiles[r] + [0]
        else:
            for i, col in enumerate(panel_columns(style, w)):
                for r in range(3):
                    faces[(c[0] + i, c[1] - 2 + r)] = [SRC_FACE, col, PANEL_ROW[style] + r, 0]
        runs += 1
    # 2. every other wall: the piece whose edges match the floor (and the front
    # panels) round it
    if not keep_faces:
        for c in cells:
            if cells[c][0] in PANELS and c not in faces:
                cells[c] = [0, 1, 0, 0]          # was a panel, isn't any more: a plain wall for now
    for c, v in faces.items():
        cells[c] = v
    _wrap_panel_ends(cells, kind)
    pieces = {}
    from art_wall_sides import canonical, FLOOR
    for p in json.load(open('Assets/images/tiles/team/wall_sides.json')):
        what = {d: FLOOR for d in p['open']}
        for kind in ('panel_top', 'panel'):
            what.update({d: kind for d in p.get(kind, [])})
        pieces[canonical(what)] = (p['x'], p['y'])
    changed = 0
    missing = 0
    for c, key in wall_keys(cells, kinds_of, keep_faces).items():
        if key not in pieces:
            # a combination the sheet doesn't have yet: use the plain one (run
            # tools/art_wall_sides.py and build_team_tiles.gd to add it)
            key = canonical({d: FLOOR for d, w in key if w == FLOOR})
            missing += 1
        x, y = pieces[key]
        cells[c] = [SRC_SIDES, x, y, 0]
        changed += 1
    changed += len(faces)
    if missing:
        print(f'  {missing} walls next to front panels used a plain piece: run tools/art_wall_sides.py, '
              'then tools/build_team_tiles.gd, then this again')
    return changed, runs, len(faces)


def _wrap_panel_ends(cells, kind):
    """A panel end with floor (or a doorway) beside it gets the end tile whose
    top skirting wraps round the corner; one without goes back to the plain end."""
    for (x, y), v in list(cells.items()):
        if v[0] == SRC_CAP:
            style, side = divmod(v[1], 2)
            row, right = CAP_STYLES[style]
            v = cells[(x, y)] = [SRC_FACE, right if side else 0, row, 0]
        if v[0] == SRC_STRIP and v[2] == 0 and v[1] in (0, 5):
            v = [SRC_FACE, v[1], 0, 0]          # the bolt-less strip has the power strip's ends
        if v[0] != SRC_FACE:
            continue
        for style, (row, right) in enumerate(CAP_STYLES):
            if v[2] != row:
                continue
            for side, col, dx in ((0, 0, -1), (1, right, 1)):
                if v[1] == col and kind.get((x + dx, y), '') not in CLOSED:
                    cells[(x, y)] = [SRC_CAP, style * 2 + side, 0, 0]


def wall_keys(cells, kinds_of, keep_faces=True):
    """Every wall that isn't a front panel -> which of its neighbours are
    floor or front panel (a key from art_wall_sides.canonical)."""
    from art_wall_sides import canonical, FLOOR, PANEL_TOP, PANEL
    kind = {c: kinds_of.get(tuple(v[:3]), '?') for c, v in cells.items()}
    out = {}
    for c, v in cells.items():
        if kind[c] != 'wall' or v[0] in PANELS:
            continue
        what = {}
        for d, (dx, dy) in NEIGHBOURS.items():
            n = (c[0] + dx, c[1] + dy)
            nk = kind.get(n, '')
            if nk not in CLOSED:
                what[d] = FLOOR
            elif nk == 'wall' and cells[n][0] == SRC_FACE:
                what[d] = PANEL_TOP if cells[n][2] % 3 == 0 else PANEL    # rows 0, 3, 6 = a panel's top row
            elif nk == 'wall' and cells[n][0] == SRC_CAP:
                what[d] = PANEL_TOP
            elif nk == 'wall' and cells[n][0] == SRC_STRIP:
                what[d] = PANEL_TOP if cells[n][2] == 0 else PANEL
        out[c] = canonical(what)
    return out


def preview(cells, kinds_of, out):
    """A picture of the whole map: team tiles as they look, floor plain, the rest as palette icons."""
    from PIL import Image
    T = 32
    sheets = {0: 'Assets/images/tiles/layout_tiles.png', 1: 'Assets/images/tiles/team/ground.png',
              2: 'Assets/images/tiles/team/wall.png', 3: 'Assets/images/tiles/team/wall_sides.png',
              4: 'Assets/images/tiles/team/objects.png', 5: 'Assets/images/tiles/team/start_anim.png',
              6: 'Assets/images/tiles/team/goal_anim.png', 7: 'Assets/images/tiles/team/node_anim.png',
              8: 'Assets/images/tiles/team/wall_caps.png', 9: 'Assets/images/tiles/team/wall_strip.png'}
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
    changed, runs, face_cells = retile(cells, kinds_of, keep_faces='--all' not in sys.argv)
    print(f'{path}: {changed} walls repainted ({runs} front panels, {face_cells} face tiles)')
    if '--preview' in sys.argv:
        preview(cells, kinds_of, sys.argv[sys.argv.index('--preview') + 1])
    if '--dry' not in sys.argv:
        open(path, 'w', encoding='utf-8', newline='\n').write(write_layout(scene, cells, header, m))
