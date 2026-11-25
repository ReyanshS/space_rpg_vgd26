# art_astronaut_p4.py: turns the team's walk sheet (astronautp4.png) into the
# astronaut's animations (astronaut_p4_frames.tres).
#
#     python tools/art_astronaut_p4.py
#
# astronautp4.png is 6 frames x 5 rows, each frame 32 x 48, feet on the bottom row:
#   row 0 walking down (towards the camera)   row 1 walking down-right
#   row 2 walking right                       row 3 walking up-right
#   row 4 walking up (away from the camera)
# The sheet only faces right, so this also writes astronautp4_flipped.png (the
# whole sheet mirrored) for the left-facing walks.
#
# astronautp4_idle.png (the team's second sheet, 6 x 2 frames of 32 x 48):
#   row 0 idle (6 frames, facing the camera)
#   row 1 shock (frames 0-3: sparks, skeleton, sparks, skeleton), burnt (frames 4-5)
# Only "carry" (standing with the plug in his hands) still comes from the old
# astronaut.png, because neither new sheet has it.
#
# Feet line up: the old frames are 40 tall, the new ones 48. Each new frame gets
# 8 px of empty space below it (AtlasTexture margin), so with the sprite centred
# the bottom row of both sits at the same height (his feet don't jump).
#
# After running it, let Godot import the new PNG (open the editor, or run
# Godot with --headless --import).
import os
from PIL import Image

HERE = 'Assets/images/astronaut/'
SHEET = HERE + 'astronautp4.png'
FLIPPED = HERE + 'astronautp4_flipped.png'
IDLE_SHEET = HERE + 'astronautp4_idle.png'
OUT = HERE + 'astronaut_p4_frames.tres'
FW, FH, COLS = 32, 48, 6
SPEED = 8.0          # frames a second while walking

# animation name -> (row, mirrored?)
WALKS = {
    'walk_down': (0, False),
    'walk_down_right': (1, False),
    'walk_right': (2, False),
    'walk_up_right': (3, False),
    'walk_up': (4, False),
    'walk_down_left': (1, True),
    'walk_left': (2, True),
    'walk_up_left': (3, True),
}
# from the idle sheet: name -> ([(row, column)...], speed, loop)
EXTRA = {
    'idle': ([(0, c) for c in range(6)], 6.0, True),
    'shock': ([(1, c) for c in range(4)], 12.0, True),
    'burnt': ([(1, 4), (1, 5)], 6.0, False),       # chars, then stays on the darkest frame
}
# animations kept from the old sheet: name -> (frame x positions, speed, loop)
OLD = {
    'carry': ([576], 1.0, True),
}


def main() -> None:
    im = Image.open(SHEET).convert('RGBA')
    assert im.size == (FW * COLS, FH * 5), f'{SHEET} should be {FW * COLS} x {FH * 5}, is {im.size}'
    im.transpose(Image.FLIP_LEFT_RIGHT).save(FLIPPED)

    subs = []          # sub_resource blocks
    anims = []         # animation dictionaries

    def atlas(sid: str, tex: str, x: int, y: int, w: int, h: int, pad: int) -> None:
        block = f'[sub_resource type="AtlasTexture" id="{sid}"]\natlas = ExtResource("{tex}")\n'
        block += f'region = Rect2({x}, {y}, {w}, {h})\n'
        if pad:
            block += f'margin = Rect2(0, 0, 0, {pad})\n'
        subs.append(block)

    def anim(name: str, ids: list, speed: float, loop: bool) -> None:
        frames = ',\n'.join('{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % i for i in ids)
        anims.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %s\n}'
                     % (frames, 'true' if loop else 'false', name, speed))

    for name, (xs, speed, loop) in OLD.items():
        ids = []
        for x in xs:
            sid = f'old_{name}_{x}'
            atlas(sid, '1_old', x, 0, 32, 40, 0)
            ids.append(sid)
        anim(name, ids, speed, loop)
    for name, (cells, speed, loop) in EXTRA.items():
        ids = []
        for row, col in cells:
            sid = f'{name}_{row}_{col}'
            atlas(sid, '4_idle', col * FW, row * FH, FW, FH, 8)
            ids.append(sid)
        anim(name, ids, speed, loop)
    for name, (row, mirrored) in WALKS.items():
        ids = []
        for c in range(COLS):
            # in the mirrored sheet the frames of a row run right to left
            x = (COLS - 1 - c) * FW if mirrored else c * FW
            sid = f'{name}_{c}'
            atlas(sid, '3_flip' if mirrored else '2_new', x, row * FH, FW, FH, 8)
            ids.append(sid)
        anim(name, ids, SPEED, True)

    head = ('[gd_resource type="SpriteFrames" format=3]\n\n'
            '[ext_resource type="Texture2D" path="res://Assets/images/astronaut/astronaut.png" id="1_old"]\n'
            '[ext_resource type="Texture2D" path="res://Assets/images/astronaut/astronautp4.png" id="2_new"]\n'
            '[ext_resource type="Texture2D" path="res://Assets/images/astronaut/astronautp4_flipped.png" id="3_flip"]\n'
            '[ext_resource type="Texture2D" path="res://Assets/images/astronaut/astronautp4_idle.png" id="4_idle"]\n\n')
    body = '\n'.join(subs) + '\n[resource]\nanimations = [' + ', '.join(anims) + ']\n'
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write(head + body)
    print(f'wrote {FLIPPED} and {OUT}: {len(OLD)} old + {len(EXTRA)} idle sheet + {len(WALKS)} walk animations')


if __name__ == '__main__':
    os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
    main()
