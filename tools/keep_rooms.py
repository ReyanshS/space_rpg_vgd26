# keep_rooms.py: deletes every room of a level except the ones you name.
#
#     python3 tools/keep_rooms.py Levels/level_1.tscn 13,20 7,14 15,9 [--dry]
#
# Each x,y is a floor tile (a START pad is handy) in a room to keep. Kept:
#   - those rooms, and the doors between them (a door to a deleted room
#     becomes wall);
#   - a frame of wall FRAME tiles thick round them (room for a 3 tall front
#     panel plus the top of the wall); beyond it the map is erased, so the
#     walls fade out into the background (tools/art_wall_sides.py, "void").
# Deleted from the scene: every story beat, tutorial step, hint route and power
# link that sat in a deleted room. Story beats that play for the whole level
# (LEVEL_START, ALL_POWERED, TOUCH_EMPTY_CELL, SHIP_LIGHTS_UP) stay wherever they are.
# The level's room lists (room_titles, room_wire_time) and the judge mode
# walkthrough keep only the rooms left. The walls are repainted at the end.
# Close Godot first. Then regenerate the autopilot routes with the solver.
import re, sys
sys.path.insert(0, 'tools')
from retile_walls import tileset_kinds, read_layout, write_layout, TILESET, retile
from move_rooms import room_cells, kinds, DOORS, DIRS

T = 32
FRAME = 4
WALL = [0, 1, 0, 0]
LEVEL_WIDE = {0, 7, 9, 10}         # StoryBeat triggers that don't belong to a room


def keep_rooms(cells, kinds_of, seeds):
    kind = kinds(cells, kinds_of)
    keep = set()
    for s in seeds:
        keep |= room_cells(kind, s, False)
    doors = {c for c, k in kind.items() if k in DOORS
             and any((c[0] + dx, c[1] + dy) in keep for dx, dy in DIRS)}
    # a door is kept only if every room it touches is kept
    def touches_only_kept(c):
        for dx, dy in DIRS:
            n = (c[0] + dx, c[1] + dy)
            nk = kind.get(n, '')
            if nk not in ('', 'wall', 'space', '?') and nk not in DOORS and n not in keep:
                return False
        return True
    doors = {c for c in doors if touches_only_kept(c)}
    inside = keep | doors
    out = {}
    for c in inside:
        out[c] = cells[c]
    for (x, y) in inside:
        for dx in range(-FRAME, FRAME + 1):
            for dy in range(-FRAME, FRAME + 1):
                n = (x + dx, y + dy)
                if n in inside or n in out:
                    continue
                out[n] = cells[n] if kind.get(n) == 'wall' else WALL[:]
    cells.clear()
    cells.update(out)
    return keep, inside


def drop_nodes(scene, kept_cells):
    """Deletes the story / tutorial / hint / link nodes in deleted rooms."""
    parts = re.split(r'(?=^\[node )', scene, flags=re.M)
    pos = {'.': (0.0, 0.0)}
    dropped = set()
    out = [parts[0]]
    names = []
    for part in parts[1:]:
        head = re.match(r'\[node name="([^"]+)"(?:[^\]]*?parent="([^"]+)")?', part)
        name, parent = head.group(1), head.group(2)
        if parent is None:
            out.append(part)
            continue
        me = name if parent == '.' else f'{parent}/{name}'
        if parent in dropped or any(parent.startswith(d + '/') for d in dropped):
            dropped.add(me)
            continue
        m = re.search(r'^position = Vector2\(([-\d.e]+), ([-\d.e]+)\)$', part, flags=re.M)
        local = (float(m.group(1)), float(m.group(2))) if m else (0.0, 0.0)
        g = (pos.get(parent, (0, 0))[0] + local[0], pos.get(parent, (0, 0))[1] + local[1])
        pos[me] = g
        top = me.split('/')[0]
        if top in ('Story', 'Tutorial', 'Hints', 'Links') and '/' in me and me.count('/') == 1:
            cells_here = [(int(g[0] // T), int(g[1] // T))] if m else []
            pm = re.search(r'^points = PackedVector2Array\(([^)]*)\)$', part, flags=re.M)
            if pm and pm.group(1).strip():
                v = [float(t) for t in pm.group(1).split(',')]
                cells_here += [(int((g[0] + v[i]) // T), int((g[1] + v[i + 1]) // T)) for i in range(0, len(v), 2)]
            trig = re.search(r'^trigger = (\d+)$', part, flags=re.M)
            level_wide = top == 'Story' and trig is not None and int(trig.group(1)) in LEVEL_WIDE
            gone = top == 'Links' or (cells_here and not level_wide
                                      and not all(c in kept_cells for c in cells_here))
            if gone:
                dropped.add(me)
                names.append(me)
                continue
        out.append(part)
    return ''.join(out), names


def trim_lists(scene, n):
    def cut(m, kind):
        items = re.findall(r'"(?:[^"\\]|\\.)*"' if kind == 'str' else r'[-\d.e]+', m.group(2))
        return f'{m.group(1)}({", ".join(items[:n])})'
    scene = re.sub(r'^(room_titles = PackedStringArray)\((.*)\)$', lambda m: cut(m, 'str'), scene, count=1, flags=re.M)
    scene = re.sub(r'^(room_wire_time = PackedFloat32Array)\((.*)\)$', lambda m: cut(m, 'num'), scene, count=1, flags=re.M)
    scene = re.sub(r'^walkthrough = PackedInt32Array\(.*\)$', 'walkthrough = PackedInt32Array(' + ', '.join(str(i + 1) for i in range(n)) + ')', scene, count=1, flags=re.M)
    return scene


if __name__ == '__main__':
    path = sys.argv[1]
    seeds = [tuple(int(t) for t in a.split(',')) for a in sys.argv[2:] if a[0].isdigit()]
    scene = open(path, encoding='utf-8').read()
    kinds_of = tileset_kinds(TILESET)
    cells, header, mt = read_layout(scene)
    before = len(cells)
    keep, inside = keep_rooms(cells, kinds_of, seeds)
    retile(cells, kinds_of)
    print(f'{path}: kept {len(seeds)} rooms ({len(keep)} floor tiles), map {before} -> {len(cells)} tiles')
    scene = write_layout(scene, cells, header, mt)
    scene, names = drop_nodes(scene, inside)
    print('deleted nodes:', ', '.join(names))
    scene = trim_lists(scene, len(seeds))
    if '--dry' not in sys.argv:
        open(path, 'w', encoding='utf-8', newline='\n').write(scene)
