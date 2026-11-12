# build_level3.py - how Level 3's first map was drafted as text (reference only:
# once it's in the scene, edit Level 3 in Godot like any other level).
#
# Level 3 = THE CORE. Room 1 teaches the new rule on a harmless pylon: wrap the
# live wire ALL the way round the core (@). Then PIP malfunctions and hides in
# his core chamber: three stages joined by barriers, one core each. Same rule,
# but now PIP's shutdown meter is racing you (rogue_pip.gd).
#
# Run from the project folder:  python tools/maps/build_level3.py
# then:  python tools/solver2.py tools/maps/level3.txt
#        python tools/map_to_scene.py tools/maps/level3.txt Scenes/level_3.tscn
W, H = 44, 24
g = [[' '] * W for _ in range(H)]


def fill(x0, y0, x1, y1, ch):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            g[y][x] = ch


def put(x, y, ch):
    g[y][x] = ch


# --- walls first, then carve the rooms out of them
fill(0, 0, 42, 12, '#')
fill(28, 12, 42, 20, '#')
fill(34, 20, 37, 23, '#')

# --- Room 1: CORE ACCESS (the sync pylon - a core with no PIP in it)
fill(1, 3, 13, 9, '.')
put(2, 6, 'P')                   # you arrive here
put(4, 6, 'S')
put(8, 6, '@')                   # the pylon
put(8, 4, 'N'); put(11, 6, 'N'); put(8, 8, 'N')
put(12, 8, '*')
put(1, 3, 'C'); put(2, 3, 'C'); put(1, 9, 'C')
put(13, 3, 'C'); put(13, 9, 'C')
put(14, 6, 'D')                  # into PIP's core chamber

# --- Stage A: PIP's first socket, an open ring of nodes
fill(15, 3, 27, 11, '.')
put(16, 10, 'S')
put(21, 7, '@')
put(18, 4, 'N'); put(24, 4, 'N'); put(24, 10, 'N'); put(18, 10, 'N')
put(21, 3, '*')
put(17, 8, 'C'); put(18, 8, 'C')           # cargo: no straight line from START to the top-left node
put(26, 3, 'C'); put(27, 3, 'C'); put(27, 4, 'C')
put(15, 11, 'C'); put(27, 11, 'C')
fill(28, 5, 28, 9, '=')                     # sinks when stage A gets power

# --- Stage B: PIP hides behind a cargo stack (the loop has to go round both)
fill(29, 3, 41, 11, '.')
put(30, 7, 'S')
put(34, 6, '@')
fill(35, 5, 36, 7, 'C')
put(32, 4, 'N'); put(32, 9, 'N')
put(39, 4, 'B'); put(39, 9, 'N')
put(41, 3, '*')
put(29, 3, 'C'); put(29, 11, 'C'); put(41, 11, 'C')
fill(33, 12, 37, 12, '=')                   # sinks when stage B gets power

# --- Stage C: the floor round his last socket is live (blinking grates)
fill(29, 13, 41, 19, '.')
put(30, 15, 'S')
put(35, 16, '@')
fill(33, 13, 33, 19, 'x')                   # a lane of blinking grates on each side
fill(37, 13, 37, 19, 'x')
put(35, 14, 'N'); put(35, 18, 'N')
put(31, 18, 'N'); put(40, 14, 'N'); put(40, 18, 'N')
put(39, 16, '*')
put(29, 19, 'C'); put(41, 13, 'C')
put(35, 20, 'D'); put(36, 20, 'D')          # the way out
fill(35, 21, 36, 22, 'E')

text = '\n'.join(''.join(row).rstrip() for row in g).rstrip('\n')
open('tools/maps/level3.txt', 'w', encoding='utf-8').write(text + '\n')
print(text)
