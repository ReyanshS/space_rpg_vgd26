# TSA Video Game Design 2027 — project notes for Claude

Godot 4.7 top-down puzzle game for the TSA Video Game Design event (2026-27; AI use is allowed but
must be documented). Title **STAR CIRCUIT** (the team's name). The player is an astronaut restoring
power to a dead spaceship by carrying a live wire from pad to pad, helped by PIP, the ship's
maintenance AI. `Scenes/title.tscn` is the main scene (logo: `Assets/images/ui/logo.png`) ->
`Levels/level_1.tscn` (Engineering Deck: the team's 3 tutorial rooms, then a small dungeon: the Reactor
Hall hub (the cable clamp sits in a live reactor ring: roll a crate in to short a way through) with 3
wings and a main door, then the Generator Room: 3 stages split by cargo barriers, ending in
blinking grates; see "Dungeon parts" and "Movable crates") -> `level_2.tscn` (Main Deck: bridge,
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
  Each line MUST fit the console: **two rows** of the console text (size 9, about 90
  characters; the speaker name counts too). Keep lines short anyway: about 70 reads best.
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
  puzzle-solving rather than combat."* RPG elements now in: story/dialogue (PIP), batteries as
  money (power cells you keep) for the WIRE UPGRADE (3 steps), collectibles (power cells: +5 s
  oxygen each on spacewalks), results/stars per level, a save file with Continue. See "RPG" below.
- **Tutorial at 3 s** (Nov 26 2026, "relatively easy, not millisecond timings"): Level 1's
  rooms 1-3 were moved round so the 3 s wire fits with time to spare (solver, lowest timer):
  room 1 START (11,20) -> goal (6,20): 1.60 s; room 2 (Storage, + the tutorial crate): 1.41 s,
  battery moved to (4,7); room 3 (Conduit Hall) START (17,9), pole (19,9), node (20,5), goal
  (24,5), no second pole: 0.87 s, plus the battery at (20,6) right on the way (+0.5 s).
  Tile edits that keep the team's art: `python tools/patch_tiles.py <scene> "move A B" ...`.
  Later rooms (Coolant Pumps, Cable Store, Generator B) need wire upgrades at 3 s.
  Autopilot routes are made with a long wire (he doesn't use the timer):
  `python tools/solver2.py Levels/level_1.tscn --time 10 --paths Data/routes/level_1.json --margin 3`
  (typed numbers now win over the scene's Rules).
- **Nov 26 2026 (Reyansh: "ignoring that the levels may be impossible")**: every level's
  START is **3 s** (`wire_time` 3, `room_wire_time` empty), which is also the most the
  timer holds (no `max_wire_time`), and a battery adds **0.5 s** (`cell_bonus`). The numbers below are the older balance; the solver now reports many rooms
  as too tight. That's known and accepted for now: the wire upgrade is meant to make up for it.
- **Balance (Nov 2026, "too easy")**: timer rules per level (Inspector, Rules group):
  L1 START 4.5 / node +3.5 / max 6 / hold 2 s, own START times 5.5, -, 6, 3.5, 3.2, -, 5;
  L2 3.5 / +3 / 5 / 1 s, room 3 = 4.2, room 5 = 5, `o2_seconds` 50; L3 3.5 / +2.5 / 5.2 / 1 s,
  PIP's `shutdown_seconds` 14 / 13.5 / 9.5 (about 1.5x the best route: after the Nov 21 map
  the best routes take 9.3 / 8.9 / 5.4 s plus grate waits; 10 s for stage A was too tight). Target "lowest timer"
  on the most forgiving perfect route: tutorial rooms (L1 1-3) 2.3-3 s, rest of L1 1-1.8 s,
  L2 0.7-1.3 s (hard but fair), L3 rooms are timed mostly by PIP's meter. A bot replayed the
  solver's route in every room in the real game: all solvable, lowest timer within ~0.1 s of
  the solver. Re-check after ANY change: `python tools/solver2.py Levels/level_N.tscn`.
- Level 3 exists (the guide says judges play to level 3). A full bot run of it takes ~75 s of play.
- Judges play from a link, so the game needs a **web export**. Web builds run on WebGL 2 (Godot's
  Compatibility renderer); this project is set to Forward+, so test a web export early and check
  that the lighting still looks right.

## Display
480x270 game pixels, 1440x810 window, nearest filtering, 32x32 tiles. Stretch mode
**canvas_items** (Nov 2026, "scale up" + sharper UI): positions and sizes are still in game
pixels, but everything is drawn at the window's real resolution, so text and panels are sharp
while the pixel art keeps its pixels (movement is a bit smoother: sub pixel steps show).
UI font (Nov 22 2026, Nilay: "find a good pixelated font", plus a dyslexia option):
**Departure Mono** (`Assets/fonts/departure_mono/`, a monospace pixel font on an 11 px grid,
Helena Zhang, SIL OFL: credit it). At size 11 one font pixel = one game pixel. Its import has
`subpixel_positioning=0` and `keep_rounding_remainders=false`, so every letter steps the same
whole number of screen pixels (with remainders on, spacing alternated: "ME NU").
**DYSLEXIA FONT** switch (title top left, bottom of the pause menu; `Game.set_dyslexic_font`,
saved in `user://settings.cfg`, which NEW GAME doesn't delete; off by default): OpenDyslexic
(`Assets/fonts/opendyslexic/`, Abbie Gonzalez, SIL OFL), as a FontVariation with letter spacing
-1 (its built-in gaps looked s p a c e d out at our sizes). How: no scene sets a font, so
`Game.apply_font()` sets the project theme's `default_font` (Labels, Buttons) and
`ThemeDB.fallback_font` (draw_string, `UIStyle.font()`) at runtime; the theme file is unchanged,
so the editor previews show Godot's font. Both fonts load at runtime (`UIStyle.pixel_font()`,
`dyslexic_font()`), not preload: a preload fails before the first import.
Sizes in game pixels (x3 on screen): `UIStyle.SMALL` 6, `BODY` 8 (theme default), `HEAD` 11,
`TITLE` 18. PIP's console: `Game.console_font_size()` = 8 for both fonts (both are wider than
Open Sans; at 8 every line fits two rows). StoryBeats' TOO LONG check measures both fonts.
**Dyslexic sizes** (Nov 26 2026, Reyansh: "everything becomes bigger and stuff gets cut off"):
OpenDyslexic is about 1.15x as wide and 1.5x as tall as Departure Mono at the same size, so with
the switch on every size is scaled by `UIStyle.DYSLEXIC_SCALE` 0.8 (`UIStyle.size_scale`, set
in `Game.apply_font`): `UIStyle.fs()` in all code-drawn text (`text()`, `text_width()`), the
theme's default size (`Game.THEME_FONT_SIZE` 8), and every Label / Button font size override
(`_rescale_fonts`; the original is kept in meta "base_font_size", so switching never drifts;
`node_added` catches menus made later). The console keeps its own sizes (`console_font_size`).
The pause and results panels grow from their centre (grow both ways), above the console.
**One menu at a time** (Nov 26 2026, "the menus overlap"): while the pause menu, upgrade panel,
map or results are open, the top right corner (battery counter, UPGRADE, MENU) and the popup
hide (`hud._process`), and the upgrade panel takes the results panel's place like it does the
pause menu's (`_upgrade_from_results`). Menu panels are nearly solid (0.98) so nothing ghosts through.
Tried and rejected: Pixelify Sans, Jersey 10, VT323 (uneven gaps or cramped at our small sizes).
m6x11 (the old font) is still in `Assets/fonts`, unused: it looked chunky because the old
"viewport" stretch forced it to size 16.

## Game rules (level.gd enforces them)
- START pad: stand on it, press **E/Space** to grab the wire. The timer starts with `wire_time`
  seconds (or that room's `room_wire_time`). That's also the most it can hold (Nov 26 2026,
  Reyansh: "max time is capped at start time"): `_max_time()` = `_wire_time()`; there is no
  `max_wire_time` any more.
- Free movement while carrying. The wire is a taut straight line from the LAST pad touched to the
  player's hands; it can't pass through walls, crates, doors or live red tiles, so steps that would
  make it are refused (`wire_reaches()`). It CAN stretch across open space.
- NODE (orange): **press E (or left click) to wrap** (Nov 26 2026, Reyansh: "you have to click to
  redirect").
  **Wording** (Nov 27 2026, team): players CONNECT the wire to a node ("wrap" is only for poles,
  where it's true); an unpowered goal is "the grey pad" (team-art goals show grey until
  powered), a powered one "the lit pad". HUD key label "connect node". Touching one with the wire only makes it READY (`_node_ready`, set in
  `player_moved()`'s pad loop; `hud.set_node_prompt()` bobs an E key next to it and the console
  says "E wrap node"; the first time PIP says `pip_node_press`). E or a click in that state =
  `_touch_pad()`; E anywhere else = reel back. Clicks: `_unhandled_input` stamps
  `_click_at` (msec); a click counts for 150 ms and is used up when it wraps (clicks on buttons
  never get there). PIP's
  autopilot wraps nodes by itself (it can't press E). Goals still connect on touch. The solver
  is unchanged (a route touching a node = the player pressed E there).
  **A node refills the timer** (Nov 26 2026, team: "as long as you're standing on the node the
  timer doesn't go down and resets", tried out as a switch, then kept for good and the switch
  removed): once wrapped, the timer is FULL (`_max_time()`), and while you stand on the node
  the wire is wrapped round (`_paused_node`, `_timer_paused()`), `_tick_timer` keeps it full
  with no time limit; step off and it counts down from full. Walking back onto it (the node
  the wire is wrapped round last) or reeling back onto it fills it up again (`player_moved()`). So `node_time` and `node_hold` are gone (exports, scene values, solver flag
  `--node`): the solver gives every node the full START time. Touch radius 22 px. "Standing on
  it" uses the same test as touching (feet or `BODY_UP` higher), so a node reached from below
  holds too (before Nov 22 2026 it didn't).
- NODE REST (being tried out; dev menu switch `Game.node_rest`, off by default, not saved):
  wire latched on a node (`_anchor_cells[-1]` is a node) and feet within `node_rest_radius`
  (48 px) of it = the timer waits with no limit (`_node_rest()` in `_tick_timer`). The solver
  ignores it (it only makes rooms easier). To make it a real rule, set it on and test the rooms.
- POLE (a steel support pillar with a purple cable ring, map char `B`, tile kind `pole`; was the
  "bend" until Nov 2026): solid for
  feet, not for the wire. Looks: `Assets/images/tiles/pillar.png` (32x64, foot on the tile's
  centre) + `pillar_glow.png` (the ring, glow channel), drawn by `tools/art_pillar.py`;
  `PuzzleTile._make_pillar()` / `_update_pillar()` draw it over the wires, under the player, but
  over him and see-through while he walks behind it. The wire is DRAWN looped round the base
  (Nov 26 2026, team: "make it look like the wire gets wrapped round the pole"): wire.gd
  `add_anchor(p, wrap)` with `level._post_loop()` = Vector3(side, 11, 6) (pillar base, an
  ellipse) or (side, 6.5, 3.5) (the clamp); `_display_points()` draws tangent lines and an arc;
  which way round comes from the TURN DIRECTION (sign of the turn), arriving at
  angle(a) + dir*acos(r/d) and leaving at angle(b) - dir*acos(r/d) (choosing "the outside of the
  bend" picked the wrong side past half a turn); the front of each loop is drawn again over the
  pillar (`_fronts`). Every post's base is also in `wire.posts` (set on grab): a straight stretch
  that would cut through one is drawn bending round its edge (`_around_posts`), so the wire
  never looks like it goes through a post before the rules wrap it at the centre. Rules and solver still use the centre corner. level.gd draws the same picture in the
  editor (`_draw_pillar_preview`). The column covers the tile above the pole. The wire wraps round its centre when it sweeps across it and unwraps when
  you sweep back (`_update_wraps()` / `_swept_over()`: the swung triangle anchor->old hands->new
  hands must contain the pole, with real width). Gives no time. Anchors list = pads AND poles
  (`_anchor_cells` + `_anchor_signs` + `_anchor_turns`), so `_winding()` counts poles too.
  Unwrapping (Nov 26 2026, team: "if you walk more than a circle it keeps wrapping, don't cut
  off"): `_anchor_turns` = how far the wire has turned round each pole (radians, accumulated
  every step); a pole only comes off when that drops back past 0 (and the straight wire is
  clear). It used to come off half way round (the side test flips at 180 degrees too). Past a
  full turn the wire coils (wire.gd draws spiral coils, `COIL_GAP`). The solver's `rewrap()`
  adds `straight_on` (feet past the pole, dot > 0) instead of counting radians: the same answer
  up to 270 degrees round a pole, and its results were identical on all 3 levels. Keep them in step.
- REEL BACK: **E while walking with the wire** (and not on a ready node) pulls you back along it (past each pole) to the last
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
- POWER CELL (a full battery): touch it *while carrying the wire* and it adds `cell_bonus` (0.5 s)
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
- **Menus use real Buttons** (pause: RESUME / UPGRADE / QUIT; results: NEXT LEVEL /
  PLAY AGAIN / UPGRADE; title: START or CONTINUE + NEW GAME; upgrade panel: UPGRADE / CONTINUE).
  Their look is in the project theme (`Assets/ui/theme.tres`, textures `Assets/ui/button_*.png`
  drawn by `tools/art_ui.py`), so new Buttons match on their own. Keys: arrows move the focus,
  E / Space / Enter press it (Game._ready adds E to `ui_accept`). The top right corner always
  has UPGRADE (opens the wire upgrade, shows your batteries, amber + a "!" dot when you can
  buy) and MENU (pause); they have
  `focus_mode` none so Space never presses them while you play. Unpausing is deferred to the
  end of the frame so the E that pressed RESUME doesn't also grab the wire.

## Dungeon parts (Nov 2026: "make it less linear, like a Zelda dungeon")
- Level 1 is a dungeon: tutorial rooms 1-3 (the team's), then the REACTOR HALL hub with three
  wings, two chains you can do in any order:
  - hub reactor ring (crate puzzle) -> the CABLE CLAMP -> COOLANT PUMPS (needs it: `needs the
    clamp` in the solver).
  - CABLE STORE (open) -> its PowerLink `CableStoreDuct` lights the one lamp of the red lamp door
	to the SERVICE DUCT -> REACTOR ACCESS (the team's old room 4).
  Each wing's goal also has a PowerLink UNLOCK to the MAIN DOOR (3 lamps), which opens onto the
  Generator Room finale. Rooms: 13 (halls count), so room_titles / room_wire_time are 13 long.
- Nov 22 2026 rework (Nilay: "the clamp and the fuse don't make sense, they're right next to each
  other"): the fuse is gone from Level 1 (the fuse door became a one-lamp main door), the clamp
  moved from the Cable Store's barrier stash into the reactor ring, so you see it the moment you
  walk into the hub, and the stash was walled up (it was its own room, so the rooms after it
  moved down one: Generator Room is 10-12, walkthrough 1,2,3,7,5,9,10,11,12). Each item now has
  one job, found in one place and used in another. Fuse tiles still work if a level wants them.
- A **hall** = a room with no START and no goal/core (`is_hall()`): never a puzzle, its doors open
  at the start (`_setup_dungeon`), it never sinks barriers.
- Tiles (map char): `fuse` f (pickup), `fuse_door` F (opens if you carry a fuse; no level uses
  them now), `main_door` M (the red lamp door: lamps = UNLOCK links pointing at it, one link = one
  lamp; walking into it shows `popup_lamps` and PIP's `pip_lamps` once), `socket` o, `clamp` k
  (pickup, one per level). Art:
  `tools/art_dungeon.py` (puzzle frames 14-16, palette 18-22). Pickups draw themselves
  (`Scripts/pickup.gd`).
- **PowerLink** (`Scripts/power_link.gd`, @tool Marker2D under a "Links" node): sits on a goal,
  child markers = targets, `action` OPEN / CLOSE / RED_OFF / RED_ON / UNLOCK, `message`,
  `show_camera` (`_glance_at`). Applied in `_solve()` after `_open_exit_doors` (`_apply_links`),
  and quietly by `_power_quietly`. Red floors switched off live in `_red_off`; use `_is_red(c)`.
- **Clamp**: E next to a socket (no wire) drops / takes it (`_try_clamp`); in a socket it's added
  to `_poles`, so the wrap rule is the pole rule. Standing on the socket works too (Nov 25 2026,
  Nilay): `_spot_beside()` finds the nearest free safe spot next to it and `_step_to()` hops
  him there before the clamp (solid) goes in. The solver tries every socket. Near a socket
  without the clamp: `popup_socket_empty` + PIP's `pip_socket_empty` once per level (Level 1
  sets it to "...There's one in the reactor ring.").
- **Ship map** (M): `Scripts/ship_map.gd`, drawn from `level.map_info()`; only in levels with
  halls / fuse doors / main doors / links (`hud.set_map_available`).
- Console: fuse count and clamp icon (hud.gd `set_fuses`, `set_clamp`).

## Movable crates (Nov 22 2026, team: "add movable crates")
- Tile kind `box`, map char `c` (palette frame 23, drawn by `tools/art_crate_icon.gd` from the
  game's own drawing code). `_read_layout()` turns each into floor + a home in `_crate_homes`;
  at runtime each is a `PushCrate` (`Scripts/push_crate.gd`, draws itself: steel with hazard
  stripes, so it never looks like the fixed wooden cargo). In the editor `_crate_preview` draws them.
- Rules (level.gd, "movable crates"): walk straight into one (player.gd `_slide` ->
  `lean_on_crate()`), lean `PUSH_LEAN` 0.14 s, it rolls one tile (`_push_crate`) onto floor, the
  spawn or a red tile, never onto pads, items, cells, sockets, another crate, you or the wire you
  carry (`_wire_crosses`). Solid for feet and wire (`is_solid_for_walk` / `is_solid_for_wire`
  check `_crates` first). Onto a LIVE red tile = `_short_out()`: sparks, it sinks, the tile goes
  in `_grounded` (`_is_red()` says no: walkable, and the wire crosses it). Won't move = a shudder
  + tick, PIP says `pip_crate_stuck` once.
- With team art a movable crate looks like the fixed ones, so `_point_out_crates()` (end of
  `_enter_room`): the first time you enter an unpowered room, PIP's arrow points at each of its
  movable crates, nearest first, max 4 lines (`pip_crate_spot`, then `pip_crate_spot_more`).
  Not while the autopilot drives. (Nov 25 2026, Nilay: "I don't know stuff that can move".)
- R (`_respawn`): `reset_crates(room)` puts the room's crates home (shorted tiles turn red
  again), unless the room has power. In a HALL with crates, R resets them and puts you back at
  the door you came in by (`_entered_at`, else `_dev_spot`), so the reactor ring can't trap you.
- Signals `crate_pushed`, `crate_grounded`; story/tutorial triggers PUSH_CRATE, GROUND_CRATE (at
  the end of both enums). Texts: `popup_crate_grounded`, `popup_crates_reset`, `pip_crate`,
  `pip_crate_ground`, `pip_crate_stuck`. Sound `push.wav` (`tools/sfx_crate.py`, plain Python).
- Solver: `push_configs()` = every layout you can push a room's crates into (BFS, fewest pushes
  first; you start on the START). It checks the wire in the first `--crate-tries` (24) layouts
  AND in every layout that shorts out a new set of red tiles, after a quick "can you walk from
  START to the goal" test (`walk_reaches`). Prints "needs the crates moved: at least n pushes".
  Halls with crates get a plan instead (`hall_plan()`: fewest pushes so every door and item is
  reachable), written to the routes JSON under "halls". The chosen layout is carried on to
  later stages. Crates are only pushed before grabbing the wire (in the game you may push while
  wired). A route's "pushes" = [[x, y, dx, dy], ...].
- Autopilot: resets the room's crates, does the route's pushes (`_push`: walk behind, lean),
  then the wire; hall plans run once, as soon as he can walk into that hall (`_do_hall_plans`).
- The TUTORIAL teaches it (Nov 26 2026): Storage (room 2) has a striped crate at (5,12) on the
  wire's line from the START to the node; tutorial step `Step4PushCrate` (advance PUSH_CRATE)
  asks you to push it before grabbing the wire.
- Level 1 uses: REACTOR HALL (the clamp in a 2 thick red ring, 2 crates: the one under the
  entrance pushed down twice is the way in), CABLE STORE (rebuilt bigger: a red strip across the
  room; short out the one tile (13,26) on the line START -> node; 2 crates, at least 3 pushes;
  lowest timer 1.52 s), COOLANT PUMPS (a crate on the clamp's line). Built by
  `tools/maps/build_level1_crates.py` (from the dungeon map), then the clamp / fuse rework above.

- Nov 26 2026 (Reyansh): **only the special crates move.** The team's wooden crate art tile
  (art source 4, atlas 4:7 in `layout_tileset.tres`) was kind "box", so crates painted with it
  were pushable but looked fixed. It's kind "crate" now (fixed); pushable crates are painted
  with the palette's crate tile (`c`, frame 23) and ALWAYS draw the striped steel look
  (`PushCrate.art` is no longer drawn). Coolant Pumps relied on a wooden crate at (46,19) being
  pushed: it's floor now (the room needs the clamp + one push of its striped crate again).
- **Push animation**: `Assets/images/astronaut/astronaut_push.png` (the team's sheet, 6 x 4
  frames of 32x48: rows down, right, left, up) = animations `push_down` / `push_right` /
  `push_left` / `push_up` in `astronaut_p4_frames.tres`. player.gd plays them while
  `_push_t` > 0 (set to 0.25 s every frame `lean_on_crate()` says he's leaning).

## Making levels in the editor (Nov 22 2026, team: "it should be very easy to create levels")
- Painting is all it takes: each palette tile's `kind` gives it its art and its rules live.
- **Live preview** (Nov 24 2026, team: "like the Geometry Dash editor"): level export
  `live_preview` (on). In the editor `_build_live_preview()` makes the same PuzzleTile /
  PowerCell / Pickup nodes the game makes, under a `LivePreview` node with no owner (never
  saved), rebuilt on every paint. Godot 4.7's TileMapLayer does NOT emit `changed` when you
  paint, so `_watch_painting()` hashes `layout.tile_map_data` 5x a second and rebuilds when it
  changes (the old redraw-on-paint never worked in 4.7). Those three scripts are `@tool` (no PointLight2D in the
  editor). `_tick_live_preview()` (level `_process` in the editor) runs the grate wave;
  main doors show one lamp per UNLOCK link. `LiveMarks` (z 55) draws SPAWN / EXIT / TEST
  START markers and stars on space. With the preview on, the Props layer and the pillar
  preview skip pads (the preview has them). `show_layout_in_editor` now defaults to off.
- **Test start tile** (kind `test_start`, palette frame 24, `tools/art_test_start.py`, no map
  char: `map_from_scene.py` writes it as floor): `_read_layout()` keeps it in `_test_cells`
  and makes it floor. F6 (editor build, not `Game.playing_through`) starts there with earlier
  rooms powered and the intro skipped; it wins over an active TestStart node. 2+ painted = red
  flags + a warning. Kept as nodes on purpose (the team chose this): story beats,
  tutorial steps, hint guides, power links (they hold text or connections).
- **Team art tiles** (Nov 24 2026, team: "update all the assets"): the team's PNGs live in
  `Assets/images/tiles/team/` and are sources 1-7 of the Layout tileset (0 = the plain
  palette): 1 ground (floor), 2 wall (front faces, wall), 3 wall_sides (Claude-made: all 47
  "blob" wall pieces, one light edge where floor touches then dark, `wall_sides.json` lists
  each piece's floor sides), 4 objects (node, goal, start, grey block = crate, small crate =
  box, big 2x2 crate = 4 crate tiles; the purple bend block is left out on purpose; the grey
  block became the unpowered goal, see "Grey goals"), 5-7
  start / goal / node animations (one animated tile each, 0.1 s a frame). Built by
  `tools/build_team_tiles.gd` (keeps the tileset uid). `_read_layout()` stores every
  source > 0 tile in `_art` (with its kind); `_build_visuals()` copies them onto the
  ArtFloor / ArtWalls / ArtProps layers (same tileset, so animations play) and skips our own
  picture there. PuzzleTile `art_from_map` hides its sprite + glow (light, sparks, [E] stay);
  PushCrate `art` draws the painted crate. Rules come only from the kind. The map tools key
  kinds by (source, x, y) (`tileset_kinds()`); map_to_scene writes source 0 only.
  `team/wall.png` is the team's **"Wall-tilemap3d v2"** (each panel has a dark top band, 53/55/59,
  so walls look 3D); the flat "Wall-tilemap v2" isn't used. (A first check wrongly called them
  identical: PIL's getbbox() on an RGBA difference only looks at alpha. Compare pixels.)
  The 47 wall pieces are wall TOPS in the same style: 2 px rim at the floor, the 3D panels'
  shadow steps, then the dark top colour, so side walls continue the panels' top band.
  After the 47 come pieces next to FRONT PANELS (Nov 25 2026, team: "the top edge skirting
  wraps round the corner"): a panel neighbour counts like floor for the rim (from y 16 next
  to a panel's top row, where its skirting is), so the panel's top edge turns the corner and
  runs down to the floor rim. Only combinations the levels use are drawn (`art_wall_sides.py`
  scans Levels/), so after map changes run: art_wall_sides.py, build_team_tiles.gd (Godot
  headless), retile_walls.py. JSON entries have "panel_top" / "panel" lists; level.gd's
  plain-wall fallback ignores those entries.
- **Panel ends** (Nov 25 2026, team: corners where a front panel ends next to a doorway
  corridor): source 8 `wall_caps.png` (`tools/art_wall_caps.py`) = each panel's left / right
  end tile (power strip, windows, computers) with the top band redrawn so the skirting turns
  the corner up the open side (distance field: face from row 18, open side; same steps as the
  team's band). `retile_walls.py` (`_wrap_panel_ends`) swaps a panel end to its cap when the
  tile beside it isn't wall / empty / space, and back when it is. Wall pieces next to a
  panel's top row start their rim at row 16 (`PANEL_EDGE` 18), lining up with the skirting.
- **Level 1 is now only its first 3 rooms** (Nov 26 2026, team: "delete all the other rooms
  except the first 3", and the exit too): Engineering Bay, Storage, Conduit Hall, by
  `tools/keep_rooms.py` (keeps the rooms + a 4 tile wall frame, erases the rest of the map,
  deletes the story beats / tutorial steps / hints / power links of deleted rooms; level-wide
  beats stay; room lists and walkthrough trimmed). **There is no exit**: after the 3 rooms and
  the lights-on cutscene the level can't be finished until the team adds one. The Conduit
  Hall's old corridor towards the Reactor Hall is now a dead end (its door became wall). The
  map now starts at tile (-3, -1): `map_from_scene.py` writes the text map from Godot (0, 0)
  (blank padding) and, for maps left of / above it, an `.origin` file the solver adds back to
  every exported route. The notes below about rooms 4-13 describe the old Level 1.
- **Level 1's fourth room** (Nov 27 2026, the team's layout; Claude only updated what sits on
  it, the map wasn't touched: same 966 tiles, identical rule map): rooms ENGINEERING BAY,
  STORAGE, CONDUIT HALL (pole (20,9), node (20,4), pole (25,4), goal (25,7), door (24-26,10)
  down), SWITCHGEAR ROOM (START (25,16), nodes (28,16) (22,19) (22,26) (29,25), 5 poles, the first
  red floor and blinking grates, goal (25,29), door (24-26,32)), LIFT CORRIDOR (a hall, still
  no exit tile: the level can't be finished until the team paints one). Room 1's goal is now
  (4,20) and Storage's START (7,13); the tutorial arrows and guides follow them. PIP's beats
  Room4Intro (red floor + grates), Room4Grates (REACH_HERE just before the grate column at
  (26,25), where the hint route crosses), Room4Fail (the node refill tip), Room4Done.
  **At 3 s, Conduit Hall and Switchgear have no fair route** (0.08 / 0.12 s lowest without
  the margin); with the first wire upgrade (4 s; rooms 1 and 2 give 4 batteries, it costs 3)
  they leave 0.96 / 0.61 s. Switchgear follows the team's own route (Nov 27 2026, drawn by the
  team): START, round pole (22,16), node (22,19), node (28,16), down the right past the poles,
  node (29,25), node (22,26), goal; `tools/route_choices.json` keeps it.
  START and NODE pads are the animated tiles (sources 5 / 7); goals stay the grey block.
  P during a blocking dialogue (a room's intro) used to start PIP while the astronaut was
  still LOCKED, so every room got force-powered: `autopilot.run()` now waits for
  `hud.is_blocking()` to end first.
- **Hints, judge routes and "needs an upgrade" come from one solver run** (Nov 27 2026, team:
  no Inspector toggle, work it out from the batteries available):
  `python3 tools/solver2.py Levels/level_N.tscn --paths Data/routes/level_N.json --margin 3 --hints`.
  For each stage it tries the START time, then one more wire upgrade at a time, as far as the
  batteries of every EARLIER stage and earlier level pay for (`UPGRADE_COSTS` / `UPGRADE_STEP`
  read from game_state.gd), and stops at the first time whose best route leaves at least
  `MIN_SPARE` 0.25 s. The route gets `upgrades`, `time`, `batteries_before` in the JSON; the
  autopilot walks it, `tools/write_hints.py` turns it into the room's H hint (updates the
  Hints guide that starts on that START, else adds HintRoomN; rooms with a Tutorial guide get
  none), and level.gd `_load_needs()` reads `upgrades` for PIP. `tools/route_choices.json`
  ({"level_1": {"4": ["N(25,20)", ...]}}, nodes in the solver's printed coordinates) makes a
  stage use the team's route; `--route 4=N(..),N(..)` for one run; `--no-upgrades` or a typed
  `--time` = the old fixed time. Takes a few minutes on Level 1.
- **PIP's upgrade tips** (level.gd "rooms that need a longer wire"): after 2 fails in a room
  whose `upgrades` > `Game.wire_upgrades` (then every third fail), instead of the H offer:
  can buy = `pip_needs_upgrade` + the corner UPGRADE button hops (`hud.flash_upgrade`);
  can't = `pip_needs_batteries` ({need}) and, if a powered room still has batteries,
  `pip_redo_room` ({room}, title capitalised) with PIP's arrow on its goal.
- **Cut a room's power** (Nov 27 2026, team: "walk up to an active goal, hold interact to cut the
  wire and retry", just that room): no wire, standing on a lit goal = `hud.set_cut_prompt`
  (E key over the goal, a red ring fills; console "E hold to cut power"); hold E `CUT_HOLD`
  0.9 s = `_cut_room()`: unsolved, fails reset, power LEDs, goal grey, conduit dark
  (`Wire.set_unpowered`), the wire you laid there snaps and is deleted (`Room.cable`, set
  in `_solve`; `_break_cable` = `Wire.snap()` then free), ceiling lights off (the emergency light pulses again by itself),
  hull beacons removed, helmet lamp on, `popup_power_cut`. Doors, barriers and links stay
  open. Kept batteries stay yours (each pays once); the missed ones are still there. PIP:
  `pip_cut_hint` the first time you stand on a lit goal of a room with batteries left,
  `pip_cut_done` after the first cut. Re-powering it runs `_solve` again (upgrade offer
  included) but the lights-on cutscene only plays once (`_ship_powered`).
- **Walls fade into empty map** (Nov 26 2026, team: the hard edge where wall met unpainted
  map): neighbour type "void" (art_wall_sides `FADE`: the wall top steps down to the
  background colour over ~24 px). retile_walls marks '' neighbours as void; space stays wall.
- **More space for rooms 7, 8, 9** (Nov 25 2026, team: Cable Store, Main Breaker, Reactor
  Access "need much more space", walls modelled on theirs): `tools/move_rooms.py` moved the
  Generator Room area + exit 2 right / 3 down and Reactor Access 3 down, rigidly (the doors to
  rooms that stay went with them; halls grow to meet them: Main Breaker 2x2 -> 4x5, Service
  Duct 4x2 -> 4x5). Solver results identical, every room / marker kept its room, autopilot ok.
  New front walls use the "mixed" panel style (`retile_walls.mixed_columns()`, copied from the
  panels the team painted: windows-panel top row, a no-bolt strip broken by a window or a
  monitor between pointed strip ends, strip bottoms, their caps). Painted panels are kept
  while valid (`panel_valid()`: floor right under the panel's bottom row), else cleared.
  **Coolant Pumps (stage 5) has 0 solver solutions** since the team's crate edit there
  (fixed + pushable crates at (37-46, 16-20), before the moves too): check it in the game;
  the autopilot force-powers it until it solves again.
- **Conduit Hall door** (Level 1 room 3, Nov 25 2026, team: "make that 3 tall"): door tiles
  (12, 8)-(12, 10) (was 2 tall), and (13, 8) became floor so it opens into the room. Solver
  results identical (lowest timers and solution counts), autopilot plays the level clean.
  The team also made the two Storage crates at (9, 8) and (5, 10) pushable (map char c).
- **Plain strip panel** (Nov 25 2026, team: the power strip panel "without the lightning
  bolt"): source 9 `wall_strip.png` (`tools/art_wall_strip.py`: wall.png's panel A with only
  the bolt painted out in the panel colour; the strip keeps its gap and pointed ends. The bolt
  = the yellow shape that doesn't reach the end columns). Kind wall, 6x3. `retile_walls.py`
  keeps it where painted (`PANELS`), wraps its ends like panel A's, and side walls line up
  with its skirting. It isn't picked automatically for new walls.
- **Wooden crates are fixed** (team, Nov 26 2026: "only striped crates move"): objects.png (4, 7)
  has kind "crate". `build_team_tiles.gd` says so too now (a rebuild on Nov 26 had quietly set it
  back to "box", turning all 7 wooden crates in Storage into pushable carts: fixed the same day).
  Rebuilding the tileset recreates sources 1-9 from that script: change kinds there, not only
  in the TileSet editor, or the next rebuild undoes them.
- **Tile index**: `docs/tile_index.html` (`tools/tile_index.py`), a picture of every Layout palette
  tile (layout_tiles) with its kind, map letter and what it does (descriptions in `WHAT`).
- **Grey goals** (Nov 25 2026): objects.png's grey block (1, 7) is the goal WITHOUT power
  (kind "goal"). Every team-art goal shows grey until its room is powered, then the animated
  blue goal (`_show_goal_art()`, called from `_build_visuals`, `_solve` and `_power_quietly`).
- **Animated pads** (Nov 25 2026): `tools/use_team_pads.py` repaints START / GOAL / NODE pads
  with the animated tiles (sources 5-7, same kinds, rules unchanged). Done for all 3 levels
  (Levels 2 and 3 on Nov 25 2026, Nilay: "change all the old designs to the new ones").
- **Old walls are gone** (Nov 24 2026, team: "delete all the old walls"): every wall in
  levels 1-3 is a team tile on the Layout, painted by `tools/retile_walls.py` (front panels
  where a wall is 3 tall above non-door floor, runs of 2+ columns: 6 = power strip, 4 = power,
  10 = computers / windows, else stretched; everything else the wall piece for its 8
  neighbours, where '', wall and space count as not floor). Painted walls show exactly as
  painted. A plain grey palette wall borrows the same piece at draw time (`_wall_piece()`);
  the old auto wall faces, roofs and the light strip under them were removed from level.gd.
  The rule maps (solver input) were identical before and after. Godot's terrain brush was
  tried and dropped: it treats empty space past the map edge as floor (rims facing nothing).
- **Spaced-out rooms** (Nov 25 2026, team: "space out the rooms so the walls look smoother"):
  `tools/space_rooms.py` (Level 1 only, the team asked for just that one) doubled 6 seams of wall
  (2 columns, 4 rows; map 56x47 -> 58x51). A seam runs edge to edge through wall / empty /
  doorways only and zig-zags only inside tiles solid in both lines, so rooms move rigidly: the
  solver's lowest timers were identical before and after (same `--margin`), every room kept its
  number and every marker its room. Doorways on a seam got a corridor floor tile (so rooms 0, 2,
  3, 4, 5 grew by 2 to 8 tiles). Left thin (no seam can reach them, doors block every path): the
  wall between the Cable Store area and the room below it on the right (2 rows), and the
  interlocking corner of the room left of the Generator Room. Walls inside one area (barrier
  stages) are never thickened. **Tile coordinates in older notes for Level 1 (like (13,26)) are
  from before this.** Levels 2 and 3 not spaced yet (the script fixes all their thin walls).
- **Room labels** (editor only, `show_room_info`, `_update_room_info()` / `_draw_room_info()`):
  every room shows its number, name, START time ("level's" = the default) and crate count, and
  red warnings (needs a START, 2 STARTs, needs a GOAL). Labels step down so they never overlap.
- Paint a new room and `room_titles` / `room_wire_time` grow to match by themselves (a new
  "ROOM n" / 0). They never shrink (no data lost); if a room is added in the middle, the labels
  show at once which names moved.

## Judge mode and PIP's autopilot
- Title, top left: JUDGE MODE toggle (`Game.judge_mode`, saved) + LEVEL n buttons. In a level,
  P (action `autopilot`, judge mode only) = `start_autopilot()`; R restarts as in normal mode
  (Nov 25 2026, Nilay: a judge wants to retry a room themselves); after 2 fails PIP says
  `pip_hint_judge` ("Press P").
- `Scripts/autopilot.gd`: walks to the next room (`autopilot_target()`: current unsolved room,
  then the level's `walkthrough` export, then number order), fetches / places the clamp,
  collects fuses, steps on airlock pads, drifts across space (`walk_path()` has drift edges),
  grabs the wire and steers to every point of the solver's route (`player.autopilot` +
  `auto_dir`, so the normal rules run). A jump between route points = a drift (`_drift`: line
  up, straight push). Blocked diagonally by a corner = one axis at a time (`_free_axis`).
  While `autopilot_on`: timer frozen, no zaps, no O2 drain, no PIP shutdown meter, blocking
  beats don't block. Falls back to `autopilot_force_solve()` (+ a warning: treat it as a bug).
- While walking a route, `autopilot_wraps` switches off `_update_wraps` and the route's `wraps`
  list decides the pillar wraps (`autopilot_sync_wraps`). Some solver routes only graze a
  pillar's centre (cross product exactly 0 on the 4 px lattice); steering a pixel off misses it.
- Blinking grates (Nov 23 2026, Nilay: in judge mode PIP walked over lit grates and nothing
  happened): before stepping from floor onto a run of grates, `_wait_for_grates` waits until
  `_grates_clear` says he can cross the whole run at walking speed while each grate is dark
  (`level.blinker_live_in(c, dt)` predicts the wave, `GRATE_MARGIN` 0.15 s either side). He
  then walks in the gap behind the wave. Still no zaps during the autopilot, as a safety net.
- `autopilot.debug = true` prints each step and where he got stuck.
- Routes: `Data/routes/level_N.json` from `python tools/solver2.py Levels/level_N.tscn --paths
  Data/routes/level_N.json --margin 3` (keyed by START tile; `clamp` = the socket used; `wraps`
  = [point index, pads touched, [[pole x, pole y, side]...]] where the wraps change). Godot
  lists `.json` as a resource, so exports include them without a filter.
  **Regenerate after any map change.** Test: a bot that only presses R (see Verification below);
  it must print no "Autopilot couldn't walk room" warnings.

## Spacewalk rules (Level 2)
- `hull` = floor outside the ship, `space` = open space (nothing drawn: the Starfield shows). A room
  containing either is an OUTSIDE room: `space_light` instead of `darkness`, space music, no
  emergency/ceiling lights (blinking hull beacons appear when powered), and an **oxygen** meter
  (`o2_seconds` + `Game.o2_bonus()`), refilled on entering a new section, on powering it and on
  respawn. Out of O2 = fail.
- Feet can't stand on space. Walking (cardinally) into a hull edge asks `drift_landing()`: if there
  is hull straight ahead (and the wire won't snag), the player **drifts** (`State.DRIFT`,
  `drift_speed` 150) until fully back on hull. No landing = refused with red dots + PIP tip.
- A door with no wall beside it is a **gangway** (catwalk that slides out). The whole door
  group counts (`_is_gangway()`): a door 3+ tiles long in a wall is never a gangway, even its
  middle tile (Nov 25 2026: the 3 tall Conduit Hall door's middle tile was drawn as a catwalk). A crate with no floor or
  hull beside it is floating debris. A cell with open space on both opposite sides floats in space
  (that tile counts as space).
- `airlock` pad: stepping on it (once) closes the door behind, vents the air, opens the outer door
  and starts the oxygen meter (`_cycle_airlock`).

## The core (Level 3)
- `core` tile (map char `@`): a round socket, solid for feet and wire. A room with a core has no
  goal: it's powered when the wire (START -> pads -> hands) winds a full turn round the core
  (`_winding()`: sum of `angle_to` of each straight piece, seen from the core; `_check_loop()` in
  `player_moved()`). The socket shows a yellow ring = how far round (`PuzzleTile.show_loop`), with a
  tick at the START's direction: the loop closes when your hands cross that line. Then
  `_plug_into_core()` flies the loose end from the hands into the socket (0.18 s, Nov 25 2026,
  Nilay: the end used to hang in the air) and calls `_solve()`.
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
  `drift_landing()`...). Standing still he faces the way he last walked (`_show_idle()`, Nov 26
  2026): an "idle_<dir>" animation if the sprite has one, else the team's "idle" (drawn facing
  down-right; mirrored for down-left), else that direction's walk held on `STAND_FRAME` 1 (feet
  together). A stop within 0.12 s of a diagonal walk keeps the diagonal (`_since_diag`).
- `Scripts/game_state.gd` (autoload **Game**): level order (`LEVELS`, found at start by
  `_find_levels()`: every `Levels/level_<n>.tscn`, in number order, numbers 1, 2, 3 with no gap;
  `ResourceLoader.list_directory` so it works in the web build too. A new level = save the next
  `level_<n>.tscn` in `Levels/`, nothing else to edit; the level warns if its `level_number`
  doesn't match its file name), results, the save file
  (`save_game()` / `load_game()`, `user://save.cfg`, `has_save()`, `continue_level()`), `o2_bonus()`,
  `go_to_level()`, `first_time(tip)` (PIP explains things once), `story_values()` for `{cells}` /
  `{o2_bonus}` / `{o2_per_cell}` in story text.
- `Scripts/juice.gd` (autoload **Juice**): game feel only, never rules. `hitstop(s)` (Engine.time_scale
  0, restored by a timer that ignores time scale; the newest call restores it), `shake(0..1, s)`
  (trauma: offset = MAX_SHAKE px x trauma squared, on the active Camera2D's `offset`, whole pixels;
  level.gd `_shake_cam(duration, px)` converts to it), `punch_scale(node, Vector2 mult, s)`
  (remembers the node's real scale in meta), `flash(item)` (modulate 4 back to normal in 0.08 s),
  `pitch()` (0.92 to 1.08). Used in level.gd: zap = hitstop 0.12 + `player.flash()` + sparks;
  room powered 0.07, all powered 0.1, boots save / crate shorts a tile 0.05, PIP's cut 0.06;
  `player.squash(mult)` on grab, node, reel-back stop, crate push, pickup, drift push-off and landing
  (+ `_dust_at`); `_play(n, pitch)` varies the sounds in `PITCH_VARIED`, and power cells charged on
  one try rise in pitch (+0.07 each). `player.gd` keeps the squashing sprite on his feet
  (`sprite.position.y = _sprite_y * sprite.scale.y`). Pickups pop in `pickup.gd` / `power_cell.gd`.
- `Scripts/puzzle_tile.gd`: runtime visuals for pads/doors/gangways/airlock/barriers (glow, sparks,
  arrows; barriers shudder and sink, `open_door(delay)`).
- `Scripts/power_cell.gd`: the collectible battery (draws itself, collect/restore animations).
- `Scripts/wire.gd`: carried wire + floor conduits (Line2D + `Shaders/wire_current.gdshader`).
- `Scripts/hud.gd` + `Scenes/hud.tscn`: a fixed **console** along the bottom (`CONSOLE_H` 48 px;
  level.gd frames the room ABOVE it, so the HUD never covers play): PIP's CRT face + his speech
  (`say(lines, speaker, blocking, point_at)`, typewriter; when quiet it shows the tutorial
  objective dimmed), ship power LEDs, cell counter, O2 bar (outside) or key reminders. The wire
  timer is a 5-LED bar floating above the astronaut's head. Also: tutorial/PIP arrows, toasts
  (top), fades, results with stars + batteries to spend, pause menu, the wire upgrade panel
  (`Scripts/upgrade_panel.gd`, made in code, `hud.open_upgrade()`), cutscene film bar (top).
- **UI look** ("clean sci-fi", Nov 22 2026; replaced the green terminal at the team's request:
  "polished, modern ish"): dark glass panels with rounded corners and a thin cyan edge
  (`StyleBoxFlat`), white text, amber for names / keys / things to buy, green = done, red =
  danger. Everything lives in `Scripts/ui_style.gd` (`UIStyle`: colours, font sizes, `box()`,
  `draw_box()`, `text()`, `draw_key()`, `draw_led()`) and the theme (`Assets/ui/theme.tres`:
  Button, Panel, PanelContainer, Label, RichTextLabel). Code-drawn UI (console, timer, upgrade
  panel, map, keycaps, dev menu) uses UIStyle, so a colour changed there changes everywhere.
  PIP's face stays a little green screen (his character). Toasts slide in, the pause menu fades
  in, results scale in. The old frame PNGs (`frame_*.png`, `button_*.png`) are no longer used.
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
- **RPG = batteries and the WIRE UPGRADE** (Nov 26 2026, Reyansh: "remove the tree and make it
  a time on the wire upgrade button, batteries are the currency, 3, 5, 7"). Replaced the skill
  tree (SkillManager, SkillDef, Data/skills, skill_tree.gd/.tscn are deleted).
  All in **Game** (`game_state.gd`): `batteries` (to spend), `wire_upgrades` (0..3),
  `UPGRADE_COSTS` [3, 5, 7], `UPGRADE_STEP` 1 s (was 0.5 until Reyansh asked for +1), `keep_battery(level, cell)` (called by
  level.gd `_solve` for every cell kept in that room; each cell pays out ONCE ever, keys
  "level:x,y" in `_paid_out`, so replays can't farm), `upgrade_cost()` (-1 = all bought),
  `can_upgrade()`, `buy_upgrade()` (saves), `wire_bonus()`, signal `batteries_changed`.
  Rules read it through `_wire_time()` (START + bonus, capped by `_max_time()`) and
  `_max_time()` (= `_wire_time()`): each upgrade adds 1 s to what the START gives, which is
  also the most the timer holds (3 -> 4 -> 5 -> 6 s). `_cell_bonus` is now plain.
  **The panel** (`upgrade_panel.gd`, class UpgradePanel, built in code with UIStyle): batteries
  badge, "+n from that room", WIRE TIMER now > next, three lamps (costs under them), a hint,
  UPGRADE (n) / CONTINUE buttons (focus on the useful one), U or Esc closes, plays `star.wav`
  (the results star chime) when it opens. It comes up after a room you power ONLY when you can
  buy the next upgrade (`Game.can_upgrade()`; `_solve` -> `await hud.offer_upgrade(paid,
  wire_time)`, after doors and links, before the lights-on cutscene) and not while PIP's
  autopilot plays; the first time PIP says `pip_upgrade`.
  **Battery counter**: top right, left of UPGRADE (`hud._battery_chip`, `_draw_battery_chip`):
  an amber pill with the battery icon and `Game.batteries`; it hops when the count changes.
  **Wire bar** (over his head, `hud._draw_timer`): one lamp per second of the cap
  (`set_timer(..., cap)`, cap = `_max_time()`): 3 / 4 / 5 lamps, and over 5 s one lamp per 2 s
  (6 s = 3 long lamps). `TIMER_PX` 8 game pixels per second, so a longer wire is a longer bar;
  the lamp in use drains smoothly. Also U, the corner UPGRADE button, and the
  UPGRADE buttons on the pause menu and the results screen. The panel pauses the game.
  Saving: finishing a level and every upgrade call `Game.save_game()` (section [upgrades]); the title screen shows
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
  Under NODE REST: **WIRE UPGRADES 0 1 2 3** (Nov 27 2026, Reyansh: "select their battery
  upgrade level"): sets `Game.wire_upgrades` and emits `batteries_changed`, so the wire time,
  its cap and bar change at once (even while carrying). Saved with the game's next save.
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
  **In use since Nov 25 2026: `astronaut_p4_frames.tres`**, built by `tools/art_astronaut_p4.py`
  from the team's `astronautp4.png` (6 x 5 frames of 32 x 48: walk down, down-right, right,
  up-right, up; the left walks come from the mirrored `astronautp4_flipped.png`). Walking
  diagonally plays `walk_<up|down>_<side>`. The team's second sheet `astronautp4_idle.png`
  (6 x 2 of 32 x 48) gives idle (row 0, frames 0, 1, 4, 5: Nilay cut the middle two), shock (row 1, frames 0-3) and burnt (row 1,
  frames 4-5, holds on 5). Only `carry` still comes from the old `astronaut.png` (36 px tall vs
  45: it looks smaller). Each new frame gets 8 px of AtlasTexture margin below so the feet line
  up with the old frames (sprite y stays -18).

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
- `Juice.hitstop` sets `Engine.time_scale` to 0: during it there are NO physics frames, and normal
  timers and tweens wait. Bots that measure time by counting physics frames just pause; to watch
  a hitstop, sample on `process_frame` with `Time.get_ticks_msec()`.
- `get_meta(key, null)` counts as "no default" and errors when the key is missing: check
  `has_meta()` first.
- Running a test script with `--script` loads before autoloads are registered: don't use the
  project's class names (Astronaut, Game...) in such scripts at all, not even
  `Astronaut.State.LOCKED` (use the number: FREE 0, WIRED 1, LOCKED 2, DRIFT 3).
- **UI text** in the menus uses real Buttons and `KeyHint` (`Scripts/key_hint.gd`: drawn keycaps +
  a label, sizes itself) instead of "[E] text" strings: console key reminders, pause controls,
  title controls. Results use three stat tiles (Time / Cells / Retries).
- Unused, safe to delete: `Scripts/hint_sign.gd`, `Scenes/hint_sign.tscn` (if present).
  `Scenes/main.tscn`, `Scripts/main.gd` and `electric_box.*` are the old prototype.

## Python tools
`tools/` (ignored by Godot via `.gdignore`) has the level solver, map/lighting previews, the map
writer and the art/sound generators. See `tools/README.md`. After editing a room, run
`python tools/solver2.py Levels/level_N.tscn`: it reads the map AND the level's Rules numbers
and lists routes with their "lowest timer" (the least time left on the way; carried over from
pad to pad) and whether every power cell can be charged in time. `--paths f.json --margin 3`
exports routes a bot can replay in the game. On a Mac the command is `python3`. Rooms with
movable crates take longer (Level 1: about 80 s); see "Movable crates".
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
Nov 22 2026 (Claude, at the team's request): movable crates (push_crate.gd, the push / short out /
reset rules, the solver's crate layouts and hall plans, the autopilot's pushes, the palette icon
and push.wav), the reworked Level 1 hub and Cable Store and the Coolant Pumps crate (solver-checked,
then walked by the autopilot in the real game), the editor's room labels and growing room lists,
the dev menu, and the "clean sci-fi" UI restyle (ui_style.gd, theme, HUD, title, skill tree,
map; canvas_items stretch for sharp text). The UI font is Godot's built-in Open Sans.
Nov 22 2026 (Claude, at Nilay's request): the clamp / fuse rework of Level 1 (no fuse, the clamp in
the reactor ring, the one-lamp door to the Service Duct, the lamp door and empty socket messages),
the NODE REST switch in the dev menu, and the node hold fix (a node reached from below holds too).
Nov 22 2026 (Claude, at Nilay's request): picked the pixel font Departure Mono and the DYSLEXIA
FONT switch with OpenDyslexic (both fonts by other people, free under the SIL Open Font License:
list them in the copyright checklist with their OFL.txt; Claude only wired them in and set the
letter spacing).
Nov 23 2026 (Claude, at Nilay's request): the skill point notification (popup, pinging dot on
SKILLS, PIP's upgrade line, worded from Nilay's own) and PIP's autopilot timing the blinking
grates. Also: the level scenes moved to `Levels/` and the game finds them by file name, so a
new level needs no code change. And the game feel ("juice", `Scripts/juice.gd`): hitstop on the
zap and on powering a room, a trauma camera shake, squash and stretch on the astronaut, popping
pickups, pitch-varied sounds.
Nov 24 2026 (Claude, at the team's request): the editor's live preview (painted tiles come alive
in the editor) and the paintable test start tile with its palette icon (`tools/art_test_start.py`).
Nov 25 2026 (Claude, at the team's request): spaced out Level 1's rooms (`tools/space_rooms.py`).
Nov 26 2026 (Claude, at the team's request): idle facing the last walking direction, the wire
drawn looped round poles (and coiling when you walk round one again and again, with the new
unwrap rule), walls fading into empty map, and Level 1 cut down to its first 3 rooms.
Nov 25 2026 (Claude, at Nilay's request): the clamp drops in while you stand on its socket, PIP
points out movable crates, judge mode's P key for PIP (R restarts), the boss loop's wire end
plugs into the core, and the team's animated pads in Levels 2 and 3. Also the draft demo video
script (`docs/demo_video_script.md`). The team's new astronaut sheets (`astronautp4.png`,
`astronautp4_idle.png`) are the TEAM's art; Claude only mirrored it for the left walks and wired it into the game.
Nov 24 2026: the team's new art (ground, front walls, objects, start / goal / extra time
animations) is the TEAM's own (from their Drive; record who drew it); Claude only cut it into
tiles, gave each tile its rule and wired it in. Claude drew the side, bottom and corner walls to
match (`tools/art_wall_sides.py`, pixel by pixel in Python, in the team's colours).
Nov 27 2026 (Claude, at the team's request): the solver's per-room wire upgrade search, the
route choice file and the hint writer (`tools/write_hints.py`), PIP's upgrade tips, and the
hold-E cut on a lit goal (the cut idea and the Switchgear route are the team's).
Nov 27 2026 (Claude, at the team's request): for the team's new Level 1 layout (the layout
itself is the team's), the room names, PIP's lines for the Switchgear Room, the tutorial arrow
fixes, the H hint routes and the judge mode routes (from the solver), and the animated pads.
Nov 26 2026 (Claude, at the team's request): nodes refill the timer and keep it full while you
stand on them (the team's idea; Claude wrote the rule and updated the solver).
Nov 26 2026 (Claude, at Reyansh's request): the skill tree replaced by batteries as money and the
three step WIRE UPGRADE (game_state.gd, upgrade_panel.gd, the end of room prompt), 3 s START and
0.5 s batteries in every level. The costs (3, 5, 7), the step (1 s) and the START time are the
team's numbers.
The tools in `tools/` were also written by Claude. Gameplay was playtested by automated scripts
that drive the real game with simulated key presses.
