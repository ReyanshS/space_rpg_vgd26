# art_test_start.py: draws the "test start" palette icon.
#
#   Assets/images/tiles/layout_tiles.png  frame 24 (the icon you paint with)
#
# The tile is the floor icon (frame 0) with a dashed green frame and a green
# flag on a pole: "start the playtest here". It's only an editor note: the
# game reads it as floor (level.gd _read_layout), and F6 starts you on it.
# Run from the project folder:  python3 tools/art_test_start.py
from PIL import Image

T = 'Assets/images/tiles/'
FRAME = 24
GREEN = (77, 255, 115, 255)
DARK = (10, 40, 20, 255)
OUTLINE = (5, 9, 33, 255)


def put_frame(path: str, frame: int, tile: Image.Image) -> None:
    """Paste a 32x32 tile into a sheet at `frame`, making the sheet wider if needed."""
    sheet = Image.open(path).convert('RGBA')
    need = (frame + 1) * 32
    if sheet.width < need:
        bigger = Image.new('RGBA', (need, sheet.height), (0, 0, 0, 0))
        bigger.paste(sheet, (0, 0))
        sheet = bigger
    sheet.paste(Image.new('RGBA', (32, 32), (0, 0, 0, 0)), (frame * 32, 0))
    sheet.alpha_composite(tile, (frame * 32, 0))
    sheet.save(path)
    print(f'{path}: frame {frame} drawn ({sheet.width}x{sheet.height})')


def test_start_icon(floor: Image.Image) -> Image.Image:
    tile = floor.copy()
    px = tile.load()
    # a dashed green frame round the edge (2 px on, 2 px off)
    for i in range(32):
        if (i // 2) % 2 == 0:
            for a, b in ((i, 0), (i, 31), (0, i), (31, i)):
                px[a, b] = GREEN
    # the pole: 2 px wide, from y 6 to 26, with a dark outline
    for y in range(5, 28):
        for x in range(10, 14):
            px[x, y] = OUTLINE
    for y in range(6, 27):
        for x in range(11, 13):
            px[x, y] = (220, 225, 235, 255)
    # the flag: a triangle pointing right, outlined
    for y in range(6, 17):
        width = 12 - abs(y - 11) * 2
        for x in range(13, 13 + width + 1):
            px[x, y] = OUTLINE
        for x in range(13, 13 + width):
            if y not in (6, 16):
                px[x, y] = GREEN
    # a small foot plate under the pole
    for x in range(7, 17):
        px[x, 27] = OUTLINE
        px[x, 26] = DARK if x in (7, 16) else GREEN
    return tile


if __name__ == '__main__':
    sheet = Image.open(T + 'layout_tiles.png').convert('RGBA')
    floor = sheet.crop((0, 0, 32, 32))
    put_frame(T + 'layout_tiles.png', FRAME, test_start_icon(floor))
