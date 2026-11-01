# map_to_scene.py - the OPPOSITE of map_from_scene.py: writes a text grid into a level scene.
#
# Lets you sketch a level as text (one character per tile), then puts it on the scene's
# Layout TileMapLayer so you can keep editing it in Godot's editor like any painted map.
# Close the scene in Godot first (or pick "Reload" when Godot asks), or Godot may save
# its old copy over the new map.
#
#   # wall   . floor   S start   G goal   N node   B bend   X red (discharge)
#   x red-off   C crate   D door   P spawn   E exit
#   * power cell   , hull (outside floor)   ~ open space   A airlock pad
#   (space) = nothing
#
# Run from the project folder:   python tools/map_to_scene.py tools/maps/level2.txt Scenes/level_2.tscn
#
# The top-left character of the text file becomes tile (0, 0) in Godot.
import re, struct, sys

TILESET = 'Assets/images/tiles/layout_tileset.tres'
SYMBOL = {'floor': '.', 'wall': '#', 'start': 'S', 'goal': 'G', 'node': 'N', 'bend': 'B',
          'discharge': 'X', 'discharge_off': 'x', 'crate': 'C', 'door': 'D', 'spawn': 'P', 'exit': 'E',
          'cell': '*', 'hull': ',', 'space': '~', 'airlock': 'A'}

if len(sys.argv) < 3:
    sys.exit('usage: python tools/map_to_scene.py <map.txt> <scene.tscn>')
text_path, scene_path = sys.argv[1], sys.argv[2]

# kind -> atlas coords, from the tileset's Custom Data
atlas = {}
for k in re.finditer(r'(\d+):(\d+)/0/custom_data_0 = "(\w*)"', open(TILESET, encoding='utf-8').read()):
    atlas[k.group(3)] = (int(k.group(1)), int(k.group(2)))
char_to_atlas = {}
for kind, ch in SYMBOL.items():
    if kind in atlas:
        char_to_atlas[ch] = atlas[kind]

rows = open(text_path, encoding='utf-8').read().split('\n')
cells = []
for y, row in enumerate(rows):
    for x, ch in enumerate(row):
        if ch == ' ':
            continue
        if ch not in char_to_atlas:
            sys.exit(f'Unknown character {ch!r} at column {x}, row {y}')
        ax, ay = char_to_atlas[ch]
        cells.append((x, y, 0, ax, ay, 0))

# Same layout Godot uses: uint16 format version (0), then 12 bytes per cell, row by row.
data = struct.pack('<H', 0) + b''.join(struct.pack('<hhHHHH', *c) for c in cells)
packed = 'tile_map_data = PackedByteArray(' + ', '.join(str(b) for b in data) + ')'

scene = open(scene_path, encoding='utf-8').read()
start = scene.index('[node name="Layout"')
nxt = scene.find('\n[', start + 1)
section = scene[start:nxt if nxt >= 0 else len(scene)]
if 'tile_map_data = ' in section:
    section = re.sub(r'tile_map_data = PackedByteArray\([^)]*\)', lambda _: packed, section)
else:
    section = section.replace('type="TileMapLayer" parent="."]\n', 'type="TileMapLayer" parent="."]\n' + packed + '\n', 1)
scene = scene[:start] + section + (scene[nxt:] if nxt >= 0 else '')
open(scene_path, 'w', encoding='utf-8', newline='\n').write(scene)
print(f'{len(cells)} tiles written to {scene_path}')
