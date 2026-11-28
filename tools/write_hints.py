# write_hints.py: turns the solver's routes into each room's H hint.
#
#     python3 tools/write_hints.py Levels/level_1.tscn Data/routes/level_1.json
#
# (or add --hints to the solver run that writes the routes:
#     python3 tools/solver2.py Levels/level_1.tscn --paths Data/routes/level_1.json --margin 3 --hints)
#
# Every route in the routes file (the same one PIP's autopilot walks in judge
# mode) becomes a hint: a FloorGuide with "Hint Only" ticked, under the level's
# Hints node. The route's 4 px steps are cut down to its corners (any point that
# lies within SIMPLIFY px of the straight line between its neighbours goes), so
# the chevrons run along a few straight pieces.
#   - A hint that already starts on that room's START is updated in place (same
#     node, same name).
#   - Otherwise a new one is added, named HintRoomN.
#   - Rooms the tutorial already walks you through (a Tutorial guide starting on
#     their START) get no hint.
# Close Godot first: it would save its old copy of the level over this one.
import json, math, random, re, sys

TILE = 32
SIMPLIFY = 6.0


def simplify(pts, eps=SIMPLIFY):
    """Ramer-Douglas-Peucker: keep only the points the shape needs."""
    if len(pts) < 3:
        return pts
    a, b = pts[0], pts[-1]
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)

    def dist(p):
        if length == 0:
            return math.hypot(p[0] - a[0], p[1] - a[1])
        return abs(dy * p[0] - dx * p[1] + b[0] * a[1] - b[1] * a[0]) / length
    i, far = max(((i, dist(p)) for i, p in enumerate(pts[1:-1], 1)), key=lambda t: t[1])
    if far > eps:
        return simplify(pts[:i + 1], eps)[:-1] + simplify(pts[i:], eps)
    return [a, b]


def tile_of(x, y):
    return (int(x // TILE), int(y // TILE))


def guides(scene, parent):
    """[(name, first point tile, the node's text)] for the FloorGuides under `parent`."""
    out = []
    for m in re.finditer(r'\[node name="([^"]+)" parent="' + parent + r'"[^\]]*\]\n(.*?)(?=\n\[|\Z)', scene, re.S):
        pm = re.search(r'^points = PackedVector2Array\(([^)]*)\)', m.group(2), re.M)
        if pm and pm.group(1).strip():
            v = [float(t) for t in pm.group(1).split(',')]
            out.append((m.group(1), tile_of(v[0], v[1]), m.group(0)))
    return out


def vec(pts):
    return 'PackedVector2Array(' + ', '.join(f'{int(x)}, {int(y)}' for x, y in pts) + ')'


def write_hints(scene_path, routes_path):
    scene = open(scene_path, encoding='utf-8').read()
    routes = json.load(open(routes_path))
    guide = re.search(r'path="res://Scenes/floor_guide.tscn" id="([^"]+)"', scene)
    if guide is None:
        # the scene doesn't use FloorGuides yet: add the resource line
        guide_id = 'hint_guide'
        scene = re.sub(r'(\[ext_resource[^\n]*\]\n)(?!\[ext_resource)',
                       r'\1[ext_resource type="PackedScene" path="res://Scenes/floor_guide.tscn" id="hint_guide"]\n',
                       scene, count=1)
    else:
        guide_id = guide.group(1)
    if '[node name="Hints" ' not in scene:
        at = scene.index('[node name="Story" ') if '[node name="Story" ' in scene else len(scene)
        scene = scene[:at] + '[node name="Hints" type="Node2D" parent="."]\n\n' + scene[at:]
    taught = {t for _n, t, _txt in guides(scene, 'Tutorial')}
    used = set(re.findall(r'unique_id=(\d+)', scene))
    done = []
    for key, r in sorted(((k, v) for k, v in routes.items() if k != 'halls'), key=lambda kv: int(kv[0])):
        start = tuple(r['start'])
        if start in taught:
            continue
        pts = [tuple(p) for p in r['points']]
        pts = [p for i, p in enumerate(pts) if i == 0 or p != pts[i - 1]]
        line = 'points = ' + vec(simplify(pts))
        old = [g for g in guides(scene, 'Hints') if g[1] == start]
        if old:
            name, _t, text = old[0]
            scene = scene.replace(text, re.sub(r'^points = .*$', line, text, count=1, flags=re.M), 1)
        else:
            name = f'HintRoom{key}'
            while True:
                uid = str(random.randint(10 ** 8, 2 ** 31 - 1))
                if uid not in used:
                    used.add(uid)
                    break
            node = (f'\n[node name="{name}" parent="Hints" unique_id={uid} instance=ExtResource("{guide_id}")]\n'
                    f'{line}\nhint_only = true\n')
            # after the last node under Hints (or right after the Hints node itself)
            last = [m for m in re.finditer(r'\[node name="[^"]+" parent="Hints"[^\]]*\]\n.*?(?=\n\[|\Z)', scene, re.S)]
            if last:
                at = last[-1].end()
            else:
                at = re.search(r'\[node name="Hints" [^\]]*\]\n', scene).end() - 1
            scene = scene[:at] + node + scene[at:]
        done.append(f'{name} (room {key}{", " + str(r.get("upgrades", 0)) + " upgrade" if r.get("upgrades") else ""})')
    open(scene_path, 'w', encoding='utf-8', newline='\n').write(scene)
    print(f'{scene_path}: hints ' + (', '.join(done) if done else 'none to write'))


if __name__ == '__main__':
    write_hints(sys.argv[1], sys.argv[2])
