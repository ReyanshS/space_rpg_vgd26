# art_ui.py - draws the two UI frames: ship hardware on the outside, an old
# green computer screen on the inside.
#
#   Assets/ui/frame_screen.png  riveted metal bezel around a dark green screen with
#                               scanlines (PIP's speech, objective, results, pause)
#   Assets/ui/frame_plate.png   plain riveted metal plate (meters, popups)
#
# Both are 20x20 "9-slice" pictures: Godot keeps the 6 px border (corners with the
# rivets) as it is and repeats the middle to fill any size. That's what the
# texture_margin_* = 6 settings in hud.tscn mean.
#
# Run from the project folder:   python tools/art_ui.py
from PIL import Image

S = 20
OUTLINE = (10, 11, 16)
HIGHLIGHT = (138, 147, 166)
SHADOW = (36, 40, 50)
METAL = (74, 81, 98)
METAL_SPECK = (66, 72, 88)
RECESS_DARK = (20, 22, 28)
RECESS_LIGHT = (98, 106, 124)
SCREEN_EDGE = (6, 10, 8)
SCAN_A = (13, 27, 19)
SCAN_B = (9, 19, 14)
RIVET = (180, 190, 208)
RIVET_SHADOW = (28, 30, 38)


def edge(x, y):
    """How far (in pixels) this pixel is from the outside of the frame."""
    return min(x, y, S - 1 - x, S - 1 - y)


def bevel(x, y, d):
    # top/left edges catch the light, bottom/right edges are in shadow
    near_top_left = (x == d or y == d) and not (x == S - 1 - d or y == S - 1 - d)
    return near_top_left


def frame(screen: bool) -> Image.Image:
    img = Image.new('RGBA', (S, S))
    px = img.load()
    for y in range(S):
        for x in range(S):
            d = edge(x, y)
            if d == 0:
                c = OUTLINE
            elif d == 1:
                c = HIGHLIGHT if bevel(x, y, 1) else SHADOW
            elif d <= 3 or not screen:
                c = METAL_SPECK if (x * 7 + y * 3) % 11 == 0 else METAL
                if not screen and d >= 4:
                    c = METAL if y % 4 else METAL_SPECK          # brushed plate
            elif d == 4:
                c = RECESS_DARK if bevel(x, y, 4) else RECESS_LIGHT   # the screen sits IN the metal
            elif d == 5:
                c = SCREEN_EDGE
            else:
                c = SCAN_A if y % 2 == 0 else SCAN_B                  # scanlines
            px[x, y] = c + (255,)
    for rx, ry in ((2, 2), (S - 4, 2), (2, S - 4), (S - 4, S - 4)):
        px[rx, ry] = RIVET + (255,)
        px[rx + 1, ry] = RIVET + (255,)
        px[rx, ry + 1] = RIVET + (255,)
        px[rx + 1, ry + 1] = RIVET_SHADOW + (255,)
    return img


if __name__ == '__main__':
    frame(True).save('Assets/ui/frame_screen.png')
    frame(False).save('Assets/ui/frame_plate.png')
    print('Assets/ui/frame_screen.png and frame_plate.png drawn (20x20, 9-slice margin 6)')
