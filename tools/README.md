# tools/ — Python helpers (not part of the game)

Godot ignores this folder (that's what the empty `.gdignore` file does). Everything here is run
from the **project folder** (the one with `project.godot`), not from inside `tools/`.

**Setup once:** install Python 3, then `pip install numpy pillow`.
Results go to `tools/out/` (git ignores it — you can always regenerate).

| Tool | What it's for | Command |
| - | - | - |
| `map_from_scene.py` | Reads the map you painted in a level scene and writes it as a text grid | `python tools/map_from_scene.py Scenes/level_2.tscn tools/out/level2.txt` (no arguments = Level 1) |
| `map_to_scene.py` | The opposite: puts a text grid onto a scene's Layout layer (close the scene in Godot first) | `python tools/map_to_scene.py tools/maps/level2.txt Scenes/level_2.tscn` |
| `solver2.py` | Lists every route that solves each room in time, the tightest segment's spare time, and whether each power cell can be charged — use after editing a room | `python tools/solver2.py tools/out/level1.txt` |
| `render.py` | One image of the whole level with the real tiles | `python tools/render.py tools/out/level1.txt tools/out/map_preview.png` |
| `light_preview.py` | Mock-up of the dark-ship lighting, to try numbers before changing `level.gd` | `python tools/light_preview.py` |
| `sfx.py` | Generates every sound effect in `Assets/audio` from sine waves + noise (overwrites them!). The music is the team's own `music_*.ogg`, not made here | `python tools/sfx.py` |
| `astro2.py` | Generates the v2 astronaut sheet `astronaut_v2.png` from text-drawn body parts | `python tools/astro2.py` |
| `art_space.py` | Draws the Level 2 art: hull plates, gangway + airlock pad pictures, the 4 new palette icons, planet and nebula | `python tools/art_space.py` |
| `maps/build_level2.py` | How Level 2's first map was pasted together from separately-solved pieces (reference only — edit Level 2 in Godot now) | `python tools/maps/build_level2.py` |
| `art_barrier.py` | Draws the BARRIER tile (crate on a lift, hazard stripes) into `puzzle_tiles.png` frame 12 and its palette icon into `layout_tiles.png` frame 16 | `python tools/art_barrier.py` |
| `art_ui.py` | Draws the UI frames `Assets/ui/frame_screen.png` (riveted bezel + green screen) and `frame_plate.png` (riveted plate) | `python tools/art_ui.py` |
| `art_core.py` | Draws the CORE tile (Level 3's round socket) into `puzzle_tiles.png` frame 13 and its palette icon into `layout_tiles.png` frame 17 | `python tools/art_core.py` |
| `sfx_pip.py` | Generates only the Level 3 boss sounds (`glitch`, `pulse`, `warn`, `boot`) - the other sounds stay as they are | `python tools/sfx_pip.py` |
| `maps/build_level3.py` | How Level 3's first map was drafted as text (reference only - edit Level 3 in Godot now) | `python tools/maps/build_level3.py` |
| `logo_import.py` | Turns a big pixel-art logo picture with a fake (painted-on) checkerboard background into a crisp, transparent, game-sized `Assets/images/ui/logo.png` | `python tools/logo_import.py <picture> [pixel size]` |

Run `map_from_scene.py` first whenever the map changed — the solver and previews read its output.

**Map characters:** `#` wall, `.` floor, `S` start, `G` goal, `N` node, `B` bend, `X` red tile,
`x` blinking grate, `C` crate (or floating debris), `D` door (gangway when no wall is beside it),
`P` spawn, `E` exit, `*` power cell, `,` hull, `~` open space, `A` airlock pad, `=` barrier,
`@` core (Level 3), space = nothing.

**Core rooms (`@`):** there's no goal. A route is finished when the wire (START, the pads it's
wrapped round, then his hands) has gone a full turn round the core. Those routes end in
`loop@(x,y)` = the pixel he has to walk to (with the wire) to close the loop, and the line also
says `s in all` = the whole route's time, fastest first. Compare that with PIP's
`shutdown_seconds` in `level_3.tscn` (a real player is slower than the solver). To keep it fast,
the solver skips pads that would take the loop backwards. Check one stage on its own with
`python tools/solver2.py tools/out/level3.txt 3` (stage numbers after the file).

The solver checks the stages in walking order, the same way the game plays them: touching `=`
tiles are one group, and when it checks a stage, every group next to an earlier stage counts as
open floor (it has sunk by then), and the nodes and bends of earlier stages joined to it by
barriers can be used too. So shortcuts through opened barriers show up. It does NOT model the
timing of blinking grates (`x` counts as floor) - test those in the game - and it never counts the
+2 s a power cell gives, so routes it finds work even without the cells. Pads count as touched
from the feet or 10 px higher, like the game (`BODY_UP`).

Solver output, e.g. `S(7,14) -> N(3,10) -> G(7,6)   (tightest segment: 3.38 s spare)` means: from the
START at tile (7, 14), touch the node at (3, 10), then the goal at (7, 6); on the hardest stretch
you have 3.38 s to spare. `B(19,9)[L]` = touch the bend and pick its first arrow; `fling` = the bend
throws you onto the next pad; `fling->(x,y)` = the fling stops at that pixel. Drifting across open
space is part of the walking between pads. Then one line per power cell: `collectible` or
`NOT collectible on any route`. The solver's speeds/radii (top of `solver2.py`) must match
`player.gd` and `level.gd`.

These were written by Claude (AI) for this project — mention them in the TSA AI-use documentation.
