# use_team_pads.py: repaints a level's START, GOAL and NODE pads with the team's
# animated tiles (start_anim / goal_anim / node_anim in the Layout tileset).
#
#     python3 tools/use_team_pads.py Levels/level_1.tscn
#
# Only the picture changes: each animated tile has the same kind ("start",
# "goal", "node") as the plain palette pad, so the rules are exactly the same.
# Close Godot first (it would save its old copy of the level over this one).
import sys
sys.path.insert(0, 'tools')
from retile_walls import tileset_kinds, read_layout, write_layout, TILESET

ANIMATED = {'start': 5, 'goal': 6, 'node': 7}     # kind -> tileset source of its animation

if __name__ == '__main__':
    path = sys.argv[1]
    scene = open(path, encoding='utf-8').read()
    kinds_of = tileset_kinds(TILESET)
    cells, header, m = read_layout(scene)
    count = {k: 0 for k in ANIMATED}
    for c, v in cells.items():
        kind = kinds_of.get(tuple(v[:3]), '')
        if kind in ANIMATED and v[0] != ANIMATED[kind]:
            cells[c] = [ANIMATED[kind], 0, 0, 0]          # the animation is tile (0, 0) of its sheet
            count[kind] += 1
    print(f'{path}: ' + ', '.join(f'{n} {k}' for k, n in count.items()) + ' pads now animated')
    open(path, 'w', encoding='utf-8', newline='\n').write(write_layout(scene, cells, header, m))
