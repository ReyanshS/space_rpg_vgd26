# build_level2.py - how Level 2's map was first put together (kept for reference).
#
# Each area was sketched as its own small text map and checked with the solver,
# then this script pasted them together at their positions and wrote
# tools/maps/level2.txt. tools/map_to_scene.py turned that into Scenes/level_2.tscn.
#
# From now on, EDIT LEVEL 2 IN GODOT (paint on the Layout layer), not here -
# running this again would overwrite your painted changes once you copy it in.
#   python tools/maps/build_level2.py
#   python tools/map_to_scene.py tools/maps/level2.txt Scenes/level_2.tscn
#
#   # wall  . floor  , hull  ~ open space  S start  G goal  N node  B bend  X sparks
#   C crate/debris  D door (no wall beside it = gangway)  A airlock pad  * power cell
#   P spawn  E exit

BRIDGE = """\
################
################
################
#.......####.G.#
#.N.....####...#
#.......CC*....#
#..............#
#...X.....B....D
#.*.X..........#
#.S.X..........#
#P..X........*.#
################"""

AIRLOCK = """\
####
####
####
####
####
####
...#
.A.D
...#
####
####
####"""

# Hull section A: learn to drift (walk off an edge, float across, land).
SECTION_A = """\
~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~
,,,,,~~~~~,,,,,
,,,,,~~~~~,,,,,
,,S,,~~*~~,,,,,
,,,,,~~~~~,,,,,
~~~~~~~~~~~~*~~
~~~~~~~~~~~~~~~
~~~~~~~~~~,,,,,
~~~~~~~~~~,,G,,
~~~~~~~~~~,,,,,
~~~~~~~~~~~~~~~"""

# Hull section B (solar array): floating debris blocks the wire unless you
# re-anchor it on the node first, so it lines up with the gap (the "lane").
SECTION_B = """\
~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~
~~~~~~,,,,,~~~~~~~~~~
~~~~~~,,N,,~~~~C~~~~~
~~~~~~,,,,,~~*~~~~,,,
~~~~~~~~~~~~~~~C~~,G,
,,,,,,,,~~~~~~~C~~,,,
,S,,,,,,~~~~~~~C~~~~~
,,,,,,,*~~~~~~~C~~~~~
~~~~~~~~~~~~~~~~~~~~~"""

# Hull section C (main coupling): a debris cloud in the middle. Drift up to the
# bend, fling right (left = sparks!), drift across to the node, drift down to
# the coupling. The hatch underneath leads back inside (the exit).
SECTION_C = """\
~~~~~~~~~~~~~~~~~~~~~
~,,,,,,~~~~~~,,,,,~~~
~XX,B,,~~~*~~,,N,,~~~
~,,,,,,~~~~~~,,,,,~~~
~~~~~~~~~CC~~~~~~~~~~
~~~~~~~~CCCC~~~~*~~~~
,,,,,,~~CCCC~~~,,,,,~
,,,,S,~~CCCC~~~,,,G,~
,,,,,,~~CCCC~~~,,,,*~
~~~~~~~~~~~~~~~##D##~
~~~~~~~~~~~~~~~#EEE#~
               #####"""

# (text, x, y) - where each piece's top-left corner goes, in tiles
PIECES = [
    (BRIDGE, 0, 0),
    (AIRLOCK, 16, 0),
    (SECTION_A, 20, 2),
    ("D", 35, 12),          # gangway A -> B
    (SECTION_B, 36, 6),
    ("D", 57, 11),          # gangway B -> C
    (SECTION_C, 58, 4),
]


def main():
    grid = {}
    for text, ox, oy in PIECES:
        for y, row in enumerate(text.split('\n')):
            for x, ch in enumerate(row):
                if ch != ' ':
                    grid[(ox + x, oy + y)] = ch
    w = max(x for x, _ in grid) + 1
    h = max(y for _, y in grid) + 1
    rows = [''.join(grid.get((x, y), ' ') for x in range(w)).rstrip() for y in range(h)]
    open('tools/maps/level2.txt', 'w', encoding='utf-8', newline='\n').write('\n'.join(rows))
    print('\n'.join(rows))


if __name__ == '__main__':
    main()
