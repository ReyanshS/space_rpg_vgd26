# build_level1_dungeon.py: turns Level 1 into a small dungeon (reference: how the
# map was made; edit Level 1 in Godot after this).
#
# Kept as they were: the team's tutorial rooms 1 to 3 (Engineering Bay, Storage,
# Conduit Hall), and the Generator Room finale with the exit.
# New, where Reactor Access was: the REACTOR HALL, a hall (no puzzle) with
#   west   CABLE STORE (wing B): open. The clamp and a fuse wait behind its cargo,
#          which sinks when you power it.
#   east   COOLANT PUMPS (wing A): open, but you need the clamp to solve it.
#   east   a fuse door to REACTOR ACCESS (wing C): the team's old room 4, moved.
#   south  the MAIN DOOR (MM): all three wings light one lamp each (power links
#          in the scene), then it opens onto the Generator Room.
# Usage (from the project folder):
#   python tools/map_from_scene.py Scenes/level_1.tscn tools/out/level_1_old.txt   (the old map)
#   python tools/maps/build_level1_dungeon.py tools/out/level_1_old.txt tools/maps/level1_dungeon.txt
import sys

src = [list(row) for row in open(sys.argv[1], encoding='utf-8').read().split('\n')]
W, H = 56, 48
g = [[' '] * W for _ in range(H)]
for y, row in enumerate(src[:H]):
    for x, ch in enumerate(row[:W]):
        g[y][x] = ch


def fill(x0, y0, x1, y1, ch):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            g[y][x] = ch


def text(x0, y0, rows):
    for dy, row in enumerate(rows):
        for dx, ch in enumerate(row):
            if ch != ' ':
                g[y0 + dy][x0 + dx] = ch


# 1. the team's Reactor Access room (interior x 17..32, rows 14..27) is saved, then moved
reactor = [[src[y][x] for x in range(17, 33)] for y in range(14, 28)]
# 2. clear its old place and everything new to the east, then build the walls
fill(16, 14, 33, 27, '#')
fill(27, 0, 55, 13, '#')
fill(34, 14, 55, 27, '#')
fill(36, 28, 55, 35, '#')      # (x 34..35 below row 27 belongs to the Generator Room)

# --- REACTOR HALL (a hall: no START, no goal) x 17..32, rows 14..24
fill(17, 14, 32, 24, '.')
for x, y in ((17, 14), (32, 14), (17, 15), (32, 15)):
    g[y][x] = 'C'                       # cargo in the top corners
for x, y in ((20, 18), (29, 18)):
    g[y][x] = 'B'                       # two support pillars holding the hall up
g[24][24] = '.'
g[13][24] = 'D'; g[13][25] = 'D'        # from Conduit Hall (already there)
g[25][23] = 'M'; g[25][24] = 'M'        # the main door, down to the generator
g[15][33] = 'D'; g[16][33] = 'D'        # to the Coolant Pumps
g[21][33] = 'F'; g[22][33] = 'F'        # fuse door to Reactor Access
g[23][16] = 'D'; g[24][16] = 'D'        # to the Cable Store
# a short corridor from the main door to the generator's own door (a hall too)
fill(23, 26, 24, 27, '.')
# (the generator's door at (23..24, 28) is already in the old map)

# --- CABLE STORE (wing B) x 1..15, rows 23..27
fill(0, 22, 16, 28, '#')
g[23][16] = 'D'; g[24][16] = 'D'
text(1, 23, [
    "kf=...........S",
    "===....CCCC....",
    "G......CCCC..B.",
    "....XX.........",
    "...N....*......",
])

# --- COOLANT PUMPS (wing A) x 34..47, rows 12..18
# The goal is behind a crate column. The wire has to bend just below the column's
# end, and only one of the three sockets is in the right place for the clamp.
text(34, 12, [
    ".....XX..C....",
    ".........C.G..",
    ".CCCCCo..C....",
    ".........C....",
    ".S.......C....",
    "..........o...",
    ".*....o.......",
])

# --- corridor from the fuse door, then REACTOR ACCESS (wing C) x 38..53, rows 20..33
fill(34, 21, 36, 22, '.')
g[21][37] = 'D'; g[22][37] = 'D'
for dy, row in enumerate(reactor):
    for dx, ch in enumerate(row):
        g[20 + dy][38 + dx] = ch

out = '\n'.join(''.join(row).rstrip() for row in g).rstrip('\n') + '\n'
open(sys.argv[2], 'w', encoding='utf-8').write(out)
print(out)
