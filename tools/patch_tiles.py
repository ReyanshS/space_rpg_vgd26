# patch_tiles.py: changes a few tiles of a level's Layout without touching the rest.
# (map_to_scene.py rewrites the whole map from text, which would lose the team's
# painted art tiles. This only edits the cells you list.)
#
#   python tools/patch_tiles.py Levels/level_1.tscn "move 13,20 11,20" "set 5,12 box" "floor 25,4"
#
#   move A B     the tile at A goes to B (its own art and all); A becomes plain floor
#   set C KIND   C becomes the plain palette tile of KIND (floor, start, goal, node, pole,
#                discharge, crate, box, cell, ...: the kinds in layout_tileset.tres)
#   floor C      C becomes plain floor
# Close the level in Godot first (or pick Reload when it asks).
import base64, re, struct, sys

TILESET = 'Assets/images/tiles/layout_tileset.tres'
scene_path = sys.argv[1]
ops = sys.argv[2:]

# palette (source 0) atlas coords of each kind
pal = {}
ts = open(TILESET, encoding='utf-8').read()
start = ts.index('id="TileSetAtlasSource_layout"')
end = ts.index('[sub_resource', start + 10) if '[sub_resource' in ts[start + 10:] else len(ts)
for m in re.finditer(r'(\d+):(\d+)/0/custom_data_0 = "(\w+)"', ts[start:end]):
    pal.setdefault(m.group(3), (int(m.group(1)), int(m.group(2))))

scene = open(scene_path, encoding='utf-8').read()
i = scene.index('[node name="Layout"')
m = re.compile(r'tile_map_data = PackedByteArray\("([^"]*)"\)').search(scene, i)
data = base64.b64decode(m.group(1))
version = struct.unpack_from('<H', data, 0)[0]
cells = {}
order = []
for k in range((len(data) - 2) // 12):
    x, y, src, ax, ay, alt = struct.unpack_from('<hhHHHH', data, 2 + k * 12)
    cells[(x, y)] = (src, ax, ay, alt)
    order.append((x, y))


def pos(t):
    a, b = t.split(',')
    return (int(a), int(b))


def put(c, v):
    if c not in cells:
        order.append(c)
    cells[c] = v


floor = (0,) + pal['floor'] + (0,)
for op in ops:
    w = op.split()
    if w[0] == 'move':
        a, b = pos(w[1]), pos(w[2])
        put(b, cells[a])
        put(a, floor)
    elif w[0] == 'set':
        put(pos(w[1]), (0,) + pal[w[2]] + (0,))
    elif w[0] == 'floor':
        put(pos(w[1]), floor)
    else:
        sys.exit('unknown op: ' + op)
    print('  ' + op)

out = struct.pack('<H', version) + b''.join(struct.pack('<hhHHHH', c[0], c[1], *cells[c]) for c in order)
scene = scene[:m.start(1)] + base64.b64encode(out).decode('ascii') + scene[m.end(1):]
open(scene_path, 'w', encoding='utf-8', newline='\n').write(scene)
print('patched', scene_path)
