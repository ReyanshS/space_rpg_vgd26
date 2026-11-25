# space_rooms.py: moves the rooms of a level further apart, so the walls
# between them are thick enough to look like real walls.
#
#     python3 tools/space_rooms.py Levels/level_1.tscn [--dry] [--preview out.png]
#
# Why: with the 3D walls, a wall between two rooms needs room for its own look.
# Rooms side by side need 2 tiles of wall between them (each room gets its own
# rim). Rooms above each other need 4: a 3 tall front panel for the room below,
# plus 1 tile of wall top above it, so the panel doesn't touch the floor above.
#
# How: "seam carving" (the trick image editors use to resize a picture without
# squashing the important parts). A seam is a path from the top of the map to
# the bottom (or left to right) that only goes through wall, empty map or a
# doorway, never through a room. Doubling every tile on the seam pushes
# everything on one side of it over by one tile: the walls it crossed get one
# tile thicker, and every room just moves, keeping its exact shape. So puzzles,
# wire routes and timers don't change. The seam may zig-zag, but only through
# solid wall (in both rows of a step), so no room is ever torn apart.
# The script keeps adding seams through the thinnest walls until none can
# be thickened any more.
#   - A doorway on a seam gets one floor tile deeper (a short corridor).
#   - Barriers (stages of one area), hull and open space are never crossed:
#     they're part of puzzles (wrapping round a sunk barrier, drift distances).
#   - Everything placed by hand moves with its room: story beats, tutorial
#     steps, hint routes, power links, TestStart, PIP. (Any `position` and
#     FloorGuide `points` in the scene.)
#   - Walls inside one area (the stages of a multistage room, joined by
#     barriers) are left as they are: they're meant to be close.
# The walls are repainted at the end (tools/retile_walls.py, front panels too).
# Afterwards: regenerate the autopilot routes and check the rooms with the
# solver (see tools/README.md).
import re, sys
sys.path.insert(0, 'tools')
from retile_walls import tileset_kinds, read_layout, write_layout, TILESET

T = 32
SIDE_GAP = 2        # wall tiles wanted between rooms side by side
STACK_GAP = 4       # ...and between rooms above each other (3 panel + 1 top)
WALLISH = {'', 'wall'}                    # a seam may run through these (and zig-zag through them)
DOORS = {'door', 'fuse_door', 'main_door'}
NOT_ROOM = WALLISH | DOORS | {'barrier', 'space', 'hull'}
FLOOR = [0, 0, 0, 0]                      # the plain floor tile (Layout palette), for corridors


class Map:
    def __init__(self, cells, kinds_of):
        self.cells = cells
        self.kinds_of = kinds_of
        self.refresh()

    def refresh(self):
        self.kind = {c: self.kinds_of.get(tuple(v[:3]), '?') for c, v in self.cells.items()}
        xs = [c[0] for c in self.cells]
        ys = [c[1] for c in self.cells]
        self.x0, self.x1, self.y0, self.y1 = min(xs), max(xs), min(ys), max(ys)

    def k(self, x, y):
        return self.kind.get((x, y), '')

    def room(self, x, y):
        return self.k(x, y) not in NOT_ROOM

    def areas(self):
        """tile -> area number. Rooms joined by a barrier (the stages of one
        multistage room) are one area: the walls inside it stay as they are."""
        area = {}
        n = 0
        def fill(start, ok):
            nonlocal n
            todo = [start]
            area[start] = n
            while todo:
                x, y = todo.pop()
                for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    c = (x + d[0], y + d[1])
                    if c not in area and ok(c):
                        area[c] = n
                        todo.append(c)
        # rooms and barriers together: a barrier group glues its stages into one area
        for c in self.kind:
            if c not in area and (self.room(*c) or self.k(*c) == 'barrier'):
                fill(c, lambda c: self.room(*c) or self.k(*c) == 'barrier')
                n += 1
        return area


def thin_walls(m, vertical):
    """Wall cells of walls that are too thin. vertical=True: walls between rooms
    side by side (a seam running top to bottom fixes them)."""
    out = set()
    area = m.areas()
    gap = SIDE_GAP if vertical else STACK_GAP
    if vertical:
        lines = [[(x, y) for x in range(m.x0, m.x1 + 1)] for y in range(m.y0, m.y1 + 1)]
    else:
        lines = [[(x, y) for y in range(m.y0, m.y1 + 1)] for x in range(m.x0, m.x1 + 1)]
    for line in lines:
        i = 0
        while i < len(line) - 1:
            if m.room(*line[i]) and m.k(*line[i + 1]) in WALLISH | DOORS:
                j = i + 1
                while j < len(line) and m.k(*line[j]) in WALLISH | DOORS:
                    j += 1
                if (j < len(line) and m.room(*line[j]) and j - i - 1 < gap
                        and area.get(line[i]) != area.get(line[j])):    # two different areas
                    # only the wall tiles: a doorway stays one door wide (a seam
                    # through it adds corridor floor, which doesn't make it thicker)
                    out.update(c for c in line[i + 1:j] if m.k(*c) not in DOORS)
                i = j
            else:
                i += 1
    return out


def find_seam(m, vertical, wanted):
    """The best seam across the whole map: a list of one cell per row (vertical
    seam) or per column, or None. It scores a point for every cell of a thin
    wall it goes through. A seam may go straight on through wall or a doorway,
    or zig-zag sideways, but only inside a run of tiles that are solid wall in
    both lines (otherwise a room would be torn)."""
    if vertical:
        rng, other = list(range(m.y0, m.y1 + 1)), list(range(m.x0 - 1, m.x1 + 2))
        cell = lambda a, b: (b, a)          # a = row, b = column
    else:
        rng, other = list(range(m.x0, m.x1 + 1)), list(range(m.y0 - 1, m.y1 + 2))
        cell = lambda a, b: (a, b)
    kind = lambda a, b: m.k(*cell(a, b))
    ok = lambda a, b: kind(a, b) in WALLISH or kind(a, b) in DOORS
    solid = lambda a, b: kind(a, b) in WALLISH
    best = {}                               # b -> (score, path) along the current line
    for i, a in enumerate(rng):
        new = {}
        if i == 0:
            for b in other:
                if ok(a, b):
                    new[b] = (1 if cell(a, b) in wanted else 0, [b])
        else:
            prev = rng[i - 1]
            # runs of tiles solid in both lines: inside one, the seam may slide freely
            run_best = {}
            run_of = {}
            run = 0
            for b in other:
                if solid(a, b) and solid(prev, b):
                    run_of[b] = run
                    if b in best and (run not in run_best or best[b][0] > run_best[run][0]):
                        run_best[run] = best[b]
                else:
                    run += 1
            for b in other:
                if not ok(a, b):
                    continue
                cands = []
                if b in best:
                    cands.append(best[b])                 # straight on
                if b in run_of and run_of[b] in run_best:
                    cands.append(run_best[run_of[b]])     # slide inside a solid run
                if not cands:
                    continue
                sc, path = max(cands, key=lambda v: v[0])
                new[b] = (sc + (1 if cell(a, b) in wanted else 0), path + [b])
        best = new
        if not best:
            return None
    sc, path = max(best.values(), key=lambda v: v[0])
    if sc == 0:
        return None
    return [cell(a, b) for a, b in zip(rng, path)]


def insert_seam(m, seam, vertical):
    """Doubles the seam: cells after it (right of it / below it) move one tile."""
    at = {c[1] if vertical else c[0]: c for c in seam}       # row (or column) -> seam cell
    new = {}
    for (x, y), v in m.cells.items():
        s = at.get(y if vertical else x)
        if s is not None and ((x > s[0]) if vertical else (y > s[1])):
            new[(x + 1, y) if vertical else (x, y + 1)] = v
        else:
            new[(x, y)] = v
    for s in seam:
        if s not in m.cells:
            continue                                         # empty map: nothing to copy
        d = (s[0] + 1, s[1]) if vertical else (s[0], s[1] + 1)
        if m.k(*s) in DOORS:
            # a doorway gets a corridor tile: the same floor as the room it leads into
            beyond = m.cells.get(d)
            new[d] = beyond[:] if beyond and m.k(*d) == 'floor' else FLOOR[:]
        else:
            new[d] = m.cells[s][:]
    m.cells.clear()
    m.cells.update(new)
    m.refresh()
    return at


def space_out(m, max_seams=60, log=print):
    shifts = []                          # (vertical, {row or column: seam cell}) in order
    for _ in range(max_seams):
        done = True
        for vertical in (True, False):
            wanted = thin_walls(m, vertical)
            if not wanted:
                continue
            seam = find_seam(m, vertical, wanted)
            if seam is None:
                continue
            fixed = sum(1 for c in seam if c in wanted)
            shifts.append((vertical, insert_seam(m, seam, vertical)))
            log(f"  {'column' if vertical else 'row'} seam through {fixed} thin wall tiles")
            done = False
        if done:
            break
    return shifts


def move_point(shifts, p):
    """Where a pixel position ends up after all the seams (it moves with its tile)."""
    x, y = p
    for vertical, at in shifts:
        cx, cy = int(x // T), int(y // T)
        if vertical:
            s = at.get(cy)
            if s is not None and cx > s[0]:
                x += T
        else:
            s = at.get(cx)
            if s is not None and cy > s[1]:
                y += T
    return (x, y)


def move_nodes(scene, shifts):
    """Moves every node's position (and FloorGuide points) with its tile.
    Positions in a .tscn are relative to the parent, so work in level space."""
    parts = re.split(r'(?=^\[node )', scene, flags=re.M)
    path_pos = {'.': (0.0, 0.0)}                # node path -> old position in level space
    out = [parts[0]]
    new_global = {'.': (0.0, 0.0)}
    for part in parts[1:]:
        head = re.match(r'\[node name="([^"]+)"(?:[^\]]*?parent="([^"]+)")?', part)
        name, parent = head.group(1), head.group(2)
        if parent is None:
            out.append(part)
            continue
        me = name if parent == '.' else f'{parent}/{name}'
        pg_old = path_pos.get(parent, (0.0, 0.0))
        pg_new = new_global.get(parent, (0.0, 0.0))
        m = re.search(r'^position = Vector2\(([-\d.e]+), ([-\d.e]+)\)$', part, flags=re.M)
        local = (float(m.group(1)), float(m.group(2))) if m else (0.0, 0.0)
        g_old = (pg_old[0] + local[0], pg_old[1] + local[1])
        g_new = move_point(shifts, g_old) if name not in ('Layout', 'Camera2D') else g_old
        path_pos[me] = g_old
        new_global[me] = g_new
        if m:
            nl = (g_new[0] - pg_new[0], g_new[1] - pg_new[1])
            part = part[:m.start()] + 'position = Vector2(%s, %s)' % (_num(nl[0]), _num(nl[1])) + part[m.end():]
        pm = re.search(r'^points = PackedVector2Array\(([^)]*)\)$', part, flags=re.M)
        if pm and pm.group(1).strip():
            v = [float(t) for t in pm.group(1).split(',')]
            pts = []
            for i in range(0, len(v), 2):
                q = move_point(shifts, (g_old[0] + v[i], g_old[1] + v[i + 1]))
                pts += [q[0] - g_new[0], q[1] - g_new[1]]
            part = part[:pm.start()] + 'points = PackedVector2Array(' + ', '.join(_num(t) for t in pts) + ')' + part[pm.end():]
        out.append(part)
    return ''.join(out)


def _num(f):
    return str(int(f)) if f == int(f) else repr(f)


if __name__ == '__main__':
    path = sys.argv[1]
    scene = open(path, encoding='utf-8').read()
    kinds_of = tileset_kinds(TILESET)
    cells, header, mt = read_layout(scene)
    m = Map(cells, kinds_of)
    before = (len(thin_walls(m, True)), len(thin_walls(m, False)), m.x1 - m.x0 + 1, m.y1 - m.y0 + 1)
    shifts = space_out(m)
    after = (len(thin_walls(m, True)), len(thin_walls(m, False)), m.x1 - m.x0 + 1, m.y1 - m.y0 + 1)
    print(f'{path}: {len(shifts)} seams. Thin wall tiles side by side {before[0]} -> {after[0]}, '
          f'stacked {before[1]} -> {after[1]}. Map {before[2]}x{before[3]} -> {after[2]}x{after[3]} tiles')
    # the walls changed shape: repaint all of them, front panels too
    from retile_walls import retile, preview
    retile(m.cells, kinds_of, keep_faces=False)
    if '--preview' in sys.argv:
        preview(m.cells, kinds_of, sys.argv[sys.argv.index('--preview') + 1])
    if '--dry' not in sys.argv:
        scene = write_layout(scene, m.cells, header, mt)
        scene = move_nodes(scene, shifts)
        open(path, 'w', encoding='utf-8', newline='\n').write(scene)
