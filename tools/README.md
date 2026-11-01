# tools/ — Python helpers (not part of the game)

Godot ignores this folder (that's what the empty `.gdignore` file does). Everything here is run
from the **project folder** (the one with `project.godot`), not from inside `tools/`.

**Setup once:** install Python 3, then `pip install numpy pillow`.
Results go to `tools/out/` (git ignores it — you can always regenerate).

| Tool | What it's for | Command |
| - | - | - |
| `map_from_scene.py` | Reads the map you painted in `level_1.tscn` and writes it as a text grid | `python tools/map_from_scene.py` |
| `solver2.py` | Lists every route that solves each room in time — use after editing a room to catch shortcuts or impossible segments | `python tools/solver2.py tools/out/level1.txt` |
| `render.py` | One image of the whole level with the real tiles | `python tools/render.py tools/out/level1.txt tools/out/map_preview.png` |
| `light_preview.py` | Mock-up of the dark-ship lighting, to try numbers before changing `level.gd` | `python tools/light_preview.py` |
| `sfx.py` | Generates every sound in `Assets/audio` from sine waves + noise (overwrites them!) | `python tools/sfx.py` |
| `astro2.py` | Generates the v2 astronaut sheet `astronaut_v2.png` from text-drawn body parts | `python tools/astro2.py` |

Run `map_from_scene.py` first whenever the map changed — the solver and previews read its output.

Solver output, e.g. `Room start (7, 14): 1 solutions` then `N(3, -> G(7,` means: from the START
at tile (7, 14) there's one route — touch the node at column 3, then the goal at column 7.
More than one line can be the same route with a slightly different fling landing.
The solver's speeds/radii (top of `solver2.py`) must match `player.gd` and `level.gd`.

These were written by Claude (AI) for this project — mention them in the TSA AI-use documentation.
