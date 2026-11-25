# art_wall_strip.py: the team's power strip front panel without the lightning
# bolt in the middle.
#
#   Assets/images/tiles/team/wall_strip.png   6 x 3 tiles (the same size as the
#                                             power strip panel in wall.png)
#
# It's the team's own panel (wall.png, columns 0-5, rows 0-2) with only the bolt
# taken out: the two halves of the yellow strip keep their pointed ends and the
# gap between them, which is now plain panel. How it finds the bolt: the yellow
# pixels are grouped into connected shapes; the two strip halves reach the
# panel's sides, the bolt is the shape in the middle that doesn't. Those pixels
# get the panel's colour. Everything else is the team's picture, untouched.
# Run from the project folder:  python3 tools/art_wall_strip.py
from PIL import Image

SRC = 'Assets/images/tiles/team/wall.png'
OUT = 'Assets/images/tiles/team/wall_strip.png'
T = 32
YELLOW = (156, 155, 77)        # the strip and the bolt
PANEL = (93, 97, 105, 255)     # the panel's face


def shapes(px, w, h, colour):
    """Groups the pixels of one colour into connected shapes (4 neighbours)."""
    seen = set()
    out = []
    for y in range(h):
        for x in range(w):
            if (x, y) in seen or px[x, y][:3] != colour:
                continue
            shape = []
            todo = [(x, y)]
            seen.add((x, y))
            while todo:
                cx, cy = todo.pop()
                shape.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and px[nx, ny][:3] == colour:
                        seen.add((nx, ny))
                        todo.append((nx, ny))
            out.append(shape)
    return out


if __name__ == '__main__':
    src = Image.open(SRC).convert('RGBA')
    panel = src.crop((0, 0, 6 * T, 3 * T))
    px = panel.load()
    w, h = panel.size
    removed = 0
    for shape in shapes(px, w, h, YELLOW):
        xs = [p[0] for p in shape]
        if min(xs) > T and max(xs) < w - T:          # doesn't reach the end columns: the bolt
            for p in shape:
                px[p] = PANEL
            removed += len(shape)
    panel.save(OUT)
    print(f'{OUT}: power strip panel without the bolt ({removed} bolt pixels removed)')
