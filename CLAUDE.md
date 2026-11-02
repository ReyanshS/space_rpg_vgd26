# TSA Video Game Design 2027 — project notes for Claude

Godot 4.7 top-down puzzle game for the TSA Video Game Design event (2026-27; AI use is allowed but
must be documented). Working title **LIVE WIRE**. The player is an astronaut restoring power to a
dead spaceship by carrying a live wire from pad to pad, helped by PIP, the ship's maintenance AI.
`Scenes/title.tscn` is the main scene -> `level_1.tscn` (Engineering Deck, 4-room tutorial) ->
`level_2.tscn` (Main Deck: bridge, airlock, spacewalk on the hull).

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
- When playtesting with Godot from the command line, **mute it**: `--audio-driver Dummy`.

## TSA requirements (check work against these)
- Official event guide (2027 & 2028 nationals) — key points: game > 3 minutes of play (-5 pts if
  shorter); judges must be able to play to the **3rd level**; playable in all browsers from a link (no
  downloads); no weapons/violence, rated E; demo video < 5 min (tutorial, a level played, the
  code/engine). Portfolio PDF order: title page; purpose, audience, how to play + controls (max 2
  pages); hand-drawn storyboard; copyright checklist; permissions; Resources & AI Reflection (max 4).
- Rating form: Creativity x2, Technical skill x2, Storyline/flow between levels x1, Overall appeal x2
  (game design 70); video, portfolio, directions/controls, storyboard, AI reflection (50).
- 2026-27 theme: *"Create a deep space-themed RPG where the primary method of progression is
  puzzle-solving rather than combat."* RPG elements now in: story/dialogue (PIP), collectibles
  (power cells) that upgrade the suit (+5 s oxygen each on spacewalks), results/stars per level.
- **Level 3 is not built yet** — the guide says judges play to level 3.
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
  make it are refused (`wire_reaches()`). It CAN stretch across open space.
- NODE (orange): wraps the wire, refills the timer, pauses it while you stand on it. Touch radius 22 px.
- BEND (purple): stops you, shows two arrows, you press one and get flung 90 deg
  (`bend_pauses_timer`). The fling stops at a wall, a node, or a hull edge.
- GOAL (blue): powers the room — lights on, conduit fills, the door opens.
- Red DISCHARGE tile: stepping on it (wire or not) = shock, room restarts. Timer at 0 = wire snaps,
  room restarts. **R** restarts manually (only counts as a retry while carrying the wire).
- POWER CELL: touch it *while carrying the wire* to charge it (radius 14 px). Kept when the room is
  powered, returned if you fail. Touching one without the wire triggers PIP's explanation once.
- Results at the exit: time, cells, retries; stars = finish + all cells + retries <= rooms with a goal.
  `Game` (autoload, `game_state.gd`) stores results; cells from earlier levels = extra oxygen.
- **H** shows the room's hint route (a FloorGuide with `hint_only`); PIP offers it after 2 fails.
  **Esc** pauses (the HUD runs with process mode Always), **Q** on the pause menu = title.

## Spacewalk rules (Level 2)
- `hull` = floor outside the ship, `space` = open space (nothing drawn: the Starfield shows). A room
  containing either is an OUTSIDE room: `space_light` instead of `darkness`, space music, no
  emergency/ceiling lights (blinking hull beacons appear when powered), and an **oxygen** meter
  (`o2_seconds` + `Game.o2_bonus()`), refilled on entering a new section, on powering it and on
  respawn. Out of O2 = fail.
- Feet can't stand on space. Walking (cardinally) into a hull edge asks `drift_landing()`: if there
  is hull straight ahead (and the wire won't snag), the player **drifts** (`State.DRIFT`,
  `drift_speed` 150) until fully back on hull. No landing = refused with red dots + PIP tip.
- A door with no wall beside it is a **gangway** (catwalk that slides out). A crate with no floor or
  hull beside it is floating debris. A cell with open space on both opposite sides floats in space
  (that tile counts as space).
- `airlock` pad: stepping on it (once) closes the door behind, vents the air, opens the outer door
  and starts the oxygen meter (`_cycle_airlock`).

## Architecture (data -> logic -> visuals)
- **The map is painted**, not coded: the `Layout` TileMapLayer uses
  `Assets/images/tiles/layout_tileset.tres`; each tile has Custom Data `kind` (floor, wall, start,
  goal, node, bend, discharge, discharge_off, crate, door, spawn, exit, cell, hull, space, airlock).
  Rooms are found by flood fill (walls/doors separate them; space and void separate hull sections)
  and numbered in walking order from the spawn. Each room needs exactly one START (airlocks none).
  Doors open when an adjacent room is solved.
- `Scripts/level.gd` (`WireLevel`, `@tool`): reads the Layout, builds the pretty Ground/HullEdges/
  Walls/Props layers live in the editor, then at runtime runs all the rules, camera, lighting, audio
  and music. Exports: `level_number`, `level_name`, `complete_message`, `room_titles`, rules,
  lighting, `o2_seconds`. Signals: `room_entered`, `room_solved`, `room_restarted`, `wire_grabbed`,
  `pad_touched(kind, index)`, `level_completed`, `cell_collected`, `empty_cell_touched`,
  `hint_shown`, `drift_started`, `airlock_cycling`, `all_rooms_powered`.
- `Scripts/player.gd` (`Astronaut`): state machine FREE / WIRED / CHOOSING / FLUNG / LOCKED / DRIFT.
  Only movement + animation; asks the level for rules (`player_moved()`, `wire_reaches()`,
  `drift_landing()`...).
- `Scripts/game_state.gd` (autoload **Game**): level order (`LEVELS`), results, `o2_bonus()`,
  `go_to_level()`, `story_values()` for `{cells}` / `{o2_bonus}` in story text.
- `Scripts/puzzle_tile.gd`: runtime visuals for pads/doors/gangways/airlock (glow, sparks, arrows).
- `Scripts/power_cell.gd`: the collectible battery (draws itself, collect/restore animations).
- `Scripts/wire.gd`: carried wire + floor conduits (Line2D + `Shaders/wire_current.gdshader`).
- `Scripts/hud.gd` + `Scenes/hud.tscn`: objective box + arrow, toasts, timer bar, fades, PIP's speech
  box (`say(lines, speaker, blocking)`, typewriter, moves to the top if the player is low on screen;
  a blocking speech cuts casual chatter short), power meter, cell counter, O2 gauge, results
  screen with stars, pause menu.
- **Story** (`Scripts/story.gd` on the `Story` node + `Scripts/story_beat.gd` Marker2D children):
  each beat has `trigger` (LEVEL_START, ENTER_ROOM, SOLVE_ROOM, REACH_HERE, GRAB_WIRE, FAIL_IN_ROOM,
  AIRLOCK, ALL_POWERED, FIRST_DRIFT, TOUCH_EMPTY_CELL), `lines`, `pause_game`; its room = where the
  marker sits. Plays once. Blocking beats never freeze a player who carries the wire.
- **Tutorial**: `Scripts/tutorial.gd` on the `Tutorial` node runs its `TutorialStep` children
  (`Scripts/tutorial_step.gd`, Marker2D) in tree order. Each step has `text`, `advance_when`
  (GRAB_WIRE, TOUCH_NODE, TOUCH_BEND, SOLVE_ROOM, ENTER_NEXT_ROOM, REACH_HERE, DRIFT) and its
  position = where the arrow points. A step only shows once the player is in its room. Rewinds to
  the room's first step on restart. `Scripts/floor_guide.gd` = scrolling yellow floor chevrons
  (`hint_only` = hidden until H).
- **Lighting** (`Scripts/light_fx.gd`): a CanvasModulate darkens the ship (`darkness` export).
  PointLight2Ds add light: red emergency light per unpowered room, ceiling lights when powered,
  pad lights, the helmet lamp (on only in unpowered rooms) and a hand glow while carrying.
  Things that should glow by themselves call `LightFX.glow(item)`: they move to light channel 2,
  lit only by one flat level-wide "glow light", so they stay bright but keep normal draw order.
  `light_mask` is NOT inherited — call it on every drawn node.
- **Space background** (`Scripts/starfield.gd`): parallax stars + `Assets/images/space/planet.png`
  and `nebula.png`, on a CanvasLayer at layer -10 (not darkened by the CanvasModulate).
- `Scenes/title.tscn` + `Scripts/title.gd`: title, premise, controls, press E.
- **Player sprite**: animations live in SpriteFrames files, `Assets/images/astronaut/
  astronaut_frames.tres` (original art: idle, walk_down/left/right, carry, shock, burnt) and
  `astronaut_v2_frames.tres` (adds walk_up and idle_<dir>). `player.gd` picks the first animation
  the current sprite has (`_first_existing`), so either file works. v2 wants sprite y = -19.

## Gotchas
- Children run `_ready()` before parents: nodes that need the level use `call_deferred`.
- Line2D `default_color` multiplies its texture (the light-blue default made the chevrons invisible).
- `tile_map_data` is binary (uint16 format version, then 12 bytes per cell:
  int16 x, int16 y, uint16 source, uint16 atlas_x, uint16 atlas_y, uint16 alternative).
  Edit the map in the Godot editor, or sketch it as text and use `tools/map_to_scene.py`.
- Coroutines (`await`) on the HUD can resume after the scene changed: check `is_inside_tree()`.
- Running a test script with `--script` loads before autoloads are registered: don't use the
  project's class names as types in such scripts (access them dynamically).
- Unused, safe to delete: `Scripts/hint_sign.gd`, `Scenes/hint_sign.tscn` (if present).
  `Scenes/main.tscn`, `Scripts/main.gd` and `electric_box.*` are the old prototype.

## Python tools
`tools/` (ignored by Godot via `.gdignore`) has the level solver, map/lighting previews, the map
writer and the art/sound generators. See `tools/README.md`. After editing a room, run
`python tools/map_from_scene.py <scene> <out.txt>` then `python tools/solver2.py <out.txt>` to check
it (routes, tightest segment, and whether every power cell can be charged in time).

## AI-generated content (for TSA documentation)
Made with Claude (Anthropic) in the Claude app and Claude Code: the level/tutorial/lighting/story/
HUD scripts, Level 2's layout and puzzles (drafted as text, verified with the solver), the tile and
astronaut sprite sheets (cleaned up from the team's AI-generated art; `astronaut_v2.png` was
hand-composited in code), the hull/space/gangway/airlock art, planet and nebula (drawn pixel by
pixel in `tools/art_space.py`), PIP's dialogue text, and all sounds and music in `Assets/audio`
(synthesized in Python from sine waves, noise and volume envelopes — no outside sources). Level 1's
rooms are the team's design, checked with a Python solver; Claude placed Level 1's power cells.
The tools in `tools/` were also written by Claude. Gameplay was playtested by automated scripts
that drive the real game with simulated key presses.
