# TSA Video Game Design 2027 — project notes for Claude

Godot 4.7 top-down puzzle game for the TSA Video Game Design event (2026-27; AI use is allowed but
must be documented). The player is an astronaut restoring power to a dead spaceship by carrying a
live wire from pad to pad. `Scenes/level_1.tscn` is the main scene: a 4-room tutorial level.

## How to work with this team
- The developers are students learning GDScript. They want to UNDERSTAND every change, not just get
  working code: explain what you changed, why, and the bigger concept behind it (signals, state
  machines, resources...). End with 1-3 short "check yourself" tasks they can do on their own.
- Don't take over their problem-solving: when they ask how to do something, guide first.
- Match the existing code style: tabs, typed GDScript, a header comment block in every script
  explaining how it fits in, and plain-English comments on anything non-obvious.
- **Godot overwrites files edited outside it.** If Godot has a script or scene open and you change
  it on disk, Godot can save its old copy over yours (on Play / save). Ask them to close Godot before
  editing, or to pick **Reload** (never Resave) when Godot reports files changed on disk.
- Keep a note of anything AI-generated for their TSA documentation (see bottom).

## TSA requirements (check work against these)
- **The official rubric is in the TSA event guide** (members only — get it from the advisor). Keep
  it at `docs/TSA_event_guide.pdf` and read it before judging whether a feature is "done".
- 2026-27 theme, per the Washington TSA event page: *"Create a deep space-themed RPG where the
  primary method of progression is puzzle-solving rather than combat."* Core RPG elements are
  required, but no traditional combat. **Not built yet:** RPG elements (story/dialogue, character
  or ship progression, items...) and Levels 2-3.
- Washington TSA page, January qualifying: at least 2 of the 3 levels, the first one well
  developed; judges must be able to finish Level 1 and get into Level 2. Scoring: game design
  70 pts; video demonstration & documentation portfolio 30 pts (game directions and controls,
  work log, storyboard). Submit a portfolio PDF + a link to the game; if judges can't open the
  link the team is disqualified. Confirm details in the team's own state guide.
- Judges play from a link, so the game needs a **web export**. Web builds run on WebGL 2 (Godot's
  Compatibility renderer); this project is set to Forward+, so test a web export early and check
  that the lighting still looks right.

## Display
480x270 viewport scaled 3x, nearest filtering, 32x32 tiles. UI font: m6x11 (`Assets/fonts`) via
`Assets/ui/theme.tres` at size 16 — only use multiples of 16 or the pixel font blurs.

## Game rules (level.gd enforces them)
- START pad: stand on it, press **E/Space** to grab the wire. The 5 s timer (`wire_time`) starts.
- Free movement while carrying. The wire is a taut straight line from the LAST pad touched to the
  player's hands; it can't pass through walls, crates, doors or live red tiles, so steps that would
  make it are refused (`wire_reaches()`).
- NODE (orange): wraps the wire, refills the timer, pauses it while you stand on it. Touch radius 22 px.
- BEND (purple): stops you, shows two arrows, you press one and get flung 90 deg
  (`bend_pauses_timer`). The fling stops at a wall or node.
- GOAL (blue): powers the room — lights on, conduit fills, the door opens.
- Red DISCHARGE tile: stepping on it (wire or not) = shock, room restarts. Timer at 0 = wire snaps,
  room restarts. **R** restarts manually.

## Architecture (data -> logic -> visuals)
- **The map is painted**, not coded: the `Layout` TileMapLayer in level_1.tscn uses
  `Assets/images/tiles/layout_tileset.tres`; each tile has Custom Data `kind` (floor, wall, start,
  goal, node, bend, discharge, discharge_off, crate, door, spawn, exit). Rooms are found by flood
  fill (walls/doors separate them) and numbered in walking order from the spawn. Each room needs
  exactly one START. Doors open when an adjacent room is solved.
- `Scripts/level.gd` (`WireLevel`, `@tool`): reads the Layout, builds the pretty Ground/Walls/Props
  layers live in the editor, then at runtime runs all the rules, the camera, lighting and audio.
  It announces events with signals: `room_entered`, `room_solved`, `room_restarted`,
  `wire_grabbed`, `pad_touched(kind, index)`, `level_completed`.
- `Scripts/player.gd` (`Astronaut`): state machine FREE / WIRED / CHOOSING / FLUNG / LOCKED. Only
  movement + animation; asks the level for rules (`player_moved()`, `wire_reaches()`, ...).
- `Scripts/puzzle_tile.gd`: runtime visuals for pads/doors (glow, sparks, arrows, light).
- `Scripts/wire.gd`: carried wire + floor conduits (Line2D + `Shaders/wire_current.gdshader`).
- `Scripts/hud.gd` + `Scenes/hud.tscn`: tutorial objective box + arrow, toasts, timer bar, fades.
- **Tutorial** (rooms 1-2): `Scripts/tutorial.gd` on the `Tutorial` node runs its
  `TutorialStep` children (`Scripts/tutorial_step.gd`, Marker2D) in tree order. Each step has
  `text`, `advance_when` (GRAB_WIRE, TOUCH_NODE, TOUCH_BEND, SOLVE_ROOM, ENTER_NEXT_ROOM,
  REACH_HERE) and its position = where the arrow points. Listens to the level's signals; rewinds
  to the room's first step on restart. `Scripts/floor_guide.gd` = scrolling yellow floor chevrons.
- **Lighting** (`Scripts/light_fx.gd`): a CanvasModulate darkens the ship (`darkness` export).
  PointLight2Ds add light: red emergency light per unpowered room, ceiling lights when powered,
  pad lights, the helmet lamp (on only in unpowered rooms) and a hand glow while carrying.
  Things that should glow by themselves call `LightFX.glow(item)`: they move to light channel 2,
  lit only by one flat level-wide "glow light", so they stay bright but keep normal draw order.
  `light_mask` is NOT inherited — call it on every drawn node.
- **Player sprite**: animations live in SpriteFrames files, `Assets/images/astronaut/
  astronaut_frames.tres` (original art: idle, walk_down/left/right, carry, shock, burnt) and
  `astronaut_v2_frames.tres` (adds walk_up and idle_<dir>). `player.gd` picks the first animation
  the current sprite has (`_first_existing`), so either file works. v2 wants sprite y = -19.

## Gotchas
- Children run `_ready()` before parents: nodes that need the level use `call_deferred`.
- Line2D `default_color` multiplies its texture (the light-blue default made the chevrons invisible).
- `tile_map_data` is binary (uint16 format version, then 12 bytes per cell:
  int16 x, int16 y, uint16 source, uint16 atlas_x, uint16 atlas_y, uint16 alternative).
  Edit the map in the Godot editor, not by hand.
- Unused, safe to delete: `Scripts/hint_sign.gd`, `Scenes/hint_sign.tscn`. `Scenes/main.tscn` and
  `electric_box.*` are the old prototype.

## Python tools
`tools/` (ignored by Godot via `.gdignore`) has the level solver, map/lighting previews, and the
generators for the sounds and the v2 sprite. See `tools/README.md`. After editing a room, run
`python tools/map_from_scene.py` then `python tools/solver2.py tools/out/level1.txt` to check it.

## AI-generated content (for TSA documentation)
Made with Claude (Anthropic) in the Claude app: the level/tutorial/lighting scripts, the tile and
astronaut sprite sheets (cleaned up from the team's AI-generated art; `astronaut_v2.png` was
hand-composited in code), and all sounds in `Assets/audio` (synthesized in Python from sine waves,
noise and volume envelopes — no outside sources). Level 1's rooms were checked with a Python
solver for one intended solution with >= 1.7 s spare per 5 s segment. The tools in `tools/`
were also written by Claude.
