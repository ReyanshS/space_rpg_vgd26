# map_from_scene.py - turns the map you PAINTED in Godot into a text grid.
#
# Reads the Layout TileMapLayer inside Scenes/level_1.tscn (its `tile_map_data`),
# looks up each tile's "kind" in layout_tileset.tres, and writes one character
# per tile to tools/out/level1.txt. The solver and preview tools read that file.
#
#   # wall   . floor   S start   G goal   N node   B bend   X red (discharge)
#   x red-off   C crate   D door   P spawn   E exit
#   * power cell   , hull (outside floor)   ~ open space   A airlock pad   (space) = nothing
#
# Run from the project folder:   python tools/map_from_scene.py [scene.tscn] [out.txt]
#   e.g. python tools/map_from_scene.py Scenes/level_2.tscn tools/out/level2.txt
# (tools/map_to_scene.py does the opposite: text grid -> scene.)
#
# tile_map_data format (Godot 4): 2 bytes = format version, then 12 bytes per
# painted cell: int16 x, int16 y, uint16 source id, uint16 atlas x, uint16 atlas y,
# uint16 alternative tile.
import os, re, struct, sys

SCENE = sys.argv[1] if len(sys.argv) > 1 else 'Scenes/level_1.tscn'
TILESET = 'Assets/images/tiles/layout_tileset.tres'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'tools/out/level1.txt'
SYMBOL = {'floor': '.', 'wall': '#', 'start': 'S', 'goal': 'G', 'node': 'N', 'bend': 'B',
          'discharge': 'X', 'discharge_off': 'x', 'crate': 'C', 'door': 'D', 'spawn': 'P', 'exit': 'E',
          'cell': '*', 'hull': ',', 'space': '~', 'airlock': 'A'}

scene = open(SCENE, encoding='utf-8').read()
layout = scene[scene.index('[node name="Layout"'):]
m = re.search(r'tile_map_data = PackedByteArray\(([^)]*)\)', layout)
if m is None:
    sys.exit('No tile_map_data found on the Layout node - is the map painted?')
raw = m.group(1).strip()
if raw.startswith('"'):                      # newer Godot can store it as base64
    import base64
    data = base64.b64decode(raw.strip('"'))
else:
    data = bytes(int(v) for v in raw.split(','))

# atlas coords -> kind, from the tileset's Custom Data
kinds = {}
for k in re.finditer(r'(\d+):(\d+)/0/custom_data_0 = "(\w*)"', open(TILESET, encoding='utf-8').read()):
    kinds[(int(k.group(1)), int(k.group(2)))] = k.group(3)

cells = {}
for i in range(2, len(data) - 11, 12):
    x, y, src, ax, ay, alt = struct.unpack('<hhHHHH', data[i:i + 12])
    cells[(x, y)] = SYMBOL.get(kinds.get((ax, ay), ''), '?')

xs = [c[0] for c in cells]
ys = [c[1] for c in cells]
rows = []
for y in range(min(ys), max(ys) + 1):
    rows.append(''.join(cells.get((x, y), ' ') for x in range(min(xs), max(xs) + 1)).rstrip())

os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, 'w').write('\n'.join(rows))
print('\n'.join(rows))
print(f'\n{len(cells)} tiles -> {OUT}  (top-left tile is ({min(xs)}, {min(ys)}) in Godot)')
