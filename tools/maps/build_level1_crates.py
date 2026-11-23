# build_level1_crates.py: adds movable crates to Level 1's dungeon (Nov 2026).
# Reference for how the map was made; after this, edit Level 1 in Godot.
#
# Kept as they were: tutorial rooms 1 to 3, Reactor Access, the Generator Room.
# Changed:
#   REACTOR HALL (the hub): no longer empty. The fuse for the amber door lies in
#       a live reactor ring; push a crate onto the red to short a way in.
#       No timer here: it's where you learn crates.
#   CABLE STORE (west wing): rebuilt bigger. A red strip runs right across the
#       room and blocks the wire too. Short out the tile that lines the wire up
#       with the node beyond it. The clamp still waits in the stash.
#   COOLANT PUMPS: a crate to roll out of the clamp's line.
# Usage (from the project folder):
#   python tools/map_from_scene.py Scenes/level_1.tscn tools/out/level_1_dungeon.txt
#   python tools/maps/build_level1_crates.py tools/out/level_1_dungeon.txt tools/maps/level1_crates.txt
#   python tools/map_to_scene.py tools/maps/level1_crates.txt Scenes/level_1.tscn
import sys

src = open(sys.argv[1], encoding='utf-8').read().split('\n')
W = max(len(r) for r in src)
H = max(len(src), 48)
g = [list(r.ljust(W)) for r in src] + [[' '] * W for _ in range(H - len(src))]


def text(x0, y0, rows):
    """Paint rows of characters with their top left at (x0, y0). '?' = leave as it is."""
    for dy, row in enumerate(rows):
        for dx, ch in enumerate(row):
            if ch != '?':
                g[y0 + dy][x0 + dx] = ch


# --- REACTOR HALL: interior x 17..32, y 14..24 (doors round it stay where they are)
text(17, 14, [
    "................",
    ".......c........",
    "................",
    "...B.XXXXXX.B...",
    ".....X....X.....",
    "...c.X..f.X.....",
    ".....X....X.....",
    ".....XXXXXX.....",
    "................",
    "................",
    "................",
])

# --- CABLE STORE: x 0..16, y 22..34 (the stash k = clamp behind the barrier stays)
text(0, 22, [
    "#################",
    "#k.=...........SD",
    "#===..c.....c...D",
    "#...............#",
    "#XXXXXXXXXXXXXXX#",
    "#..............C#",
    "#...B........####",
    "#..........N#????",
    "#.*....C....#????",
    "#......C....#????",
    "#G.....C....#????",
    "#############????",
])

# --- COOLANT PUMPS: a crate on the clamp's line (roll it out of the way first)
g[16][39] = 'c'

open(sys.argv[2], 'w', encoding='utf-8').write('\n'.join(''.join(r).rstrip() for r in g) + '\n')
print('wrote', sys.argv[2])
