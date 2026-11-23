# TSA Video Game Design 2027 — project notes for Claude

Godot 4.7 top-down puzzle game for the TSA Video Game Design event (2026-27; AI use is allowed but
must be documented). Title **STAR CIRCUIT** (the team's name). The player is an astronaut restoring
power to a dead spaceship by carrying a live wire from pad to pad, helped by PIP, the ship's
maintenance AI. `Scenes/title.tscn` is the main scene (logo: `Assets/images/ui/logo.png`) ->
`level_1.tscn` (Engineering Deck: the team's 3 tutorial rooms, then a small dungeon: the Reactor
Hall hub with 3 wings and a main door, then the Generator Room: 3 stages split by cargo
barriers, ending in blinking grates; see "Dungeon parts") -> `level_2.tscn` (Main Deck: bridge,
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
  Each line MUST fit the console: **two rows at 16 px** (about 70 characters; the speaker name
  counts too). One text size everywhere (the team tried 12 px for long lines and said no).
- **Code comments** follow the same style: plain sentences, no dashes as punctuation (use a
  comma, colon, full stop or brackets), no ALL-CAPS words for emphasis, script headers written as
  `# name.gd: what it does`. Caps are fine for real names: enum values, constants, START/GOAL/NODE
  pads, PIP, XP/LV, and on-screen texts in quotes. (The AI-use record at the bottom stays: TSA
  requires it.)
  A longer line gets split into pages, which players miss, so the editor marks it red on
  the story beat ("TOO LONG"): shorten it. The "press E" key is its own HUD node (`NextKey`,
  under PIP's portrait), never part of the text.
  Exception on purpose: in Level 3 the malfunctioning PIP talks in CAPS as speaker
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
  puzzle-solving rather than combat."* RPG elements now in: story/dialogue (PIP), a skill tree
  (3 branches, points for finishing levels), collectibles (power cells: +5 s oxygen each on
  spacewalks), results/stars per level, a save file with Continue. See "RPG" below.
- **Balance (Nov 2026, "too easy")**: timer rules per level (Inspector, Rules group):
  L1 START 4.5 / node +3.5 / max 6 / hold 2 s, own START times 5.5, -, 6, 3.5, 3.2, -, 5;
  L2 3.5 / +3 / 5 / 1 s, room 3 = 4.2, room 5 = 5, `o2_seconds` 50; L3 3.5 / +2.5 / 5.2 / 1 s,
  PIP's `shutdown_seconds` 14 / 13.5 / 9.5 (about 1.5x the best route: after the Nov 21 map
  the best routes take 9.3 / 8.9 / 5.4 s plus grate waits; 10 s for stage A was too tight). Target "lowest timer"
  on the most forgiving perfect route: tutorial rooms (L1 1-3) 2.3-3 s, rest of L1 1-1.8 s,
  L2 0.7-1.3 s (hard but fair), L3 rooms are timed mostly by PIP's meter. A bot replayed the
  solver's route in every room in the real game: all solvable, lowest timer within ~0.1 s of
  the solver. Re-check after ANY change: `python tools/solver2.py Scenes/level_N.tscn`.
- Level 3 exists (the guide says judges play to level 3). A full bot run of it takes ~75 s of play.
- Judges play from a link, so the game needs a **web export**. Web builds run on WebGL 2 (Godot's
  Compatibility renderer); this project is set to Forward+, so test a web export early and check
  that the lighting still looks right.

## Display
480x270 viewport scaled 3x, nearest filtering, 32x32 tiles. UI font: m6x11 (`Assets/fonts`) via
`Assets/ui/theme.tres` at size 16 — only use multiples of 16 or the pixel font blurs.

## Game rules (level.gd enforces them)
- START pad: stand on it, press **E/Space** to grab the wire. The timer starts with `wire_time`
  seconds (or that room's `room_wire_time`). Nothing ever pushes it above `max_wire_time`.
- Free movement while carrying. The wire is a taut straight line from the LAST pad touched to the
  player's hands; it can't pass through walls, crates, doors or live red tiles, so steps that would
  make it are refused (`wire_reaches()`). It CAN stretch across open space.
- NODE (orange): wraps the wire and ADDS `node_time` (no full refill), capped at `max_wire_time`.
  Standing on it holds the clock, but only for `node_hold` s. Touch radius 22 px.
- POLE (a steel support pillar with a purple cable ring, map char `B`, tile kind `pole`; was the
  "bend" until Nov 2026): solid for
  feet, not for the wire. Looks: `Assets/images/tiles/pillar.png` (32x64, foot on the tile's
  centre) + `pillar_glow.png` (the ring, glow channel), drawn by `tools/art_pillar.py`;
  `PuzzleTile._make_pillar()` / `_update_pillar()` draw it over the wires, under the player, but
  over him and see-through while he walks behind it. level.gd draws the same picture in the
  editor (`_draw_pillar_preview`). The column covers the tile above the pole. The wire wraps round its centre when it sweeps across it and unwraps when
  you sweep back (`_update_wraps()` / `_swept_over()`: the swung triangle anchor->old hands->new
  hands must contain the pole, with real width). Gives no time. Anchors list = pads AND poles
  (`_anchor_cells` + `_anchor_signs`), so `_winding()` counts poles too. The solver uses the exact
  same rule (`rewrap()` / `swept_over()`); keep them identical.
- REEL BACK: **E while walking with the wire** pulls you back along it (past each pole) to the last
  pad it's wrapped round (`_reel_back()`), unwrapping the poles; onto a node = it holds again. Costs
  the flying time. After 0.7 s standing still away from that pad, an [E] key shows above you.
- Pads/cells count as touched from the feet OR from BODY_UP (10 px) higher (`_touching()`),
  because the sprite is taller than a tile. Radii: start 20, node 22, goal 22, cell 14.
- GOAL (blue): powers the stage — lights on, conduit fills, its doors open and every BARRIER
  GROUP touching the stage sinks into the floor (a wave, nearest the goal first).
- Stages in the same area (joined by barriers) SHARE pads: a later stage's wire can wrap round
  the nodes of stages already powered there (`_stage_pads()`). Poles work anywhere (they're posts).
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
- **Menus use real Buttons** (pause: RESUME / SKILL TREE / QUIT; results: NEXT LEVEL /
  PLAY AGAIN / SKILL TREE; title: START or CONTINUE + NEW GAME; skill tree: UNLOCK / BACK).
  Their look is in the project theme (`Assets/ui/theme.tres`, textures `Assets/ui/button_*.png`
  drawn by `tools/art_ui.py`), so new Buttons match on their own. Keys: arrows move the focus,
  E / Space / Enter press it (Game._ready adds E to `ui_accept`). The top right corner always
  has SKILLS (opens the tree, shows "+n" when you have points) and MENU (pause); they have
  `focus_mode` none so Space never presses them while you play. Unpausing is deferred to the
  end of the frame so the E that pressed RESUME doesn't also grab the wire.

## Dungeon parts (Nov 2026: "make it less linear, like a Zelda dungeon")
- Level 1 is a dungeon: tutorial rooms 1-3 (the team's), then the REACTOR HALL hub with three
  wings: CABLE STORE (open; its cargo hides the clamp and a fuse), COOLANT PUMPS (open, needs the
  clamp: `needs the clamp` in the solver), REACTOR ACCESS (the team's old room 4, behind a fuse
  door). Each wing's goal has a PowerLink UNLOCK to the MAIN DOOR, which opens onto the
  Generator Room finale. Built by `tools/maps/build_level1_dungeon.py`. Order: B, then A and C in
  any order. Room numbers changed (halls count): room_titles / room_wire_time are 14 long.
- A **hall** = a room with no START and no goal/core (`is_hall()`): never a puzzle, its doors open
  at the start (`_setup_dungeon`), it never sinks barriers.
- Tiles (map char): `fuse` f (pickup), `fuse_door` F (opens if you carry a fuse), `main_door` M
  (lamps = UNLOCK links pointing at it), `socket` o, `clamp` k (pickup, one per level). Art:
  `tools/art_dungeon.py` (puzzle frames 14-16, palette 18-22). Pickups draw themselves
  (`Scripts/pickup.gd`).
- **PowerLink** (`Scripts/power_link.gd`, @tool Marker2D under a "Links" node): sits on a goal,
  child markers = targets, `action` OPEN / CLOSE / RED_OFF / RED_ON / UNLOCK, `message`,
  `show_camera` (`_glance_at`). Applied in `_solve()` after `_open_exit_doors` (`_apply_links`),
  and quietly by `_power_quietly`. Red floors switched off live in `_red_off`; use `_is_red(c)`.
- **Clamp**: E next to a socket (no wire) drops / takes it (`_try_clamp`); in a socket it's added
  to `_poles`, so the wrap rule is the pole rule. The solver tries every socket.
- **Ship map** (M): `Scripts/ship_map.gd`, drawn from `level.map_info()`; only in levels with
  halls / fuse doors / main doors / links (`hud.set_map_available`).
- Console: fuse count and clamp icon (hud.gd `set_fuses`, `set_clamp`).

## Judge mode and PIP's autopilot
- Title, top left: JUDGE MODE toggle (`Game.judge_mode`, saved) + LEVEL n buttons. In a level,
  R = `start_autopilot()` instead of restart; after 2 fails PIP says `pip_hint_judge`.
- `Scripts/autopilot.gd`: walks to the next room (`autopilot_target()`: current unsolved room,
  then the level's `walkthrough` export, then number order), fetches / places the clamp,
  collects fuses, steps on airlock pads, drifts across space (`walk_path()` has drift edges),
  grabs the wire and steers along the solver's route (`player.autopilot` + `auto_dir`, so the
  normal rules run). While `autopilot_on`: timer frozen, no zaps, no O2 drain, no PIP shutdown
  meter, blocking beats don't block. Falls back to `autopilot_force_solve()` (+ a warning).
- Routes: `Data/routes/level_N.json` from `python tools/solver2.py Scenes/level_N.tscn --paths
  Data/routes/level_N.json --margin 3` (keyed by START tile; `clamp` = the socket used).
  **Regenerate after any map change.** Test: a bot that only presses R (see Verification below).

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
  every emergency light flashes, boss music `music_core.ogg`), he talks as "P!P", and hides in the core
  chamber: 3 stages joined by barriers, one core each (open ring / behind cargo + pole / between
  blinking grates). Each loop reboots him a bit; he flies to the next socket. The last one shuts
  him down, he reboots, then the normal lights-on cutscene plays.
- `Scripts/rogue_pip.gd` (`RoguePip`, node in level_3.tscn) is NOT a rule: it listens to
  `room_solved`, and calls level.gd's small public API: `core_spots()`, `wire_room_index()`,
  `cut_wire()` (fail kind "cut"), `set_alert()`, `shake()`, `hold()`/`let_go()` (`_solve()`
  waits for every hold before opening doors / the cutscene). Its SHUTDOWN METER (12 red LEDs over
  his head) fills only while you carry the wire in his stage: `shutdown_seconds` per phase
  (see Balance above). Full = pulse that cuts the wire. A Mood enum (ASLEEP, ROGUE, HIT, OFF, BOOT, AWAKE)
  drives how he's drawn (code-drawn monitor, 2x scale via `draw_set_transform`).
- HUD: `set_rogue(on)` turns PIP's console face red and angry; any line with speaker
  `GameHUD.ROGUE_SPEAKER` ("P!P") is red.
- Solver: `@` rooms are solved by winding (it reports "s in all" = total route time, compare it
  with `shutdown_seconds`); it skips pads that turn the loop backwards. It doesn't model grates.

## Architecture (data -> logic -> visuals)
- **The map is painted**, not coded: the `Layout` TileMapLayer uses
  `Assets/images/tiles/layout_tileset.tres`; each tile has Custom Data `kind` (floor, wall, start,
  goal, node, pole, discharge, blinker, crate, door, spawn, exit, cell, hull, space, airlock,
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
- `Scripts/player.gd` (`Astronaut`): state machine FREE / WIRED / LOCKED / DRIFT (no fling any more).
  Only movement + animation; asks the level for rules (`player_moved()`, `wire_reaches()`,
  `drift_landing()`...).
- `Scripts/game_state.gd` (autoload **Game**): level order (`LEVELS`), results, the save file
  (`save_game()` / `load_game()`, `user://save.cfg`, `has_save()`, `continue_level()`), `o2_bonus()`,
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
  (top), fades, results with stars + skill points, pause menu, the skill tree screen (an
  instance of `Scenes/skill_tree.tscn`, `hud.open_skill_tree()`), cutscene film bar (top).
- **UI look** (the team asked for "less AI"): ship hardware outside, old green terminal inside.
  Panels are 9-slice `StyleBoxTexture`s of `Assets/ui/frame_screen.png` (riveted bezel + green
  scanline screen) and `frame_plate.png` (riveted plate), drawn by `tools/art_ui.py`, margin 6.
  Colours: amber `#ffc24d` (names, keys, headings), phosphor green `#a8f0a0` (text), dim green for
  hints. Meters are LED segments (`_led()` in hud.gd). Keep new UI in this style - no flat
  translucent boxes with thin glowing borders.
- **Story** (`Scripts/story.gd` on the `Story` node + `Scripts/story_beat.gd` Marker2D children):
  each beat has `trigger` (LEVEL_START, ENTER_ROOM, SOLVE_ROOM, REACH_HERE, GRAB_WIRE, FAIL_IN_ROOM,
  AIRLOCK, ALL_POWERED, FIRST_DRIFT, TOUCH_EMPTY_CELL, SHIP_LIGHTS_UP), `lines`, `pause_game`,
  `point_here` (blue arrow at the marker while it plays, or at the beat's first Node2D child if
  it has one: `arrow_position()`); its room = where the marker sits. Plays once. Blocking beats
  never freeze a player who carries the wire. New triggers go at the END of the enum (scenes store
  the number). In the editor each beat draws a bubble + trigger + first line (red for "P!P").
- **Editing levels in Godot** (the team does this themselves; guide: `docs/level_editing.md`).
  Text that isn't story is in the level's Inspector too: groups "PIP's rule lines" (`pip_hint`,
  `pip_o2_low`, `pip_no_landing`, `pip_cell_kept`, `pip_cell_lost`, `pip_strain`, `pip_shared`;
  said via `_pip_say()`, `{cells}`-style values, empty = silent) and "Popup texts" (`popup_...`).
  Don't hard-code new player-facing text in level.gd: add an export in one of those groups.
  (Also `pip_stranded`, `popup_stranded`, `popup_boots`.)
- **Stranded after a fail**: `_check_stranded()` runs a tile BFS from the player to the room's
  START avoiding red tiles and grates; no path = an [R] key floats over him, the console says
  "[R] back to start", PIP explains once. Cleared by R, by grabbing the wire, or when a path appears.
- **RPG = skill tree** (replaced the old XP / LV / pick-an-upgrade system, Nov 2026).
  Autoload **SkillManager** (`Scripts/skill_manager.gd`, registered BEFORE Game) holds `points`
  and the unlocked skills; `has_skill(id)`, `can_unlock(id)`, `unlock(id)`, `bonus(effect)`,
  signals `points_changed`, `skill_unlocked`, `skills_changed`. Skills are DATA: one `SkillDef`
  (`Scripts/skill_def.gd`) `.tres` per skill in `Data/skills/`, loaded with
  `ResourceLoader.list_directory` (works in exports). 3 branches (Wire, Suit, Life Support),
  5 skills each, cost 1-2, each needs its `parent_id`. Effects: `wire_time` (START, and lifts
  the cap too), `node_time`, `max_time`, `node_hold`, `cell_bonus`, `walk_speed` (+8% each),
  `boots` (zaps per room absorbed), `o2`, `o2_per_cell`. Tree: Wire (LONGER WIRE I, NODE BOOST,
  BIG SPOOL, SUPER CELLS, LONGER WIRE II), Suit (servos x3, RUBBER BOOTS, INSULATED SOLES),
  Life Support (tanks, CELL CHARGER, CALM BREATHING = nodes hold 1 s longer).
  Points: level.gd export `skill_points` (L1 2, L2 3, L3 3), given in `_finish_level()` only the
  first time (`Game.has_finished()`), so replays can't farm them. The tree opens at any time
  (T, the SKILLS corner button, or the SKILL TREE buttons); it pauses the game and draws itself (`skill_tree.gd`,
  layout computed from the parent links). Unlocks apply at once (level listens to
  `skills_changed` -> `_apply_skills()`). Rules read skills through `_wire_time()`,
  `_cell_bonus()`, `_shock()`, `Game.o2_bonus()`: never read `wire_time` / `cell_bonus`
  directly in rules. **No puzzle may require a skill** (the solver uses none).
  Saving: finishing a level and every unlock call `Game.save_game()`; the title screen shows
  CONTINUE: LEVEL n + NEW GAME buttons when a save exists. Bots: `Game.new_game()` first.
  `RoguePip` is `@tool`: in the editor it previews the pylon, each socket (number + shutdown
  time) and the flight path, using `level.editor_core_spots()` (a quiet `_build_rooms(true)`).
- **TestStart** (`Scripts/test_start.gd`, one per level scene, `active` off by default): drag it,
  tick Active, F6 = start there with every earlier room powered quietly (`_apply_test_start()`,
  `_power_quietly()`); `test_room` / `test_skip_intro` on the level let story.gd, tutorial.gd and
  rogue_pip.gd catch up. Only used when the level scene is run on its own from the editor
  (`OS.has_feature("editor")` and not `Game.playing_through`), so F5 and exports ignore it.
  Bots that load a level with `change_scene_to_file` count as "on its own": keep markers inactive.
- **Dev menu** (`Scripts/dev_menu.gd`, added by Game._ready only when `OS.has_feature("editor")`,
  so never in exports): ` or F1 anywhere lists every room of every level (level.gd
  `dev_checkpoints()`, read from each scene without adding it to the tree). A pick sets
  `Game.dev_room` and loads the level; `_apply_test_start()` then runs the same
  `_start_in_room()` as TestStart, on the room's START (`_dev_spot()`). While open it freezes
  the current scene (process_mode DISABLED, also the HUD's Always nodes) so keys don't leak.
- **Tutorial**: `Scripts/tutorial.gd` on the `Tutorial` node runs its `TutorialStep` children
  (`Scripts/tutorial_step.gd`, Marker2D) in tree order. Each step has `text`, `advance_when`
  (GRAB_WIRE, TOUCH_NODE, WRAP_POLE, SOLVE_ROOM, ENTER_NEXT_ROOM, REACH_HERE, DRIFT) and its
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
- **Intro cutscene** (`Scenes/intro.tscn` + `Scripts/cutscene.gd`, a reusable slideshow):
  START on a new game / NEW GAME -> `Game.go_to_intro()` -> 3 pictures (`Assets/images/cutscenes/`,
  480x270, shown 1:1) -> Level 1. E / Space / Enter / click = next, Esc = skip all.
  CONTINUE skips it. Slides, order, next level and music are exports on the Intro node.
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
- Coroutines (`await`) can resume after the scene changed (quit to title): SceneTree timers and
  `process_frame` still fire, but the node is out of the tree, so `get_tree()` is null. After
  every `await` in level.gd / hud.gd / rogue_pip.gd: `if not is_inside_tree(): return`.
  rogue_pip.gd's `_wait()` / `_until_quiet()` return false then (`if not await _wait(0.6): return`).
  (Nov 2026: quitting during PIP's malfunction crashed on `create_timer`; a bot that quits at
  54 moments per level now runs clean.)
- Running a test script with `--script` loads before autoloads are registered: don't use the
  project's class names (Astronaut, SkillManager...) in such scripts at all, not even
  `Astronaut.State.LOCKED` (use the number: FREE 0, WIRED 1, LOCKED 2, DRIFT 3).
- **UI text** in the menus uses real Buttons and `KeyHint` (`Scripts/key_hint.gd`: drawn keycaps +
  a label, sizes itself) instead of "[E] text" strings: console key reminders, pause controls,
  title controls. Results use three stat tiles (Time / Cells / Retries).
- Unused, safe to delete: `Scripts/hint_sign.gd`, `Scenes/hint_sign.tscn` (if present).
  `Scenes/main.tscn`, `Scripts/main.gd` and `electric_box.*` are the old prototype.

## Python tools
`tools/` (ignored by Godot via `.gdignore`) has the level solver, map/lighting previews, the map
writer and the art/sound generators. See `tools/README.md`. After editing a room, run
`python tools/solver2.py Scenes/level_N.tscn`: it reads the map AND the level's Rules numbers
and lists routes with their "lowest timer" (the least time left on the way; carried over from
pad to pad) and whether every power cell can be charged in time. `--paths f.json --margin 3`
exports routes a bot can replay in the game.
Known blind spots of the cell check (false "NOT collectible"): it ignores the +2 s a cell gives,
it forgets pole wraps when it checks the way on from a cell (L1 cell (24,7) is fine in the game),
and in core rooms it never checks cells on the last stretch before the loop closes (L3 (21,3)).
Check such a cell with a bot in the game before moving it.

## AI-generated content (for TSA documentation)
Made with Claude (Anthropic) in the Claude app and Claude Code: the level/tutorial/lighting/story/
HUD scripts (incl. the lights-on cutscene), Level 2's layout and puzzles (drafted as text, verified with the solver), the tile and
astronaut sprite sheets (cleaned up from the team's AI-generated art; `astronaut_v2.png` was
hand-composited in code), the hull/space/gangway/airlock art, planet and nebula (drawn pixel by
pixel in `tools/art_space.py`), PIP's dialogue text, and all SOUND EFFECTS in `Assets/audio`
(synthesized in Python from sine waves, noise and volume envelopes — no outside sources), the
barrier tile (`tools/art_barrier.py`) and the UI frames (`tools/art_ui.py`). Level 1's puzzles are
the team's design, checked with a Python solver; Claude placed Level 1's power cells and, at the
team's request, designed Level 1's Generator Room (multistage barriers, shared nodes, blinking
grates). The title logo was provided by the team; `tools/logo_import.py` (Claude) removed its
painted-on checkerboard background and shrank it to game pixels - record where the logo came from.
Level 3: the IDEA (PIP malfunctions, you surround him with wire before he destroys it, which brings
him back) is the team's (Discord, Nov 2026); Claude designed the loop rule, the layout and puzzles
(solver-checked), wrote `rogue_pip.gd` and the dialogue, drew the core tile (`tools/art_core.py`)
and made the boss sound effects (`tools/sfx_pip.py`).
**Music is the team's own** (Nov 2026: five tracks, `Assets/audio/music_*.ogg`): title =
"Title theme dramatic", ship = "Space theme bells", space = "Space theme bells 2", rogue PIP
boss = "Space staccato", ending = "Title theme no dramatic". Claude only wired them in
(`Game.MUSIC` = per-track volume, `Game.load_music()`, `level.set_music_override()`). Record
who made them for the copyright checklist.
Nov 2026 (Claude, at the team's request): bends turned into poles (the wrap rule, the post art
in puzzle_tile.gd), the new timer rules and all the balance numbers, the reworked Level 1 room 4
and Level 2 room 5 (solver-checked, then replayed by a bot), the KeyHint keycaps and results tiles,
and fixes for errors when quitting mid-level. Also the dev menu (jump to any room).
The skill tree system (SkillManager, the skill files and their numbers, the skill tree screen,
the save file and Continue) was written by Claude in Nov 2026 to replace the XP upgrades; the
team chose the branches, the points per level and where it opens. Claude also made the menu
buttons (art drawn in `tools/art_ui.py`, styled in the theme) and the SKILLS / MENU corner
buttons, at the team's request.
Nov 22 2026 (Claude): the support pillar art for the poles (`tools/art_pillar.py`, drawn pixel by
pixel in Python, octagon design), the slideshow cutscene script and its per-picture sounds
(`tools/sfx_intro.py`, synthesized), PIP's new Level 3 shutdown times, the fly-away ending, the
dungeon systems (halls, fuses, fuse doors, main door, power links, clamp and sockets, ship map;
art in `tools/art_dungeon.py`), Level 1's dungeon layout and its new wing puzzles (Cable Store,
Coolant Pumps; solver-checked; Reactor Access is the team's old room 4, moved), and judge mode
with PIP's autopilot. The three
intro cutscene PICTURES were provided by the team (record who made them, and the tool if they
were AI-generated, for the copyright checklist); Claude only cropped them to 16:9 and shrank them
to 480x270 with Python.
The tools in `tools/` were also written by Claude. Gameplay was playtested by automated scripts
that drive the real game with simulated key presses.
