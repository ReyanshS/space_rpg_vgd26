# move_rooms.py: moves whole rooms (or a multistage area) somewhere else on the
# map, to give them more space, without changing their puzzles.
#
#     python3 tools/move_rooms.py Levels/level_1.tscn --move 20,35+15,48:2,3 --grow 24,30 [--dry]
#
#   --move CELLS:DX,DY   the rooms containing these floor tiles (x,y, joined with +)
#                        move DX tiles right and DY down. A room joined to others by
#                        a barrier takes its whole area with it (all its stages).
#   --grow X,Y           the hall containing this tile may grow to reach a door that
#                        moved away from it (halls have no puzzle, so their shape is free)
#
# What moves with a room: its floor and everything on it, its barriers, the doors
# between moved rooms, the walls inside the area (between its stages), and a door
# to a room that stays (the hall on the other side grows to meet it). Everything
# placed by hand moves along: story beats, tutorial steps, hint routes, power
# links, TestStart (any `position` / FloorGuide `points` on a moved tile).
# The room keeps its exact shape, so its puzzle, wire routes and timers don't
# change. The place it left becomes wall. Afterwards the walls are repainted
# (tools/retile_walls.py): panels that no longer face a room are cleared, and
# the new front walls get panels.
# It refuses to put a moved tile on top of another room, a door or anything that
# isn't wall. Then: regenerate the autopilot routes and check with the solver.
import re, sys
sys.path.insert(0, 'tools')
from retile_walls import tileset_kinds, read_layout, write_layout, TILESET, retile
from space_rooms import _num

T = 32
DOORS = {'door', 'fuse_door', 'main_door'}
NOT_ROOM = {'', 'wall', 'barrier', 'space', '?'} | DOORS
WALL = [0, 1, 0, 0]               # the plain wall tile (Layout palette)
DIRS = ((1, 0), (-1, 0), (0, 1), (0, -1))


def kinds(cells, kinds_of):
    return {c: kinds_of.get(tuple(v[:3]), '?') for c, v in cells.items()}


def room_cells(kind, seed, with_barriers):
    """The floor tiles of the room containing seed (and with_barriers: every room
    joined to it through barriers, plus the barriers)."""
    ok = lambda c: kind.get(c, '') not in NOT_ROOM or (with_barriers and kind.get(c) == 'barrier')
    if not ok(seed):
        sys.exit(f'{seed} is not a room tile')
    out = {seed}
    todo = [seed]
    while todo:
        x, y = todo.pop()
        for dx, dy in DIRS:
            n = (x + dx, y + dy)
            if n not in out and ok(n):
                out.add(n)
                todo.append(n)
    return out


def group_of(kind, seeds):
    rooms = set()
    for s in seeds:
        rooms |= room_cells(kind, s, True)
    # doors touching the group (whole door groups)
    doors = set()
    for c, k in kind.items():
        if k in DOORS and any((c[0] + dx, c[1] + dy) in rooms for dx, dy in DIRS):
            doors.add(c)
    # walls inside the group: in the box round its rooms, and not touching any
    # other room (those are the walls between its own stages)
    xs = [c[0] for c in rooms]
    ys = [c[1] for c in rooms]
    walls = set()
    for x in range(min(xs), max(xs) + 1):
        for y in range(min(ys), max(ys) + 1):
            c = (x, y)
            if kind.get(c) != 'wall':
                continue
            near = [(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)]
            other_room = any((kind.get(n, '') not in NOT_ROOM and n not in rooms)
                             or (kind.get(n, '') in DOORS and n not in doors) for n in near)
            if not other_room:
                walls.add(c)
    return rooms | doors | walls, doors


def move(cells, kinds_of, seeds, off, grow_halls):
    kind = kinds(cells, kinds_of)
    group, doors = group_of(kind, seeds)
    dx, dy = off
    # which way each door opens onto a room that stays (worked out before anything
    # moves or grows, so a hall grown for one door tile can't fool the next one)
    door_out = {}
    for d in doors:
        for ex, ey in DIRS:
            n = (d[0] + ex, d[1] + ey)
            if n not in group and kind.get(n, '') not in NOT_ROOM:
                door_out[d] = (ex, ey)
    old = {c: cells[c][:] for c in group}
    for c in group:
        cells[c] = WALL[:]                                      # the place it leaves: wall
    for (x, y), v in old.items():
        t = (x + dx, y + dy)
        tk = kinds_of.get(tuple(cells[t][:3]), '?') if t in cells else ''
        if tk not in ('', 'wall'):
            sys.exit(f'moving {(x, y)} onto {t}, which is {tk}: not enough room there')
        cells[t] = v
    # a door to a room that stays: grow that hall to meet the door where it is now
    kind = kinds(cells, kinds_of)
    moved = {(c[0] + dx, c[1] + dy) for c in group}
    for d, (ex, ey) in door_out.items():
        nd = (d[0] + dx, d[1] + dy)
        outside = (d[0] + ex, d[1] + ey)
        hall = None
        for g in grow_halls:
            cells_of_hall = room_cells(kind, g, False)
            if outside in cells_of_hall:
                hall = cells_of_hall
        if hall is None:
            sys.exit(f'door {d} leads to {outside}, a room that stays: add --grow for it')
        # the tile on the hall's side of the moved door, then a box from the hall to it
        side = (nd[0] + ex, nd[1] + ey)
        hx = [c[0] for c in hall] + [side[0]]
        hy = [c[1] for c in hall] + [side[1]]
        floor = cells[next(iter(hall))][:]
        for x in range(min(hx), max(hx) + 1):
            for y in range(min(hy), max(hy) + 1):
                c = (x, y)
                if c in hall or c in moved:
                    continue
                if kind.get(c, '') != 'wall':
                    continue
                for ex, ey in DIRS:
                    n = (x + ex, y + ey)
                    if kind.get(n, '') not in NOT_ROOM and n not in hall and n not in moved:
                        sys.exit(f'growing the hall at {c} would join it to another room at {n}')
                cells[c] = floor[:]
        kind = kinds(cells, kinds_of)
    return group


def move_nodes(scene, moves):
    """Moves every node whose position is on a moved tile (and FloorGuide points)."""
    def shift(p):
        c = (int(p[0] // T), int(p[1] // T))
        for group, (dx, dy) in moves:
            if c in group:
                return (p[0] + dx * T, p[1] + dy * T)
        return p
    parts = re.split(r'(?=^\[node )', scene, flags=re.M)
    old_g = {'.': (0.0, 0.0)}
    new_g = {'.': (0.0, 0.0)}
    out = [parts[0]]
    for part in parts[1:]:
        head = re.match(r'\[node name="([^"]+)"(?:[^\]]*?parent="([^"]+)")?', part)
        name, parent = head.group(1), head.group(2)
        if parent is None:
            out.append(part)
            continue
        me = name if parent == '.' else f'{parent}/{name}'
        po, pn = old_g.get(parent, (0.0, 0.0)), new_g.get(parent, (0.0, 0.0))
        m = re.search(r'^position = Vector2\(([-\d.e]+), ([-\d.e]+)\)$', part, flags=re.M)
        local = (float(m.group(1)), float(m.group(2))) if m else (0.0, 0.0)
        go = (po[0] + local[0], po[1] + local[1])
        gn = shift(go) if name not in ('Layout', 'Camera2D') else go
        old_g[me], new_g[me] = go, gn
        if m:
            part = part[:m.start()] + 'position = Vector2(%s, %s)' % (_num(gn[0] - pn[0]), _num(gn[1] - pn[1])) + part[m.end():]
        pm = re.search(r'^points = PackedVector2Array\(([^)]*)\)$', part, flags=re.M)
        if pm and pm.group(1).strip():
            v = [float(t) for t in pm.group(1).split(',')]
            pts = []
            for i in range(0, len(v), 2):
                q = shift((go[0] + v[i], go[1] + v[i + 1]))
                pts += [q[0] - gn[0], q[1] - gn[1]]
            part = part[:pm.start()] + 'points = PackedVector2Array(' + ', '.join(_num(t) for t in pts) + ')' + part[pm.end():]
        out.append(part)
    return ''.join(out)


if __name__ == '__main__':
    path = sys.argv[1]
    args = sys.argv[2:]
    scene = open(path, encoding='utf-8').read()
    kinds_of = tileset_kinds(TILESET)
    cells, header, mt = read_layout(scene)
    grow = [tuple(int(t) for t in args[i + 1].split(',')) for i, a in enumerate(args) if a == '--grow']
    moves = []
    for i, a in enumerate(args):
        if a != '--move':
            continue
        spec, off = args[i + 1].split(':')
        seeds = [tuple(int(t) for t in s.split(',')) for s in spec.split('+')]
        off = tuple(int(t) for t in off.split(','))
        group = move(cells, kinds_of, seeds, off, grow)
        moves.append((group, off))
        print(f'moved {len(group)} tiles by {off}')
    changed, runs, faces = retile(cells, kinds_of)
    print(f'walls repainted: {changed}')
    if '--preview' in args:
        from retile_walls import preview
        preview(cells, kinds_of, args[args.index('--preview') + 1])
    if '--dry' not in args:
        scene = write_layout(scene, cells, header, mt)
        scene = move_nodes(scene, moves)
        open(path, 'w', encoding='utf-8', newline='\n').write(scene)
