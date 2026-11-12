# TSA Video Game Design 2027 — project notes for Claude

Godot 4.7 top-down puzzle game for the TSA Video Game Design event (2026-27; AI use is allowed but
must be documented). Title **STAR CIRCUIT** (the team's name). The player is an astronaut restoring
power to a dead spaceship by carrying a live wire from pad to pad, helped by PIP, the ship's
maintenance AI. `Scenes/title.tscn` is the main scene (logo: `Assets/images/ui/logo.png`) ->
`level_1.tscn` (Engineering Deck: the team's 4 rooms joined by doors, then the Generator Room: 3
stages split by cargo barriers, ending in blinking grates) -> `level_2.tscn` (Main Deck: bridge,
airlock, spacewalk across one open hull) -> `level_3.tscn` (The Core: PIP malfunctions and you
reboot him by looping the wire round his core three times; the team's idea, see "The core" below).
- The team works in `D:\Godot\tsa-project\space_rpg_vgd26` (GitHub `ReyanshS/space_rpg_vgd26`,
  branch `nilay-claude`, public) and pushes with GitHub Desktop - the command line here can't sign
  in to GitHub. A teammate also edits the maps: fetch before working.

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
- **Writing (PIP, tutorial, popups):** the team wants it to sound natural, not AI-written. Short
  plain sentences, contractions, no dashes of any kind as punctuation, few exclamation marks, no
  ALL-CAPS words inside PIP's lines. PIP is a slightly nervous maintenance bot with dry humour.
  Each line must fit the console: **two lines of text** (about 72 characters; the speaker name
  counts too). Exception on purpose: in Level 3 the malfunctioning PIP talks in CAPS as speaker
  "P!P" (red), and the real PIP whispers through in lowercase as "PIP" (green).
- **Fun > features.** The team said the game "isn't that fun". Anything that makes a player wait
  with nothing to do (e.g. stuck after a mistake until the timer runs out) is a bug to fix.

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
- Level 3 exists (the guide says judges play to level 3). A full bot run of it takes ~75 s of play.
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
- BEND (purple): stops you, shows two arrows AND a dotted preview of where each one throws you
  (`predict_fling()`, same 2 px steps as the real fling), you press one and get flung 90 deg
  (`bend_pauses_timer`). The fling stops at a wall, a node, or a hull edge.
- REEL BACK: **E while walking with the wire** pulls you back along it to the last pad it's
  wrapped round (`_reel_back()`); onto a bend = choose again, onto a node = timer paused. Costs
  the flying time. After 0.7 s standing still away from that pad, an [E] key shows above you.
- Pads/cells count as touched from the feet OR from BODY_UP (10 px) higher (`_touching()`),
  because the sprite is taller than a tile. Radii: start 20, node 22, goal 22, bend 20, cell 14.
- GOAL (blue): powers the stage — lights on, conduit fills, its doors open and every BARRIER
  GROUP touching the stage sinks into the floor (a wave, nearest the goal first).
- Stages in the same area (joined by barriers) SHARE pads: a later stage's wire can wrap round
  the nodes and bends of stages already powered there (`_stage_pads()`).
- BLINKING GRATE (`blinker`, map char `x`): lit for `grate_live` of every `grate_cycle` seconds,
  each column `grate_wave` s behind the one to its left (a wave); flickers just before lighting.
  Lit = zaps your feet (also if you stand still); the wire is never blocked by it.
- Red DISCHARGE tile: stepping on it (wire or not) = shock. Timer at 0 = wire snaps. Either way
  the stage resets but the player **stays where he fell** (`_stay_after_fail()` pushes him to the
  nearest safe tile if he's on red or over space; O2 refills). He walks back to the START himself.
  **R** = fade back to the START (only counts as a retry while carrying the wire).
- POWER CELL (a full battery): touch it *while carrying the wire* and it adds `cell_bonus` (2 s)
  to the wire timer right away - a detour that can pay for itself. Kept when the stage is
  powered (star + suit oxygen later), back if you fail. PIP explains cells at Level 1's start (a
  StoryBeat with `point_here`); first use / keep / loss get one-time messages (`Game.first_time()`).
  The solver does NOT count the bonus time (so it never relies on it).
- All rooms powered -> the **lights-on cutscene** (`_power_tour()` in level.gd): film bars, the
  camera glides back through every room and lights each one at full power (`full_power_light`).
  StoryBeats with trigger SHIP_LIGHTS_UP play during it, ALL_POWERED ones after it.
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

## The core (Level 3)
- `core` tile (map char `@`): a round socket, solid for feet and wire. A room with a core has no
  goal: it's powered when the wire (START -> pads -> hands) winds a full turn round the core
  (`_winding()`: sum of `angle_to` of each straight piece, seen from the core; `_check_loop()` in
  `player_moved()`). The socket shows a yellow ring = how far round (`PuzzleTile.show_loop`), with a
  tick at the START's direction: the loop closes when your hands cross that line.
- Story: Level 3's first room (CORE ACCESS) teaches the loop on a harmless "sync pylon". Powering
  it overloads PIP (`RoguePip.malfunction_room`): red alert (`set_alert`: `alert_light` tint,
  every emergency light flashes, `music_core.wav`), he talks as "P!P", and hides in the core
  chamber: 3 stages joined by barriers, one core each (open ring / behind cargo + bend / between
  blinking grates). Each loop reboots him a bit; he flies to the next socket. The last one shuts
  him down, he reboots, then the normal lights-on cutscene plays.
- `Scripts/rogue_pip.gd` (`RoguePip`, node in level_3.tscn) is NOT a rule: it listens to
  `room_solved`, and calls level.gd's small public API: `core_spots()`, `wire_room_index()`,
  `cut_wire()` (fail kind "cut"), `set_alert()`, `shake()`, `hold()`/`let_go()` (`_solve()`
  waits for every hold before opening doors / the cutscene). Its SHUTDOWN METER (12 red LEDs over
  his head) fills only while you carry the wire in his stage: `shutdown_seconds` per phase
  (18, 15, 19). Full = pulse that cuts the wire. A Mood enum (ASLEEP, ROGUE, HIT, OFF, BOOT, AWAKE)
  drives how he's drawn (code-drawn monitor, 2x scale via `draw_set_transform`).
- HUD: `set_rogue(on)` turns PIP's console face red and angry; any line with speaker
  `GameHUD.ROGUE_SPEAKER` ("P!P") is red.
- Solver: `@` rooms are solved by winding (it reports "s in all" = total route time, compare it
  with `shutdown_seconds`); it skips pads that turn the loop backwards. It doesn't model grates.

## Architecture (data -> logic -> visuals)
- **The map is painted**, not coded: the `Layout` TileMapLayer uses
  `Assets/images/tiles/layout_tileset.tres`; each tile has Custom Data `kind` (floor, wall, start,
  goal, node, bend, discharge, blinker, crate, door, spawn, exit, cell, hull, space, airlock,
  barrier, core). Rooms (= puzzle STAGES) are found by flood fill (walls/doors/barriers separate them;
  space and void separate hull sections) and numbered in walking order from the spawn. Each needs
  exactly one START (airlocks none). Doors open when the room before them is solved; touching
  barrier tiles form a GROUP (`_build_barrier_groups()`) that sinks when any stage next to it is.
- **Areas**: stages joined by a barrier group (or a gangway outside) form one AREA
  (`_build_areas()`): the camera roams across the whole area (`area_bounds`), the name popup only
  shows when you enter a new area, and pads are shared (see Game rules). Doors start a new area.
  The team wants BOTH: normal rooms joined by doors, and multistage rooms where powering a stage
  really changes the room for the next one. A good multistage room makes the next stage NEED the
  opened space (e.g. Generator Room stage B only works by wrapping round stage A's node through
  the sunk barrier column) - not just a barrier where a door would be. Check every new stage with
  the solver (it opens barrier groups of earlier stages and shares their nodes, like the game).
- `Scripts/level.gd` (`WireLevel`, `@tool`): reads the Layout, builds the pretty Ground/HullEdges/
  Walls/Props layers live in the editor, then at runtime runs all the rules, camera, lighting, audio
  and music. Exports: `level_number`, `level_name`, `complete_message`, `room_titles`, rules,
  lighting, `o2_seconds`. Signals: `room_entered`, `room_solved`, `room_restarted`, `wire_grabbed`,
  `pad_touched(kind, index)`, `level_completed`, `cell_collected`, `empty_cell_touched`,
  `hint_shown`, `drift_started`, `airlock_cycling`, `ship_lighting_up` (cutscene starts),
  `all_rooms_powered` (cutscene over).
- `Scripts/player.gd` (`Astronaut`): state machine FREE / WIRED / CHOOSING / FLUNG / LOCKED / DRIFT.
  Only movement + animation; asks the level for rules (`player_moved()`, `wire_reaches()`,
  `drift_landing()`...).
- `Scripts/game_state.gd` (autoload **Game**): level order (`LEVELS`), results, `o2_bonus()`,
  `go_to_level()`, `first_time(tip)` (PIP explains things once), `story_values()` for `{cells}` /
  `{o2_bonus}` / `{o2_per_cell}` in story text.
- `Scripts/puzzle_tile.gd`: runtime visuals for pads/doors/gangways/airlock/barriers (glow, sparks,
  arrows; barriers shudder and sink, `open_door(delay)`).
- `Scripts/power_cell.gd`: the collectible battery (draws itself, collect/restore animations).
- `Scripts/wire.gd`: carried wire + floor conduits (Line2D + `Shaders/wire_current.gdshader`).
- `Scripts/hud.gd` + `Scenes/hud.tscn`: a fixed **console** along the bottom (`CONSOLE_H` 48 px;
  level.gd frames the room ABOVE it, so the HUD never covers play): PIP's CRT face + his speech
  (`say(lines, speaker, blocking, point_at)`, typewriter; when quiet it shows the tutorial
  objective dimmed), ship power LEDs, cell counter, O2 bar (outside) or key reminders. The wire
  timer is a 5-LED bar floating above the astronaut's head. Also: tutorial/PIP arrows, toasts
  (top), fades, results with stars + suit upgrade, pause menu, cutscene film bar (top).
- **UI look** (the team asked for "less AI"): ship hardware outside, old green terminal inside.
  Panels are 9-slice `StyleBoxTexture`s of `Assets/ui/frame_screen.png` (riveted bezel + green
  scanline screen) and `frame_plate.png` (riveted plate), drawn by `tools/art_ui.py`, margin 6.
  Colours: amber `#ffc24d` (names, keys, headings), phosphor green `#a8f0a0` (text), dim green for
  hints. Meters are LED segments (`_led()` in hud.gd). Keep new UI in this style - no flat
  translucent boxes with thin glowing borders.
- **Story** (`Scripts/story.gd` on the `Story` node + `Scripts/story_beat.gd` Marker2D children):
  each beat has `trigger` (LEVEL_START, ENTER_ROOM, SOLVE_ROOM, REACH_HERE, GRAB_WIRE, FAIL_IN_ROOM,
  AIRLOCK, ALL_POWERED, FIRST_DRIFT, TOUCH_EMPTY_CELL, SHIP_LIGHTS_UP), `lines`, `pause_game`,
  `point_here` (blue arrow at the marker while it plays); its room = where the marker sits. Plays
  once. Blocking beats never freeze a player who carries the wire. New triggers go at the END of
  the enum (scenes store the number).
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
HUD scripts (incl. the lights-on cutscene), Level 2's layout and puzzles (drafted as text, verified with the solver), the tile and
astronaut sprite sheets (cleaned up from the team's AI-generated art; `astronaut_v2.png` was
hand-composited in code), the hull/space/gangway/airlock art, planet and nebula (drawn pixel by
pixel in `tools/art_space.py`), PIP's dialogue text, and all sounds and music in `Assets/audio`
(synthesized in Python from sine waves, noise and volume envelopes — no outside sources), the
barrier tile (`tools/art_barrier.py`) and the UI frames (`tools/art_ui.py`). Level 1's puzzles are
the team's design, checked with a Python solver; Claude placed Level 1's power cells and, at the
team's request, designed Level 1's Generator Room (multistage barriers, shared nodes, blinking
grates). The title logo was provided by the team; `tools/logo_import.py` (Claude) removed its
painted-on checkerboard background and shrank it to game pixels - record where the logo came from.
Level 3: the IDEA (PIP malfunctions, you surround him with wire before he destroys it, which brings
him back) is the team's (Discord, Nov 2026); Claude designed the loop rule, the layout and puzzles
(solver-checked), wrote `rogue_pip.gd` and the dialogue, drew the core tile (`tools/art_core.py`)
and made the boss sounds/music (`tools/sfx_pip.py`).
The tools in `tools/` were also written by Claude. Gameplay was playtested by automated scripts
that drive the real game with simulated key presses.
