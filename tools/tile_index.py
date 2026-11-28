# tile_index.py: builds docs/tile_index.html, a picture index of the Layout
# palette (Assets/images/tiles/layout_tiles.png: the plain tiles that carry the
# game's rules) and what each one does.
#
#     python3 tools/tile_index.py
#
# The kinds are read from the tileset, so a tile added to the palette shows up
# here (add a line to WHAT for its description). Run it again after the palette
# changes.
import base64, io, html
from PIL import Image

T = 32
OUT = 'docs/tile_index.html'


def png(img, scale):
    img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    buf = io.BytesIO()
    img.save(buf, 'PNG')
    return 'data:image/png;base64,' + base64.b64encode(buf.getvalue()).decode()


# kind -> (map letter, what it does). The letter is what tools/map_from_scene.py
# writes for it (the solver reads those text maps).
WHAT = {
    'floor': ('.', 'Plain floor. You walk on it and the wire crosses it.'),
    'wall': ('#', 'Wall. Solid for you and the wire. Walls, doors and barriers split the map into rooms. '
                  'Drawn as the wall piece that fits the floor round it (or paint the team\'s wall sheets).'),
    'start': ('S', 'START pad. Stand on it and press E to grab the wire: the timer starts. One per room.'),
    'goal': ('G', 'GOAL pad. Grey until its room has power (PIP calls it the grey pad). Touch it with the wire to power the room: it lights up blue, doors open, barriers sink. Hold E on a lit one to cut the power and redo the room.'),
    'node': ('N', 'Node. Press E on it to connect the wire: it bends there, and the timer fills up and stays full for as long as you stand on it.'),
    'pole': ('B', 'Pole (a steel pillar). Solid for you, not for the wire: walk round it and the wire wraps round it, '
                  'walk back and it unwraps. Gives no time.'),
    'discharge': ('X', 'Red floor. Stepping on it shocks you and resets the room. The wire can\'t cross it. '
                       'A pushed crate can short it out.'),
    'blinker': ('x', 'Blinking grate. Zaps you while it\'s lit; it lights up in a wave. The wire is fine over it.'),
    'crate': ('C', 'Fixed cargo. Blocks you and the wire. With no floor round it, it\'s floating debris in space.'),
    'door': ('D', 'Door. Opens when the room before it has power. With no wall beside it, it\'s a gangway '
                  '(a catwalk out in space that slides out).'),
    'spawn': ('P', 'Where the player starts the level. One per level. Plain floor otherwise.'),
    'exit': ('E', 'Exit. Walking onto it finishes the level (results, then the next level).'),
    'cell': ('*', 'Power cell (battery). Touch it while carrying the wire for extra time. '
                  'Collected cells count for stars and buy upgrades.'),
    'hull': (',', 'Hull: floor outside the ship (spacewalks). Rooms with hull are outside rooms with an oxygen meter.'),
    'space': ('~', 'Open space. You can\'t stand on it but can drift across to more hull; the wire stretches over it.'),
    'airlock': ('A', 'Airlock pad. Step on it to cycle the airlock: the door behind closes and the outer door opens.'),
    'barrier': ('=', 'Barrier: cargo on a lift. Sinks into the floor when a room next to it is powered. '
                     'Touching barriers sink together; rooms joined by barriers are one multistage area.'),
    'core': ('@', 'Core (Level 3). Power the room by looping the wire all the way round it. Solid.'),
    'fuse': ('f', 'Fuse pickup. Walk over it to take it. Fuse doors take one each.'),
    'fuse_door': ('F', 'Fuse door. Opens if you walk into it carrying a fuse.'),
    'main_door': ('M', 'Lamp door (red). One lamp per power link pointing at it; opens when every lamp is lit.'),
    'socket': ('o', 'Clamp socket. Press E next to it to put down or take the cable clamp; '
                    'in a socket the clamp works like a pole.'),
    'clamp': ('k', 'Cable clamp pickup (one per level). Walk over it to take it.'),
    'box': ('c', 'Movable crate (striped). Walk into it and it rolls one tile. Blocks you and the wire. '
                 'Rolled onto red floor, it shorts that tile out. R puts it back.'),
    'test_start': ('(none)', 'Editor only: press F6 to start here with every room before it powered. Plain floor in the real game.'),
}


def build():
    import sys
    sys.path.insert(0, 'tools')
    from retile_walls import tileset_kinds, TILESET
    kinds = sorted((ax, k) for (src, ax, ay), k in tileset_kinds(TILESET).items() if src == 0)
    palette = Image.open('Assets/images/tiles/layout_tiles.png').convert('RGBA')
    cards = []
    for x, kind in kinds:
        letter, text = WHAT.get(kind, ('?', 'No description yet: add it to WHAT in tools/tile_index.py.'))
        img = png(palette.crop((x * T, 0, x * T + T, T)), 3)
        cards.append(f'<figure class="card"><div class="pics"><img class="tile" src="{img}" alt=""></div>'
                     f'<figcaption><span class="coord">({x}, 0) &middot; {html.escape(kind)} &middot; map {html.escape(letter)}</span>'
                     f'{html.escape(text)}</figcaption></figure>')
    body = f'<section><div class="grid">{"".join(cards)}</div></section>'
    open(OUT, 'w').write(TEMPLATE.replace('{{BODY}}', body))
    print(f'{OUT}: {len(kinds)} palette tiles')


TEMPLATE = '''<title>Star Circuit Tile Index</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@500;700&family=Inter:wght@400;600&family=JetBrains+Mono:wght@500&display=swap">
<style>
/* layout: a reference sheet, sections of tile cards on a dark-steel ground like the game's walls */
:root {
  --bg: #eef0f4; --panel: #ffffff; --fg: #1c1f26; --muted: #5d6472; --line: #d5d9e1;
  --accent: #b9860f; --tilebg: #2a2d34;
  --display: "Space Grotesk", "Helvetica Neue", Arial, sans-serif;
  --body: "Inter", "Helvetica Neue", Arial, sans-serif;
  --mono: "JetBrains Mono", ui-monospace, Menlo, monospace;
}
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --bg: #15171c; --panel: #1e2128; --fg: #e8eaef; --muted: #9aa1ae; --line: #2e323b; --accent: #e8b640; --tilebg: #0f1014; color-scheme: dark } }
:root[data-theme="dark"] { --bg: #15171c; --panel: #1e2128; --fg: #e8eaef; --muted: #9aa1ae; --line: #2e323b; --accent: #e8b640; --tilebg: #0f1014; color-scheme: dark }
body { background: var(--bg); color: var(--fg); font-family: var(--body); line-height: 1.5; }
.wrap { max-width: 1180px; margin: 0 auto; padding-block: 32px 64px; padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
header h1 { font-family: var(--display); font-size: 2rem; margin: 0 0 6px; text-wrap: balance; }
header p { color: var(--muted); max-width: 68ch; margin: 0 0 12px; }
.legend { display: flex; flex-wrap: wrap; gap: 12px; font-size: 0.85rem; color: var(--muted); }
.key { display: inline-flex; align-items: center; gap: 6px; }
.key i { width: 14px; height: 14px; display: inline-block; border: 1px solid var(--line); }
section { margin-top: 40px; }
h2 { font-family: var(--display); font-size: 1.3rem; margin: 0 0 4px; display: flex; align-items: baseline; gap: 10px; }
.count { font-family: var(--mono); font-size: 0.8rem; color: var(--accent); }
.intro { color: var(--muted); max-width: 72ch; margin: 0 0 16px; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(230px, 1fr)); gap: 12px; }
.card { margin: 0; background: var(--panel); border: 1px solid var(--line); border-radius: 6px; padding: 10px; display: flex; gap: 10px; align-items: flex-start; min-width: 0; }
.pics { display: flex; flex-direction: column; gap: 6px; align-items: center; flex: none; }
.tile { width: 96px; height: 96px; image-rendering: pixelated; background: var(--tilebg); }
.diagram { width: 44px; height: 44px; image-rendering: pixelated; }
figcaption { font-size: 0.85rem; min-width: 0; }
.coord { display: block; font-family: var(--mono); color: var(--accent); font-size: 0.8rem; margin-bottom: 2px; font-variant-numeric: tabular-nums; }
.wide { overflow-x: auto; background: var(--panel); border: 1px solid var(--line); border-radius: 6px; padding: 12px; }
.wide img { image-rendering: pixelated; display: block; max-width: none; }
</style>
<div class="wrap">
<header>
<h1>Star Circuit tile index</h1>
<p>The Layout palette (<b>layout_tiles</b>, the first sheet in the TileMap panel's list): the plain tiles that carry the game's rules. Each card shows the tile's spot in the palette (column, row), its kind (the rule it gives) and the letter the map tools and solver use for it. The team's art sheets work the same way: each of their tiles has one of these kinds.</p>
</header>
{{BODY}}
</div>
'''

if __name__ == '__main__':
    build()
