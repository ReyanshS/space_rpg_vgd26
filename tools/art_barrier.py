# art_barrier.py - draws the BARRIER tile: a cargo crate on a lift, with a
# yellow/black hazard-stripe frame ("this machine moves").
#
# Writes it into two sheets (safe to run again - it just redraws the same spots):
#   Assets/images/tiles/puzzle_tiles.png  frame 12  (what you see in the game)
#   Assets/images/tiles/layout_tiles.png  frame 16  (the icon you paint with,
#                                                    with a small "sinks" arrow)
# The layout palette also needs the tile in layout_tileset.tres (16:0, kind "barrier").
#
# Run from the project folder:   python tools/art_barrier.py
from PIL import Image

T = 'Assets/images/tiles/'
YELLOW = (255, 206, 60, 255)
BLACK = (32, 26, 22, 255)
OUTLINE = (14, 14, 24, 255)
LAMP = (255, 92, 70, 255)


def barrier_tile(crate: Image.Image) -> Image.Image:
    img = Image.new('RGBA', (32, 32), (0, 0, 0, 0))
    px = img.load()
    for y in range(32):
        for x in range(32):
            if x in (0, 31) or y in (0, 31):
                px[x, y] = OUTLINE
            elif x < 4 or x > 27 or y < 4 or y > 27:
                # diagonal stripes, 3 px wide
                px[x, y] = YELLOW if ((x + y) // 3) % 2 == 0 else BLACK
            else:
                px[x, y] = OUTLINE
    # the team's crate, a little smaller, sitting inside the stripes
    inner = crate.crop((3, 3, 29, 29)).resize((22, 22), Image.NEAREST)
    img.alpha_composite(inner, (5, 5))
    # a small red lamp on top = "locked, waiting for power"
    for x in (15, 16):
        px[x, 1] = LAMP
        px[x, 2] = LAMP
    return img


def with_arrow(tile: Image.Image) -> Image.Image:
    """Palette icon: the tile plus a white down-arrow (it sinks into the floor)."""
    img = tile.copy()
    px = img.load()
    shape = ['..###..', '..###..', '..###..', '#######', '.#####.', '..###..', '...#...']
    for dy, row in enumerate(shape):
        for dx, ch in enumerate(row):
            if ch == '#':
                px[12 + dx, 12 + dy] = (255, 255, 255, 255)
    return img


def put_frame(path: str, frame: int, tile: Image.Image) -> None:
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


if __name__ == '__main__':
    puzzle = Image.open(T + 'puzzle_tiles.png').convert('RGBA')
    crate = puzzle.crop((6 * 32, 0, 7 * 32, 32))
    tile = barrier_tile(crate)
    put_frame(T + 'puzzle_tiles.png', 12, tile)
    put_frame(T + 'layout_tiles.png', 16, with_arrow(tile))
