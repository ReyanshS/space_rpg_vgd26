# ---------------------------------------------------------------------------
# level.gd: reads the map you paint, makes it look nice, and runs the rules.
#
# The big picture
#   1. You paint the level on the "Layout" TileMapLayer with simple tiles
#      (floor, wall, start, goal, node, pole, red, crate, door, spawn, exit,
#      cell, hull, space, airlock, barrier, and more: see the palette).
#      In the editor every tile comes alive as you paint it (the live preview:
#      glowing pads, bobbing cells, blinking grates), and a "test start" tile
#      marks where F6 drops you.
#      Each tile in the palette carries a hidden label called "kind"
#      (set in Assets/images/tiles/layout_tileset.tres -> Custom Data).
#   2. _read_layout() turns the painted tiles into a Dictionary:
#      tile position -> kind, e.g. Vector2i(3, 4) -> "node".
#   3. _build_visuals() uses that to draw the pretty version on 3 extra layers
#      (Ground, Walls, Props): tall wall panels, roof edges, floor variety, hull plates.
#      In the editor this re-runs every time you paint, so you see the result live.
#   4. _build_rooms() finds the rooms (floor areas separated by walls, doors
#      and barriers). Each room is one puzzle STAGE. Doors lead to the next
#      room. Barriers (cargo on a lift) split one room into several stages:
#      touching barrier tiles are a group that sinks into the floor as soon as a
#      stage next to it is powered. Stages joined by barriers form one area:
#      the camera roams across it, and a later stage can wrap its wire round the
#      nodes of the stages you already powered there. So powering
#      something really changes the room for the next puzzle.
#   5. During play the player calls player_moved() every frame and that function
#      checks the rules: red tiles, power cells, new room, touching pads...
#   6. Lighting: the ship starts dark (CanvasModulate). Glowing things (wires,
#      pad halos, floor guides) use light channel 2, lit by one flat "glow
#      light" (see light_fx.gd). Each room has a red emergency light, and
#      ceiling lights that switch on when you power it.
#      When every room has power, a short cutscene (_power_tour) takes the
#      camera back through all the rooms, lighting each one up at full power.
#   7. The level announces what happens with signals (wire_grabbed, pad_touched,
#      room_solved, ...). The tutorial, the story (PIP's lines) and the floor
#      guides listen to those. The level doesn't need to know they exist.
#
# The wire rules
#   - Press E on the START pad to grab the wire. The timer starts right away.
#   - You walk freely, but the wire is a tight straight line from the last pad
#     you touched to your hands. It can't pass through walls, crates or red
#     tiles. If a step would make it, you just can't take that step.
#   - The START gives you wire_time seconds. The timer can never go above
#     max_wire_time (not even with batteries).
#   - NODE: wraps the wire and adds node_time seconds. Standing on it holds the
#     timer, but only for node_hold seconds: you can't rest there for ever.
#   - NODE REST (a switch in the dev menu, off unless you turn it on): while the
#     wire is latched on a node (the node is the last pad it touched) and you stay
#     within node_rest_radius of it, the timer waits as long as you like. Time to
#     look round the room. (_node_rest)
#   - POLE (purple post): solid, you walk round it. When the wire sweeps across
#     it, the wire wraps round it like a rope round a post (_update_wraps).
#     Walk back the way you came and it unwraps. It gives no time; it lets the
#     wire go round corners it couldn't otherwise.
#   - GOAL: powers the stage and opens its doors / moves its barriers.
#   - Timer hits 0, or you step on a red tile (with or without the wire)
#     -> the wire snaps and the stage resets, but you stay where you are
#     (pushed off the red tile). Walk back to the START, or press R to jump
#     there. The wire itself can't be stretched over red tiles.
#   - Blinking grates switch on and off in a wave (grate_cycle, grate_live,
#     grate_wave). Lit = they zap your feet. The wire is fine over them.
#
# Power cells (the reward for a clever route)
#   - "cell" tiles become PowerCells. Touch one while carrying the wire to charge
#     it. You keep it once the room is powered; if you fail, it comes back.
#   - At the exit you get up to 3 stars: finish, every cell, few retries.
#     Game (game_state.gd, an autoload) remembers the results, and every cell
#     gives you extra oxygen on later spacewalks.
#
# Spacewalk (Level 2)
#   - "hull" = floor outside the ship, "space" = open space (stars show through).
#     A room with hull or space in it is an outside room: sunlit, no ceiling
#     lights, its own music, and an oxygen meter that drains while you're there.
#   - Your feet can't go onto space. Walk into a hull edge and, if there's a
#     plate straight ahead to land on, you DRIFT across (player.gd, State.DRIFT).
#     The wire can stretch across open space.
#   - A door with no wall beside it is a gangway: a catwalk over space that slides
#     out when the room before it is powered.
#   - "airlock" pad: stand on it and the airlock cycles: the door behind you
#     shuts, the air hisses out, the outer door opens and the oxygen meter starts.
#
# The core (Level 3)
#   - A "core" tile is a round machine socket. A room with a core has no goal
#     pad: you power it by wrapping the wire all the way round the core.
#   - How we know: add up the angle each straight piece of wire sweeps round
#     the core, as seen from the core (_winding). A full turn = TAU radians
#     (360 degrees). A ring on the socket shows how far round you are.
#   - In Level 3, PIP's body docks on the cores (rogue_pip.gd). That script
#     isn't part of the rules: it listens to the level's signals, and it can
#     call cut_wire(), set_alert(), hold() and let_go().
#
# Dungeon parts (so a level isn't just one room after another)
#   - A room with no START and no goal (a hall) never locks anything: its doors
#     are open from the start. Halls join the puzzle rooms like a hub.
#   - FUSE (pickup) and FUSE DOOR: walk over a fuse to pick it up (the console
#     counts them). Walk into a fuse door with one and it opens, using it up.
#     (No level uses fuses right now. Level 1 uses lamp doors instead.)
#   - MAIN DOOR (the red lamp door): needs power from somewhere else. Each
#     PowerLink with the action "unlock" that points at it lights one of its
#     lamps; all lit = it opens. One link = a door with one lamp. Walk into it
#     and the popup says how many lamps are lit (popup_lamps).
#   - POWER LINKS (power_link.gd): a marker on a room's goal with markers on
#     tiles anywhere in the level. When that room gets power, those tiles change:
#     doors open or close, barriers sink or rise, red floors switch off or on,
#     main doors get a lamp. The camera glances over so you see what changed.
#   - The CLAMP (pickup): a cable clamp you carry. Press E next to a SOCKET tile
#     to drop it in (or take it back). In a socket it works like a pole: the
#     wire wraps round it. Puzzles that need a corner where there isn't one.
#     Walk up to a socket without the clamp and PIP says where to look
#     (pip_socket_empty).
#   - M opens the ship map (hud.gd), drawn from map_info().
#
# Movable crates (push_crate.gd; tile kind "box", map char c)
#   - Walk straight into one and lean on it for a moment: it rolls one tile, if
#     there's floor behind it. It blocks your feet and the wire, like a fixed crate.
#   - Pushed onto a live red tile, it shorts the tile out and sinks: a steel plate
#     you and the wire can cross (_grounded).
#   - Carrying the wire, you can't roll a crate through the wire itself.
#   - R puts the crates of the room you're in back where they started, unless
#     that room already has power (reset_crates). In a hall, R only does that.
#
# The RPG side (skill points and the skill tree; see skill_manager.gd)
#   - Finishing a level for the first time gives `skill_points` (an export, so
#     harder levels can give more). Replays give nothing (_finish_level).
#     You're told: a popup, a pinging dot on the SKILLS button
#     (hud.notify_skill_points), and the first time, PIP's pip_skill_points.
#   - You spend them on the skill tree (T or the SKILLS button, at any time).
#     Skills change the rules through _wire_time(), _cell_bonus(), _shock() and
#     the player's speed_mult, and apply the moment you unlock them
#     (_apply_skills listens to SkillManager.skills_changed).
#   - No puzzle ever needs a skill: skills only make rules easier, and the
#     solver checks every room with no skills at all.
# ---------------------------------------------------------------------------
@tool
class_name WireLevel
extends Node2D

# Signals: announcements other nodes can listen to. The tutorial and the story
# listen to most of these; the floor guides listen to room_solved and hint_shown.
signal room_entered(index: int)
signal room_solved(index: int)
signal room_restarted(index: int)            # you failed and the room reset
signal wire_grabbed(index: int)              # you picked up the wire in room `index`
signal pad_touched(kind: String, index: int) # the wire reached a node / goal, or wrapped a "pole"
signal level_completed
signal cell_collected(index: int)            # a power cell got charged in room `index`
signal empty_cell_touched                    # you touched a cell without the wire (only sent once)
signal hint_shown(index: int)                # the player pressed H in room `index`
signal drift_started(index: int)             # you pushed off into open space
signal airlock_cycling(index: int)           # the airlock in room `index` started its sequence
signal ship_lighting_up                      # every room has power: the lights-on cutscene starts
signal all_rooms_powered                     # ...and the cutscene is over (you can move again)
signal item_picked(kind: String, index: int) # you picked up a "fuse" or the "clamp" in room `index`
signal door_unlocked(index: int)             # a fuse door or main door opened (index = the room it leads to)
signal crate_pushed(index: int)              # a movable crate rolled one tile in room `index`
signal crate_grounded(index: int)            # a crate shorted out a red tile in room `index`

const TILE := 32
const DIRS4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

# How close (in pixels, from a pad's centre) counts as touching it. A tile is 32 px.
# We measure from his feet and from a point BODY_UP pixels higher: the sprite is
# taller than a tile, so when he looks like he's on a pad his feet can be just below it.
# tools/solver2.py uses the same numbers, so change them there too.
const START_RADIUS := 20.0
const NODE_RADIUS := 22.0
const GOAL_RADIUS := 22.0
const BODY_UP := 10.0
const CELL_RADIUS := 14.0
const AIRLOCK_RADIUS := 12.0
const MAX_DRIFT := 640.0       # pixels: no hull within this distance = you can't push off

const WALL_TEX := "res://Assets/images/tiles/wall_face.png"
const FLOOR_TEX := "res://Assets/images/tiles/floor.png"
const ROOF_TEX := "res://Assets/images/tiles/roof.png"
const PUZZLE_TEX := "res://Assets/images/tiles/puzzle_tiles.png"
const HULL_TEX := "res://Assets/images/tiles/hull.png"
# Which picture in puzzle_tiles.png belongs to which kind.
const PUZZLE_FRAME := {"start": 0, "goal": 1, "node": 2, "pole": 3, "discharge": 4,
	"blinker": 5, "crate": 6, "door": 7, "airlock": 11, "barrier": 12, "core": 13,
	"fuse_door": 14, "main_door": 15, "socket": 16}
const DOOR_KINDS := ["door", "fuse_door", "main_door"]
const PICKUP_RADIUS := 16.0    # how close you walk to a fuse or the clamp to pick it up
const SOCKET_REACH := 30.0     # how close you stand to a socket to drop / take the clamp with E
const GANGWAY_FRAME := 9
const SRC_WALL := 0
const SRC_FLOOR := 1
const SRC_ROOF := 2
const SRC_PUZZLE := 3
const SRC_HULL := 4
const SOUNDS := ["grab", "hum", "node", "bend", "shock", "snap", "powerup", "door", "complete", "tick",
	"pickup", "hiss", "puff", "clank", "alarm", "fanfare", "pulse", "push"]

## The TileMapLayer you paint on. If empty, a child called "Layout" is used.
@export var layout: TileMapLayer
## Editor only: the tiles you paint come alive, like in the game. Pads glow,
## batteries bob, grates blink in their wave, pillars stand on the poles. It's
## the same code the game uses (puzzle_tile.gd, power_cell.gd, pickup.gd).
@export var live_preview := true:
	set(value):
		live_preview = value
		if is_inside_tree():
			_queue_rebuild()
## Editor only: label every room with its number, name, START time and any
## problems (no START, no goal...), so you can see how the game reads your map.
@export var show_room_info := true:
	set(value):
		show_room_info = value
		if _room_info:
			_room_info.queue_redraw()
## Editor only: show the flat palette icons on top of the finished look too
## (handy to check which tile is which; off = see only the real look).
@export var show_layout_in_editor := false:
	set(value):
		show_layout_in_editor = value
		_apply_layout_visibility()

@export_group("Level")
## Which level this is. It must match the file name: Levels/level_2.tscn is
## level 2 (game_state.gd finds the levels by their file names).
@export var level_number := 1
## Shown in the pause menu.
@export var level_name := "ENGINEERING DECK"
## Shown on the results screen.
@export var complete_message := "Power's back on in this part of the ship."
## The order PIP's autopilot (judge mode) does the rooms in: room numbers as in
## Room Titles (1 = the first). Rooms with nothing to solve are skipped. Empty =
## every room with a START, in number order.
@export var walkthrough: PackedInt32Array = []
## Skill points for finishing this level the first time. Give harder levels more.
@export var skill_points := 2

@export_group("Rules")
## Seconds you get from the START pad.
@export var wire_time := 4.0
## Seconds a NODE adds to the timer.
@export var node_time := 3.0
## The timer never goes above this (START, nodes and batteries all stop here).
@export var max_wire_time := 5.0
## Standing on a NODE holds the timer for this many seconds, then it runs again.
@export var node_hold := 1.5
## Only with NODE REST switched on in the dev menu: how close (in pixels, a tile
## is 32) you must stay to the node the wire is latched on for the timer to wait.
@export var node_rest_radius := 48.0
## A room's own START time, one number per room in walking order (like Room
## Names). 0 or missing = use wire_time. Lets an easy room (a tutorial) or a
## long one get more time without changing the whole level.
## Check with:  python tools/solver2.py Levels/level_1.tscn
@export var room_wire_time: PackedFloat32Array = []
## Seconds a power cell adds to the wire's timer when you grab it with the wire.
@export var cell_bonus := 2.0

@export_group("Lighting")
## How dark the ship is before a room gets power (1,1,1 = no darkness at all).
@export var darkness := Color(0.2, 0.21, 0.3)
## How bright it is outside the ship, where the sun lights the hull.
@export var space_light := Color(0.5, 0.54, 0.7)
## Brightness of a room's lights once it's powered.
@export var room_light_energy := 0.75
## How bright the inside of the ship gets once every room has power
## (after the lights-on cutscene). Should be lighter than `darkness`.
@export var full_power_light := Color(0.42, 0.43, 0.52)
## The red tint inside the ship during an alert (Level 3: PIP is trying to shut
## everything down). Something else turns the alert on and off with set_alert().
@export var alert_light := Color(0.4, 0.15, 0.17)

@export_group("Blinking grates")
## Seconds for one full on + off cycle of a blinking grate.
@export var grate_cycle := 2.4
## How many of those seconds it's lit (and zaps you).
@export var grate_live := 1.2
## Each column of grates lights up this many seconds after the one to its left,
## so the light runs across the floor like a wave and you can walk in the gap.
## Positive: the wave runs right-to-left. Negative: left-to-right. 0: all together.
@export var grate_wave := 0.36

@export_group("Spacewalk")
## Seconds of oxygen for each hull section. Every power cell charged in earlier
## levels adds Game.O2_PER_CELL more.
@export var o2_seconds := 75.0

@export_group("Room names")
## Shown for a moment when you walk into each room (in the order you reach them).
## Stages joined by barriers count as one room: only the first one's name shows.
@export var room_titles: PackedStringArray = [
	"ROOM 1",
	"ROOM 2",
	"ROOM 3",
	"ROOM 4",
]

# Things PIP says because of the rules, not the story. Each plays once at most.
# (Story lines are StoryBeat nodes under the "Story" node, see story_beat.gd.)
# You can write {cells}, {o2_bonus} or {o2_per_cell} and the real number goes in.
# Keep each one short enough for two lines in the console (about 72 letters).
@export_group("PIP's rule lines")
## You failed the same room twice and it has a hint route.
@export var pip_hint := "Stuck? Press H and I'll show you the way."
## Spacewalk: your oxygen dropped below 30%.
@export var pip_o2_low := "Your air's getting low. Power this section and the relay will top you up."
## You walked towards open space with no hull plate ahead to land on.
@export var pip_no_landing := "Nothing to land on that way. Your boots only let go with a plate ahead."
## The first time you power a room with a battery charged.
@export var pip_cell_kept := "That battery's yours now. Each one you keep adds {o2_per_cell} seconds of suit air."
## The first time a charged battery goes back because you failed.
@export var pip_cell_lost := "That battery's back. You only keep them once you reach the blue pad."
## The first time the wire stops you walking.
@export var pip_strain := "The wire can't go through that. Wrap it round a node for a new angle."
## The first time you grab a wire that can use a node from an earlier stage (PIP points at it).
@export var pip_shared := "That node from the last machine is still live. Wrap this wire round it."
## After a fail, when there's no way back to the START without crossing red tiles or grates.
@export var pip_stranded := "No safe way back from there. Press R and I'll bring you to the start."
## The first time you earn skill points (the results screen of a level that has
## a next one). One entry = one speech bubble.
@export var pip_skill_points: PackedStringArray = [
	"Oh! Some power's restored, so you can upgrade your equipment now.",
	"Restore more power and you can upgrade more gear. Press T to look.",
]

# The short messages that pop up at the top of the screen.
@export_group("Popup texts")
@export var popup_power_on := "POWER ON"
@export var popup_relay_online := "RELAY ONLINE"
@export var popup_all_online := "ALL SYSTEMS ONLINE"
## {bonus} = the seconds a battery adds (cell_bonus).
@export var popup_cell_bonus := "+{bonus} SECONDS ON THE WIRE"
@export var popup_zap := "ZAP!"
@export var popup_overload := "WIRE OVERLOADED"
@export var popup_out_of_air := "OUT OF AIR"
@export var popup_pip_cut := "PIP CUT THE POWER"
@export var popup_wire_gone := "WIRE'S GONE. WALK BACK OR PRESS R"
@export var popup_hint := "FOLLOW THE ARROWS"
@export var popup_outer_door := "OUTER DOOR OPEN"
@export var popup_stranded := "NO WAY BACK? PRESS R"
@export var popup_boots := "YOUR BOOTS SAVED YOU"
@export var popup_fuse := "GOT A FUSE"
@export var popup_fuse_used := "FUSE FITTED. DOOR OPEN"
@export var popup_fuse_locked := "LOCKED. IT NEEDS A FUSE"
@export var popup_clamp := "GOT THE CABLE CLAMP"
## Walking into a lamp door that's still shut. {lit} and {needs} = its lamps.
@export var popup_lamps := "LOCKED. LAMPS LIT: {lit} OF {needs}"
## Walking up to a clamp socket without the clamp.
@export var popup_socket_empty := "THIS SOCKET TAKES THE CABLE CLAMP"
@export var popup_crate_grounded := "SHORTED OUT. SAFE TO CROSS"
@export var popup_crates_reset := "CRATES PUT BACK"

# What PIP says about the dungeon parts (each one only once).
@export_group("PIP's dungeon lines")
## The first fuse you pick up.
@export var pip_fuse := "A fuse. One of the amber doors takes these."
## You walk into a fuse door without a fuse.
@export var pip_fuse_locked := "That door needs a fuse. There'll be one lying around somewhere."
## Judge mode: offered after two fails in a room (instead of the hint line).
@export var pip_hint_judge := "Stuck? Press P and I'll walk you through it."
## Judge mode: when the autopilot takes over, and when it hands back.
@export var pip_autopilot_start := "Hands off the controls. I've got this one."
@export var pip_autopilot_done := "There. Your turn. R again if you want me to do the next one."
## You pick up the clamp.
@export var pip_clamp := "A cable clamp. Press E by a purple socket to set it down."
## The first time you put the clamp in a socket.
@export var pip_clamp_placed := "Now the wire wraps round it, like a pillar. E takes it back out."
## The first time you walk up to a socket without the clamp (say where it is).
@export var pip_socket_empty := "That socket takes a cable clamp. Have a look round for one."
## The first time you walk into a lamp door that's still shut.
@export var pip_lamps := "Each lamp on a red door is a room that has to get power first."
## The first time you push a movable crate.
@export var pip_crate := "That's it. Keep leaning on a crate and it rolls one tile."
## Walking into a room with crates that move: PIP's arrow points at each one.
## The first line is for the first crate, the second for every other one.
@export var pip_crate_spot := "See that crate? It's not bolted down. Walk into it to push it."
@export var pip_crate_spot_more := "That one rolls too."
## The first time a crate shorts out a red tile.
@export var pip_crate_ground := "It shorted the grate out. You and the wire can cross that tile now."
## The first time a crate won't move (something behind it).
@export var pip_crate_stuck := "Stuck? R puts this room's crates back where they started."

# The last level only: when you reach the exit, the camera flies out into space
# and the whole ship fires its engines and leaves (_fly_away), then the results.
@export_group("Ending")
## What PIP says while the engines warm up, and as the ship jumps away.
@export var ending_lines: PackedStringArray = ["Engines are warm. Hold on to something.", "Next stop, home."]
## Which way the ship flies off the screen.
@export var ending_direction := Vector2.RIGHT


# An inner class: a little bundle of data describing one room.
class Room:
	var index := -1
	var cells: Array[Vector2i] = []
	var start := Vector2i(-1, -1)
	var goal := Vector2i(-1, -1)
	var pads: Array[Vector2i] = []      # nodes and the goal
	var doors: Array[Vector2i] = []
	var neighbors: Array = []
	var bounds := Rect2i()              # keeps the camera inside the room
	var solved := false
	var is_exit := false
	var conduit: Wire = null            # the floor cable from goal to door
	var outside := false                # has hull / open space: a spacewalk area
	var airlock := Vector2i(-1, -1)     # the airlock pad, if this room is an airlock
	var cycled := false                 # this airlock has been used
	var fails := 0                      # failed tries here (PIP offers a hint after 2)
	var power_cells: Array[Vector2i] = []
	var full_power := false             # lit up by the lights-on cutscene
	var area_id := -1                   # stages joined by barriers/catwalks share an area...
	var area_bounds := Rect2i()         # ...and the camera can roam across all of it
	var core := Vector2i(-1, -1)        # a CORE socket: wrap the wire round it instead of a goal

	## The spot that powers this room: its GOAL pad, or its CORE. (-1, -1) = none.
	func target() -> Vector2i:
		return goal if goal.x >= 0 else core


# --- map data
var _kinds := {}               # Vector2i -> "floor" / "wall" / "node" / ...
var _floating_cells: Array[Vector2i] = []   # power cells out in open space
var _rect := Rect2i()          # the area that has painted tiles
var _ground: TileMapLayer
var _walls: TileMapLayer
var _props: TileMapLayer
var _hull_edges: Node2D        # draws the thickness of the hull plates
var _pillar_preview: Node2D    # editor only: draws the support pillars on pole tiles
var _live_root: Node2D         # editor only: the live preview (real pads, cells, pickups)
var _live_marks: Node2D        # editor only: markers for tiles the game never draws (spawn, exit...)
var _live_grates := {}         # editor only: tile -> PuzzleTile of each blinking grate
var _map_hash := 0             # editor only: a fingerprint of the painted map (to spot painting)
var _map_check := 0.0          # editor only: seconds until we look at the fingerprint again
var _test_cells: Array[Vector2i] = []   # painted "test start" tiles (F6 starts there)
var _art := {}                 # tile -> [source, atlas coords, alternative, kind]: the team's art tiles
var _art_floor: TileMapLayer   # the team's floor tiles, as painted
var _art_walls: TileMapLayer   # the team's walls (front faces, sides, corners), as painted
var _art_props: TileMapLayer   # the team's pads and crates (animated ones animate by themselves)
static var _wall_pieces := {}  # which neighbours are floor (bits) -> that wall piece in wall_sides.png
var _rebuild_queued := false

# --- rooms
var _rooms: Array[Room] = []
var _room_of := {}             # tile -> Room
var _door_rooms := {}          # door tile -> the rooms it joins
var _tiles := {}               # tile -> PuzzleTile node
var _open_doors := {}          # door tile -> true once opened
var _spawn := Vector2i.ZERO
var _current_room: Room

# --- the wire you're carrying
var _wire: Wire = null
var _wire_room: Room
var _anchor_cells: Array[Vector2i] = []   # pads and poles the wire is wrapped around, in order
var _anchor_signs: Array[float] = []      # for each anchor: which way the wire turns round it (poles only, else 0)
var _last_anchor := Vector2.ZERO          # pixel position the tight wire starts from
var _prev_feet := Vector2.ZERO            # where you stood last time player_moved() ran (for wrapping)
var _poles: Array[Vector2i] = []          # every pole tile in the level
var _paused_node := Vector2i(-1, -1)      # node you're standing on (timer held)
var _node_hold_left := 0.0                # how much longer that node holds the timer
var _time_left := 0.0
var _tick_accum := 0.0
var _strain_cd := 0.0

# --- power cells, progress and results
var _cells := {}                          # tile -> PowerCell
var _cells_pending: Array[Vector2i] = []  # charged on this try (lost if you fail)
var _cells_banked := 0                    # kept for good
var _cell_tip_shown := false
var _play_time := 0.0
var _retries := 0
var _hints_used := 0
var _hints_shown := {}                    # Room -> true
var _hint_offered := {}                   # Room -> true
var _rooms_powered := 0
var _rooms_with_goal := 0

# --- spacewalk
var _o2_on := false
var _o2 := 0.0
var _o2_max := 1.0
var _o2_warned := false
var _o2_beep := 0.0
var _drift_warn_cd := 0.0
var _drift_tip_shown := false
var _beacons: Array = []                  # [light, dot, phase, room]: blinking hull lights
var _beacon_flare := {}                   # Room -> time until its beacons flash together
var _barrier_groups: Array = []           # {"tiles": [...], "rooms": [...]}: cargo that moves together
var _group_of := {}                       # barrier tile -> index in _barrier_groups
var _wire_pads: Array[Vector2i] = []      # the pads the wire you're carrying can use
var _blinkers: Array[Vector2i] = []       # blinking grate tiles
var _reel_tween: Tween                    # the reel-back pull, while it's happening
var _still_time := 0.0                    # how long you've stood still holding the wire
var _last_safe := Vector2.INF             # the last spot you stood on safely (for after a zap)
var _stranded := false                    # after a fail: no safe path back to the START
var _stranded_check := 0.0

# --- RPG
var _boots_used := {}                     # Room -> how many zaps your boots already shrugged off there

# --- the core (Level 3)
var _alert := false            # red alert: the ship's tinted red, the boss music plays
var _holds := 0                # how many other nodes asked the level to wait (hold / let_go)

# --- dungeon parts (see "Dungeon parts" at the top)
var _red_off := {}             # red tiles a power link switched off: tile -> true
var _fuses := 0                # fuses you're carrying
var _has_clamp := false        # you're carrying the cable clamp
var _clamp_at := Vector2i(-1, -1)   # the socket the clamp is in ((-1, -1) = none)
var _clamp_post: Node2D        # the clamp standing in its socket (drawn by pickup.gd)
var _pickups := {}             # tile -> Pickup node (fuses and the clamp still lying around)
var _sockets: Array[Vector2i] = []
var _visited := {}             # Room -> true once you've walked in (for the ship map)
var _main_groups: Array = []   # main doors: {"tiles": [...], "needs": n, "lit": n}
var _main_group_of := {}       # main door tile -> index in _main_groups
var _locked_msg_cd := 0.0      # don't repeat "it's locked" every frame
var _socket_tip_shown := false # PIP said where the clamp is (once per level)

# --- movable crates (push_crate.gd)
const PUSH_LEAN := 0.14        # seconds you lean on a crate before it rolls
var _crate_homes: Array[Vector2i] = []   # where the crates start (read from the map, editor too)
var _crate_list: Array[PushCrate] = []
var _crates := {}              # tile -> PushCrate standing there (solid)
var _grounded := {}            # red tile -> PushCrate that shorted it out (now a plate)
var _crate_preview: Node2D     # editor only: draws the crates on the map
var _room_info: Node2D         # editor only: the room labels (_draw_room_info)
var _lean_cell := Vector2i(-1, -1)   # the crate you're leaning on...
var _lean_dir := Vector2i.ZERO       # ...which way...
var _lean_time := 0.0                # ...for how long...
var _lean_frame := -10               # ...and the last physics frame you did
var _lean_refused := false           # this lean already got its "won't move" shudder
var _entered_at := {}                # Room -> where you last walked in (for R in a hall)
var _crates_shown := {}              # Room -> true once PIP has pointed out its movable crates

# --- judge mode: PIP walks the room for you (autopilot.gd)
## True while the autopilot has the controls: no timer, no zaps, keys ignored.
var autopilot_on := false
var autopilot_wraps := false    # PIP is walking a solver route: the route decides the pillar wraps
var _autopilot: Autopilot

# --- playtesting (TestStart marker + F6, or the dev menu)
## The room a TestStart marker or the dev menu put you in (-1 = normal start). The story,
## tutorial and rogue PIP read this to catch up with the rooms you skipped.
var test_room := -1
## Skip PIP's level intro (the marker said so, or the dev menu).
var test_skip_intro := false

# lights-on cutscene
var _cutscene := false         # true while the cutscene moves the camera
var _cut_cam := Vector2.ZERO   # where the cutscene camera looks (a Tween moves it)
var _flying := false           # the ending: the camera is out in space, the ship flies off
var _ship_powered := false     # every room has power: the inside of the ship is brighter
var _env_tween: Tween          # the tween changing the darkness tint (so two never fight)

# --- state
var _busy := false             # true during win/lose animations: ignore input
var _complete := false
var _leaving := false
var _dialogue_lock := false    # PIP is talking and the player has to read
var _input_cooldown := 0.0     # ignore keys for a moment (so one E press doesn't do two things)
var _cam_pos := Vector2.ZERO
var _sfx := {}
var _music := {}               # "ship" / "space" -> AudioStreamPlayer
var _music_tweens := {}
var _music_now := ""
var _music_override := ""      # set_music_override(): music chosen by a cutscene, not by the room
var _tile_root: Node2D
var _conduit_root: Node2D
var _wire_root: Node2D

# --- lighting
var _dark: CanvasModulate     # tints the whole level dark (or sunlit outside)
var _glow_light: PointLight2D  # one flat light that only lights glowing things (channel 2)
var _room_lights := {}         # Room -> Array of PointLight2D (off until powered)
var _emergency: Array = []     # [light, room] pairs: red lights that pulse until powered
var _light_t := 0.0

var player: Astronaut
var hud: GameHUD
var camera: Camera2D


# ===================================================================== setup

func _ready() -> void:
	if layout == null:
		layout = get_node_or_null("Layout") as TileMapLayer
	if layout == null:
		push_error("WireLevel: add a TileMapLayer child called 'Layout' and paint the level on it.")
		return
	_build_visuals()
	_apply_layout_visibility()
	if Engine.is_editor_hint():
		# Re-draw the pretty version whenever someone paints on the Layout layer.
		if not layout.changed.is_connected(_queue_rebuild):
			layout.changed.connect(_queue_rebuild)
		return
	add_to_group("level")      # lets the tutorial / guides find us with get_first_node_in_group
	_check_level_number()
	_ensure_input_actions()
	_build_rooms()
	_setup_darkness()
	_spawn_runtime_tiles()
	_spawn_power_cells()
	_build_conduits()
	_setup_room_lights()
	_setup_space()
	_setup_audio()
	player = get_node_or_null("Player") as Astronaut
	hud = get_node_or_null("HUD") as GameHUD
	camera = get_node_or_null("Camera2D") as Camera2D
	if player == null or hud == null:
		push_error("WireLevel needs child nodes 'Player' (player.tscn) and 'HUD' (hud.tscn).")
		set_physics_process(false)
		set_process(false)
		return
	player.level = self
	player.position = center_of(_spawn)
	_last_safe = player.position
	_current_room = _room_of.get(_spawn)
	hud.dialogue_blocking.connect(_on_dialogue_blocking)
	hud.results_next.connect(func() -> void: _leave(level_number + 1))   # no next level = title screen
	hud.results_again.connect(func() -> void: _leave(level_number))
	hud.can_block = can_pause_for_dialogue
	hud.set_level_info("LEVEL %d: %s" % [level_number, level_name])
	hud.set_cells(0, _cells.size())
	hud.set_power(0, _rooms_with_goal)
	_setup_dungeon()
	_visited[_current_room] = true
	hud.set_judge(Game.judge_mode)
	_apply_skills()                        # skills you unlocked earlier...
	SkillManager.skills_changed.connect(_apply_skills)   # ...and ones you unlock mid level
	_update_hint_label.call_deferred()     # after the floor guides know their rooms
	_apply_test_start()
	if camera:
		camera.make_current()
		_update_camera(0.0, true)
	_update_environment(true)
	_announce_room()
	hud.fade_rect.color.a = 1.0
	hud.fade_in(0.6)


## Painting fires "changed" for every tile. Instead of rebuilding many times in
## one frame, we remember that a rebuild is needed and do it once, at the end.
func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild_now.call_deferred()


func _rebuild_now() -> void:
	_rebuild_queued = false
	_build_visuals()


func _apply_layout_visibility() -> void:
	if layout == null:
		return
	if Engine.is_editor_hint():
		layout.visible = true
		layout.z_index = 50
		layout.self_modulate = Color(1, 1, 1, 0.45 if show_layout_in_editor else 0.0)
		# (you can still paint on it while it's see-through: Godot shows the
		# tile under your mouse, and the live preview shows the result)
	else:
		layout.visible = false     # in the game you only see the pretty layers


func _ensure_input_actions() -> void:
	_add_key_action("map", [KEY_M])
	# Backup in case these actions are missing from Project Settings > Input Map.
	_add_key_action("interact", [KEY_E, KEY_SPACE])
	_add_key_action("restart", [KEY_R])
	_add_key_action("hint", [KEY_H])
	_add_key_action("pause", [KEY_ESCAPE])


func _add_key_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ===================================================================== playtesting (TestStart)

## A TestStart marker (test_start.gd) that's switched on, or null.
## Only counts when you run this level scene from the editor (F6): exported
## games don't have the "editor" feature, and Game.playing_through is true
## whenever the game itself loaded the level (F5 from the title).
func _active_test_start() -> TestStart:
	if not OS.has_feature("editor") or Game.playing_through:
		return null
	for child in get_children():
		if child is TestStart and child.active:
			return child
	return null


## Start the playtest at the TestStart marker, or in the room the dev menu
## picked (dev_menu.gd, Game.dev_room). Every room before it is powered quietly
## (no cutscenes, no PIP lines): lights on, doors open, cargo sunk.
## The story, tutorial and rogue PIP read `test_room` and catch up themselves.
func _apply_test_start() -> void:
	if Game.dev_room >= 0:
		var index := Game.dev_room
		Game.dev_room = -1                  # only this one load
		for r in _rooms:
			if r.index == index and index > 0:
				_start_in_room(r, _dev_spot(r), true, true)
		return
	# A painted "test start" tile wins: paint it, press F6, you start there.
	if not _test_cells.is_empty() and OS.has_feature("editor") and not Game.playing_through:
		if _test_cells.size() > 1:
			push_warning("%d test start tiles are painted: using the one at %s. Erase the others." % [_test_cells.size(), _test_cells[0]])
		var tr: Room = _room_of.get(_test_cells[0])
		if tr == null:
			push_warning("The test start tile isn't in a room - starting at the spawn.")
			return
		_start_in_room(tr, center_of(_test_cells[0]), true, true)
		return
	var ts := _active_test_start()
	if ts == null:
		return
	var at := to_local(ts.global_position)
	var r: Room = _room_of.get(cell_of(at))
	if r == null:
		push_warning("TestStart isn't on the floor of a room - starting at the spawn.")
		return
	_start_in_room(r, at, ts.skip_earlier_rooms, not ts.play_intro)


## Puts the player at `at` in room r, as if they had just got there.
func _start_in_room(r: Room, at: Vector2, skip_earlier_rooms: bool, skip_intro: bool) -> void:
	test_room = r.index
	test_skip_intro = skip_intro
	player.position = _nearest_safe_spot(at)
	_last_safe = player.position
	_current_room = r
	if skip_earlier_rooms:
		for o in _rooms:
			if o.index < r.index and not o.is_exit:
				_power_quietly(o)
	if r.outside and (_o2_on or skip_earlier_rooms):
		_o2_on = true                       # you're outside: the airlock was "used" already
		_o2_max = o2_seconds + Game.o2_bonus()
		_refill_o2()
	player.set_lamp(not r.solved)
	hud.set_power(_rooms_powered, _rooms_with_goal)
	print("Playtest starts in room %d (%d rooms before it powered)." % [r.index + 1, _rooms_powered])


## Where the dev menu drops you in room r: on its START pad. A room without one
## (an airlock) puts you just inside the door you came in by.
func _dev_spot(r: Room) -> Vector2:
	if r.start.x >= 0:
		return center_of(r.start)
	var best := r.cells[0]
	var best_d := INF
	for door in r.doors:
		var came_from := false
		for o in _door_rooms.get(door, []):
			if o != r and o.index >= 0 and o.index < r.index:
				came_from = true
		if not came_from:
			continue
		for c in r.cells:
			var d := Vector2(c - door).length()
			if d < best_d and (kind_at(c) == "floor" or kind_at(c) == "hull"):
				best_d = d
				best = c
	return center_of(best)


## For the dev menu: the rooms you can jump to, in walking order, as
## [room index, name] pairs. Rooms with a START, and airlocks. It works on a
## level that was loaded but never added to the scene tree (its _ready hasn't run).
func dev_checkpoints() -> Array:
	if layout == null:
		layout = get_node_or_null("Layout") as TileMapLayer
	if layout == null:
		return []
	_read_layout()
	_build_rooms(true)
	var out: Array = []
	for r in _rooms:
		if r.index < 0 or r.is_exit or (r.start.x < 0 and r.airlock.x < 0):
			continue
		var title := room_titles[r.index] if r.index < room_titles.size() else "ROOM %d" % (r.index + 1)
		out.append([r.index, title])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return out


## A skipped room: everything a win would change, but instantly and silently.
func _power_quietly(o: Room) -> void:
	o.solved = true
	if o.airlock.x >= 0:
		o.cycled = true
		_o2_on = true
		_o2_max = o2_seconds + Game.o2_bonus()
	if o.target().x >= 0:
		_rooms_powered += 1
	for c in [o.goal, o.start, o.core]:
		var t: PuzzleTile = _tiles.get(c)
		if t:
			t.powered = true
	_show_goal_art(o.goal, true)
	if o.conduit:
		o.conduit.set_powered()
	if o.outside:
		_light_hull(o)
	else:
		for pair in _emergency:
			if pair[1] == o:
				pair[0].energy = 0.0
		for l in _room_lights.get(o, []):
			l.visible = true
			l.energy = room_light_energy
	_open_exit_doors(o, true)
	_apply_links(o, true)
	# a playtest that starts past a fuse or main door: those are open already,
	# and the clamp is in your pocket if it was lying in a room you skipped
	for d in o.doors:
		if (kind_at(d) == "fuse_door" or kind_at(d) == "main_door") and not _open_doors.has(d):
			for other in _door_rooms.get(d, []):
				if other != o and other.index > o.index:
					_open_door_tiles(_door_group(d), true)
	for c in _pickups.keys():
		if _room_of.get(c) == o and _pickups[c].kind == "clamp":
			_take_pickup(c, true)


# ===================================================================== dungeon parts
# Halls, fuses and fuse doors, main doors, power links and the clamp. See
# "Dungeon parts" at the top of this script for what each one does.

## A hall: a room with no START and no goal. Nothing to solve, so it never
## locks anything: its doors are open from the start. Halls join puzzle rooms
## like the hub of a dungeon.
func is_hall(r: Room) -> bool:
	return r.start.x < 0 and r.target().x < 0 and r.airlock.x < 0 and not r.is_exit


func _setup_dungeon() -> void:
	for r in _rooms:
		if is_hall(r):
			_open_exit_doors(r, true)
	_build_main_groups()
	# a level with halls, special doors or power links gets the map (M)
	var dungeon: bool = _rooms.any(is_hall) or not _main_groups.is_empty() \
		or not _power_links().is_empty() or _kinds.values().has("fuse_door")
	hud.set_map_available(dungeon)


## Door tiles side by side (of the same kind) are one door: they open together.
func _door_group(c: Vector2i) -> Array[Vector2i]:
	var kind := kind_at(c)
	var out: Array[Vector2i] = [c]
	var i := 0
	while i < out.size():
		for d in DIRS4:
			var n := out[i] + d
			if kind_at(n) == kind and not out.has(n):
				out.append(n)
		i += 1
	return out


func _open_door_tiles(tiles: Array[Vector2i], quiet := false) -> void:
	for i in tiles.size():
		var d := tiles[i]
		if _open_doors.has(d):
			continue
		_open_doors[d] = true
		var t: PuzzleTile = _tiles.get(d)
		if t:
			t.open_door(i * 0.05)
	if not quiet:
		_play("door")


## Main doors: count how many "unlock" power links point at each one. That's
## how many lamps it has, and how many parts of the deck must get power first.
func _build_main_groups() -> void:
	_main_groups.clear()
	_main_group_of.clear()
	for c in _kinds:
		if _kinds[c] != "main_door" or _main_group_of.has(c):
			continue
		var tiles := _door_group(c)
		for t in tiles:
			_main_group_of[t] = _main_groups.size()
		_main_groups.append({"tiles": tiles, "needs": 0, "lit": 0})
	for link in _power_links():
		if link.action != PowerLink.Action.UNLOCK:
			continue
		for target in link.target_cells(self):
			if _main_group_of.has(target):
				_main_groups[_main_group_of[target]]["needs"] += 1
	for g in _main_groups:
		_show_main_lamps(g)


func _show_main_lamps(g: Dictionary) -> void:
	for tile in g["tiles"]:
		var t: PuzzleTile = _tiles.get(tile)
		if t:
			t.set_lamps(g["lit"], g["needs"])


## Every PowerLink in the level (power_link.gd puts them in this group).
func _power_links() -> Array:
	return get_tree().get_nodes_in_group("power_link") if is_inside_tree() else []


## The power links that start in room r (their marker sits on one of its tiles).
func _links_from(r: Room) -> Array:
	return _power_links().filter(func(l: PowerLink) -> bool: return _room_of.get(cell_of(to_local(l.global_position))) == r)


## Room r just got power: every power link starting there does its job.
## Not quiet: the camera glances at each place that changed, so you see it.
func _apply_links(r: Room, quiet := false) -> void:
	for link in _links_from(r):
		var cells: Array[Vector2i] = link.target_cells(self)
		if cells.is_empty():
			continue
		for c in cells:
			_link_effect(link.action, c, quiet)
		if not quiet:
			if link.message != "":
				hud.show_toast(link.message, 2.5)
			if link.show_camera:
				await _glance_at(center_of(cells[0]))
				if not is_inside_tree(): return


func _link_effect(action: int, c: Vector2i, quiet: bool) -> void:
	var kind := kind_at(c)
	match action:
		PowerLink.Action.OPEN:
			if kind == "barrier":
				var g: Dictionary = _barrier_groups[_group_of[c]]
				var tiles: Array[Vector2i] = []
				for t in g["tiles"]:
					if not _open_doors.has(t):
						_open_doors[t] = true
						tiles.append(t)
				if not tiles.is_empty():
					_move_barriers(_room_of.get(c, _current_room), tiles, quiet)
			elif DOOR_KINDS.has(kind):
				_open_door_tiles(_door_group(c), quiet)
		PowerLink.Action.CLOSE:
			var tiles: Array[Vector2i] = []
			if kind == "barrier":
				tiles.assign(_barrier_groups[_group_of[c]]["tiles"])
			elif DOOR_KINDS.has(kind):
				tiles = _door_group(c)
			for t in tiles:
				if _open_doors.has(t) and not _box_on(t):
					_open_doors.erase(t)
					var pt: PuzzleTile = _tiles.get(t)
					if pt:
						pt.close_door()
			if not quiet and not tiles.is_empty():
				_play("clank")
		PowerLink.Action.RED_OFF, PowerLink.Action.RED_ON:
			var off: bool = action == PowerLink.Action.RED_OFF
			for t in _red_region(c):
				if off:
					_red_off[t] = true
				else:
					_red_off.erase(t)
				var pt: PuzzleTile = _tiles.get(t)
				if pt:
					pt.set_live(not off)
			if not quiet:
				_play("powerup" if off else "shock")
		PowerLink.Action.UNLOCK:
			if not _main_group_of.has(c):
				return
			var g: Dictionary = _main_groups[_main_group_of[c]]
			g["lit"] += 1
			_show_main_lamps(g)
			if g["lit"] >= g["needs"]:
				_open_door_tiles(g["tiles"], quiet)
				if not quiet:
					door_unlocked.emit(_room_index_beyond(g["tiles"][0]))
			elif not quiet:
				_play("node")


## Is the astronaut standing on tile c? (A closing door or rising barrier
## never closes on top of him.)
func _box_on(c: Vector2i) -> bool:
	return player != null and Rect2(Vector2(c * TILE), Vector2(TILE, TILE)).grow(6).has_point(player.position)


## Every red tile joined to c (touching sides): one red floor switches as a whole.
func _red_region(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if kind_at(c) != "discharge":
		return out
	out.append(c)
	var i := 0
	while i < out.size():
		for d in DIRS4:
			var n := out[i] + d
			if kind_at(n) == "discharge" and not out.has(n):
				out.append(n)
		i += 1
	return out


## The room on the far side of a door tile from the room you're in.
func _room_index_beyond(door: Vector2i) -> int:
	for r in _door_rooms.get(door, []):
		if r != _current_room:
			return r.index
	return -1


## A short cutscene: the camera glides to `pos`, waits so you can see what
## changed there, and glides back to you. (Like the lights-on cutscene, it
## sets _cutscene so the camera stops following the player.)
func _glance_at(pos: Vector2) -> void:
	if camera == null or _flying:
		return
	var back := _cam_pos
	_cutscene = true
	_cut_cam = back
	var tw := create_tween()
	tw.tween_property(self, "_cut_cam", pos, clampf(back.distance_to(pos) / 500.0, 0.3, 0.9)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if not is_inside_tree(): return
	await get_tree().create_timer(0.9).timeout
	if not is_inside_tree(): return
	var tw2 := create_tween()
	tw2.tween_property(self, "_cut_cam", back, clampf(back.distance_to(pos) / 500.0, 0.3, 0.9)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw2.finished
	if not is_inside_tree(): return
	_cutscene = false


## Walking about: pick up fuses and the clamp, open fuse doors you bump into,
## and say why a lamp door or a socket won't do anything yet.
func _check_dungeon() -> void:
	for c in _pickups.keys():
		if _touching(center_of(c), PICKUP_RADIUS):
			_take_pickup(c)
	_locked_msg_cd = maxf(0.0, _locked_msg_cd - get_physics_process_delta_time())
	var here := cell_of(player.position)
	for d in DIRS4:
		var c := here + d
		if _open_doors.has(c) or center_of(c).distance_to(player.position) > 24.0:
			continue
		var kind := kind_at(c)
		if kind == "fuse_door":
			if _fuses > 0:
				_fuses -= 1
				hud.set_fuses(_fuses)
				_open_door_tiles(_door_group(c))
				hud.show_toast(popup_fuse_used, 2.0)
				door_unlocked.emit(_room_index_beyond(c))
			elif _locked_msg_cd <= 0.0:
				_locked_msg_cd = 3.0
				hud.show_toast(popup_fuse_locked, 2.0)
				if Game.first_time("fuse_locked"):
					_pip_say(pip_fuse_locked)
		elif kind == "main_door" and _main_group_of.has(c) and _locked_msg_cd <= 0.0:
			# a lamp door: the popup counts its lamps, so you know how far you are
			var g: Dictionary = _main_groups[_main_group_of[c]]
			_locked_msg_cd = 3.0
			hud.show_toast(popup_lamps.format({"lit": g["lit"], "needs": g["needs"]}), 2.0)
			if Game.first_time("lamps_locked"):
				_pip_say(pip_lamps)
	# next to a clamp socket with no clamp anywhere in reach: say where to look
	if not _has_clamp and _clamp_at.x < 0 and _locked_msg_cd <= 0.0:
		for s in _sockets:
			if center_of(s).distance_to(player.position) <= SOCKET_REACH:
				_locked_msg_cd = 3.0
				hud.show_toast(popup_socket_empty, 2.0)
				if not _socket_tip_shown:
					_socket_tip_shown = true
					_pip_say(pip_socket_empty)
				break


func _take_pickup(c: Vector2i, quiet := false) -> void:
	var p: Pickup = _pickups[c]
	_pickups.erase(c)
	if p.kind == "fuse":
		_fuses += 1
		hud.set_fuses(_fuses)
		if not quiet:
			hud.show_toast(popup_fuse, 2.0)
			if Game.first_time("fuse"):
				_pip_say(pip_fuse)
	else:
		_has_clamp = true
		hud.set_clamp(true)
		if not quiet:
			hud.show_toast(popup_clamp, 2.5)
			_pip_say(pip_clamp)
	if quiet:
		p.queue_free()
	else:
		_play("pickup")
		p.collect()
		player.squash(Vector2(0.88, 1.14), 0.16)
		item_picked.emit(p.kind, room_index_at(center_of(c)))


## E without the wire, next to a socket: drop the clamp in, or take it back out.
## Returns true if it did something (so E doesn't also do anything else).
func _try_clamp() -> bool:
	if _clamp_at.x >= 0 and center_of(_clamp_at).distance_to(player.position) <= SOCKET_REACH:
		_lift_clamp()
		return true
	if not _has_clamp:
		return false
	var best := Vector2i(-1, -1)
	for s in _sockets:
		var d := center_of(s).distance_to(player.position)
		if d <= SOCKET_REACH and (best.x < 0 or d < center_of(best).distance_to(player.position)):
			best = s
	if best.x < 0:
		return false
	# Standing on the socket (even partly)? Once the clamp is in, it's solid, so
	# he'd be stuck inside it. Step him off first, to the nearest free spot beside it.
	var feet := Rect2(player.position - Astronaut.FEET_HALF, Astronaut.FEET_HALF * 2.0)
	if feet.intersects(Rect2(Vector2(best * TILE), Vector2(TILE, TILE))):
		var spot := _spot_beside(best)
		if spot == player.position:
			return false              # boxed in on every side: nowhere to step to
		_step_to(spot)
	_put_clamp(best)
	return true


## The nearest place next to socket s (not on it) where his feet fit and nothing
## zaps him. Tries the edge of each side in line with where he stands, and the
## middle of each side. Returns his own position if there's none.
func _spot_beside(s: Vector2i) -> Vector2:
	var tile := Rect2(Vector2(s * TILE), Vector2(TILE, TILE))
	var half := Astronaut.FEET_HALF + Vector2.ONE      # one pixel clear of the socket
	var pos := player.position
	var tries: Array[Vector2] = []
	for y in [pos.y, tile.get_center().y]:
		tries.append(Vector2(tile.position.x - half.x, y))     # left side
		tries.append(Vector2(tile.end.x + half.x, y))          # right side
	for x in [pos.x, tile.get_center().x]:
		tries.append(Vector2(x, tile.position.y - half.y))     # above
		tries.append(Vector2(x, tile.end.y + half.y))          # below
	var best := pos
	var best_d := INF
	for p in tries:
		var d := p.distance_to(pos)
		if d < best_d and not box_blocked(p, Astronaut.FEET_HALF) and _safe_to_stand(p):
			best = p
			best_d = d
	return best


## A quick little hop to `to` (he can't walk while it plays).
func _step_to(to: Vector2) -> void:
	player.lock()
	var tw := create_tween()
	tw.tween_property(player, "position", to, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		player.release()
		player_moved())


## Takes the clamp out of its socket, into your hands.
func _lift_clamp() -> void:
	_poles.erase(_clamp_at)
	_clamp_at = Vector2i(-1, -1)
	_has_clamp = true
	hud.set_clamp(true)
	if _clamp_post:
		_clamp_post.queue_free()
		_clamp_post = null
	_play("clank")


## Stands the clamp up in socket s.
func _put_clamp(s: Vector2i) -> void:
	_clamp_at = s
	_poles.append(s)                     # in its socket the clamp works like a pole
	_has_clamp = false
	hud.set_clamp(false)
	_clamp_post = Pickup.new()
	_clamp_post.kind = "clamp"
	_clamp_post.standing = true
	_clamp_post.position = center_of(s)
	_tile_root.add_child(_clamp_post)
	_play("clank")
	Juice.punch_scale(_clamp_post, Vector2(0.7, 1.35), 0.22)   # it springs up in the socket
	if Game.first_time("clamp_placed"):
		_pip_say(pip_clamp_placed)


## A socket you could use with E right now (for the [E] key over it), or (-1, -1).
func _socket_in_reach() -> Vector2i:
	if _clamp_at.x >= 0 and center_of(_clamp_at).distance_to(player.position) <= SOCKET_REACH:
		return _clamp_at
	if _has_clamp:
		for s in _sockets:
			if center_of(s).distance_to(player.position) <= SOCKET_REACH:
				return s
	return Vector2i(-1, -1)


## Everything the ship map (hud.gd) draws: rooms, doors, items, where you are.
func map_info() -> Dictionary:
	var rooms: Array = []
	for r in _rooms:
		if r.is_exit and not _visited.has(r):
			continue
		rooms.append({"cells": r.cells, "solved": r.solved, "visited": _visited.has(r),
			"here": r == _current_room, "hall": is_hall(r), "cells_left": r.power_cells.filter(
				func(c: Vector2i) -> bool: return not _cells[c].collected).size()})
	var doors: Array = []
	for c in _kinds:
		if DOOR_KINDS.has(_kinds[c]) or _kinds[c] == "barrier":
			doors.append({"cell": c, "kind": _kinds[c], "open": _open_doors.has(c)})
	var items: Array = []
	for c in _pickups:
		items.append({"cell": c, "kind": _pickups[c].kind})
	return {"rooms": rooms, "doors": doors, "items": items, "player": player.position / TILE,
		"rect": _rect, "clamp_at": _clamp_at}


# ===================================================================== movable crates
# See "Movable crates" at the top. Where each crate is lives in _crates (tile ->
# crate); a crate that sank into a red tile moves to _grounded. The crates
# themselves (push_crate.gd) only draw and animate.

## The player walks straight into something along `dir` and would stand at
## `target`. If what's in the way is one movable crate (nothing else), he leans
## on it, and after PUSH_LEAN seconds it rolls one tile. Returns true if it was
## a crate, so the player doesn't also try to slide round it. (player.gd _slide)
func lean_on_crate(target: Vector2, dir: Vector2) -> bool:
	var c := _crate_in_box(target, Astronaut.FEET_HALF)
	if c.x < 0 and c.y < 0:
		return false
	var d := Vector2i(roundi(dir.x), roundi(dir.y))
	var frame := Engine.get_physics_frames()
	if c != _lean_cell or d != _lean_dir or frame - _lean_frame > 2:
		_lean_time = 0.0                    # a new lean: start counting again
		_lean_refused = false
	_lean_cell = c
	_lean_dir = d
	_lean_frame = frame
	_lean_time += get_physics_process_delta_time()
	if _lean_time >= PUSH_LEAN and not _busy:
		_lean_time = 0.0
		_push_crate(c, d)
	return true


## The one crate a box (feet) at `pos` would overlap, if that's the only solid
## thing there. (-1, -1) = none, or a wall / a second crate is in the way too.
func _crate_in_box(pos: Vector2, half: Vector2) -> Vector2i:
	var none := Vector2i(-1, -1)
	var found := none
	for y in range(floori((pos.y - half.y) / TILE), floori((pos.y + half.y - 0.01) / TILE) + 1):
		for x in range(floori((pos.x - half.x) / TILE), floori((pos.x + half.x - 0.01) / TILE) + 1):
			var c := Vector2i(x, y)
			if _crates.has(c):
				if found != none and found != c:
					return none
				found = c
			elif is_solid_for_walk(c):
				return none
	return found


func _push_crate(c: Vector2i, d: Vector2i) -> void:
	var k: PushCrate = _crates[c]
	var t := c + d
	if not _crate_can_go(t):
		if not _lean_refused:
			_lean_refused = true
			k.refuse()
			_play("tick")
			if Game.first_time("crate_stuck"):
				_pip_say(pip_crate_stuck)
		return
	_crates.erase(c)
	_crates[t] = k
	k.cell = t
	k.slide_to(center_of(t))
	_play("push")
	Juice.punch_scale(k, Vector2(1.12, 0.9), 0.14)   # shorter than SLIDE_TIME, so it's done before a crate sinks
	player.squash(Vector2(1.1, 0.92), 0.12)
	var r: Room = k.room
	crate_pushed.emit(r.index if r else -1)
	if Game.first_time("crate_push"):
		_pip_say(pip_crate)
	if _is_red(t):
		_short_out(k, t)
	_check_stranded_soon()


## A crate rolled onto a live red tile: it sparks, sinks and becomes a plate.
func _short_out(k: PushCrate, t: Vector2i) -> void:
	_crates.erase(t)
	_grounded[t] = k
	k.grounded = false          # it still looks like a crate until it has rolled there
	k.ground()
	var pt: PuzzleTile = _tiles.get(t)
	if pt:
		pt.set_live(false)
	await get_tree().create_timer(PushCrate.SLIDE_TIME).timeout
	if not is_inside_tree(): return
	_play("shock")
	_sparks_at(center_of(t))
	_shake_cam(0.15, 1.5)
	Juice.hitstop(0.05)
	hud.show_toast(popup_crate_grounded, 2.0)
	var r: Room = k.room
	crate_grounded.emit(r.index if r else -1)
	if Game.first_time("crate_ground"):
		_pip_say(pip_crate_ground)


## Can a crate roll onto tile t? Only onto floor (red tiles count: that shorts
## them out), never onto pads, items, other crates, you or the wire you carry.
func _crate_can_go(t: Vector2i) -> bool:
	var k := kind_at(t)
	if k != "floor" and k != "spawn" and k != "discharge":
		return false
	if _crates.has(t) or _pickups.has(t) or _cells.has(t) or t == _clamp_at:
		return false
	var feet := Rect2(player.position - Astronaut.FEET_HALF, Astronaut.FEET_HALF * 2.0)
	if feet.intersects(Rect2(Vector2(t * TILE), Vector2(TILE, TILE))):
		return false
	if _wire != null and _wire_crosses(t):
		return false
	return true


## Does the wire you're carrying run over tile t? (Pads and poles in order,
## then the last stretch to your feet.)
func _wire_crosses(t: Vector2i) -> bool:
	var pts: Array[Vector2] = []
	for c in _anchor_cells:
		pts.append(center_of(c))
	pts.append(player.position)
	for i in pts.size() - 1:
		var steps := maxi(1, ceili(pts[i].distance_to(pts[i + 1]) / 2.0))
		for j in steps + 1:
			if cell_of(pts[i].lerp(pts[i + 1], float(j) / steps)) == t:
				return true
	return false


## Does room r have movable crates?
func _room_has_crates(r: Room) -> bool:
	return _crate_list.any(func(k: PushCrate) -> bool: return k.room == r)


## Puts the crates of room r back where they started (a shorted tile turns red
## again). Returns true if any crate had moved. quiet = no fade, no popup.
func reset_crates(r: Room, quiet := false) -> bool:
	var moved: Array[PushCrate] = []
	for k in _crate_list:
		if k.room == r and (k.cell != k.home or _grounded.has(k.cell)):
			moved.append(k)
	for k in moved:                          # first lift them all off the map...
		if _grounded.get(k.cell) == k:
			_grounded.erase(k.cell)
			var pt: PuzzleTile = _tiles.get(k.cell)
			if pt:
				pt.set_live(not _red_off.has(k.cell))
		elif _crates.get(k.cell) == k:
			_crates.erase(k.cell)
	for k in moved:                          # ...then put each one home (no two share a home)
		_crates[k.home] = k
		k.cell = k.home
		if quiet:
			k.position = center_of(k.home)
			k.grounded = false
			k.queue_redraw()
		else:
			k.go_home(center_of(k.home))
	if not moved.is_empty() and player != null and box_blocked(player.position, Astronaut.FEET_HALF):
		player.position = _nearest_safe_spot(player.position)   # a crate came home where you stood
		_last_safe = player.position
	if not moved.is_empty() and not quiet:
		hud.show_toast(popup_crates_reset, 1.5)
	return not moved.is_empty()


## After a push the way back to the START may have opened (or closed): check soon.
func _check_stranded_soon() -> void:
	if _stranded:
		_stranded_check = 0.0


## For the autopilot: the room tile c is in (null = none).
func room_at_cell(c: Vector2i) -> Room:
	return _room_of.get(c)


## For the autopilot: is there a crate standing on tile c?
func crate_at(c: Vector2i) -> bool:
	return _crates.has(c)


# ===================================================================== judge mode: the autopilot
# autopilot.gd does the walking; these are the few things it asks the level.

## P in judge mode: PIP takes over and does the next room. (R still restarts,
## so a judge can try a room themselves after PIP has shown it.)
func start_autopilot() -> void:
	if _busy or _complete or autopilot_on:
		return
	if _autopilot == null:
		_autopilot = Autopilot.new()
		_autopilot.level = self
		add_child(_autopilot)
		_autopilot.load_routes(level_number)
	_autopilot.run()


func autopilot_begin() -> void:
	autopilot_on = true
	player.autopilot = true
	_clear_stranded()
	if _wire != null:
		_fail("restart")              # holding a wire? start that room clean
	_pip_say(pip_autopilot_start)


func autopilot_end() -> void:
	autopilot_on = false
	autopilot_wraps = false
	player.autopilot = false
	player.auto_dir = Vector2.ZERO
	if not _complete:
		_pip_say(pip_autopilot_done)


## The room the autopilot should do next: the one you're in if it's unsolved,
## otherwise the first unsolved room in `walkthrough` (or in number order).
func autopilot_target():
	if _current_room != null and not _current_room.solved and _current_room.start.x >= 0:
		return _current_room
	var order: Array = []
	for n in walkthrough:
		for r in _rooms:
			if r.index == n - 1:
				order.append(r)
	var rest := _rooms.filter(func(r: Room) -> bool: return r.start.x >= 0)
	rest.sort_custom(func(a: Room, b: Room) -> bool: return a.index < b.index)
	for r in rest:
		if not order.has(r):
			order.append(r)
	for r in order:
		if not r.solved and r.start.x >= 0:
			return r
	return null


func is_busy() -> bool:
	return _busy or _cutscene


func exit_cell() -> Vector2i:
	for c in _kinds:
		if _kinds[c] == "exit":
			return c
	return Vector2i(-1, -1)


## Airlock pads that haven't cycled yet (the autopilot steps on one when the
## way out into space is still shut).
func airlock_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in _rooms:
		if r.airlock.x >= 0 and not r.cycled:
			out.append(r.airlock)
	return out


## Last resort when the autopilot can't find a way to the exit: put him there.
func autopilot_to_exit() -> void:
	var c := exit_cell()
	if c.x >= 0 and not _complete:
		player.position = center_of(c)
		player_moved()


func has_clamp() -> bool:
	return _has_clamp


func clamp_socket() -> Vector2i:
	return _clamp_at


func item_cell(kind: String) -> Vector2i:
	for c in _pickups:
		if _pickups[c].kind == kind:
			return c
	return Vector2i(-1, -1)


## Take the clamp out of its socket (the autopilot stands next to it first).
func take_clamp() -> void:
	if _clamp_at.x >= 0:
		_lift_clamp()


## Put the clamp into socket s (the autopilot stands next to it first).
func place_clamp_at(s: Vector2i) -> void:
	if _has_clamp and _sockets.has(s):
		_put_clamp(s)


func autopilot_grab() -> void:
	_try_grab()


## While PIP walks a solver route, the route says which pillars the wire is
## wrapped round (autopilot_wraps switches off _update_wraps). The maths is the
## same; the solver just did it on exact 4 px steps. Some routes only graze a
## pillar's centre, and PIP's steering is a pixel or two off, so without this
## the wire could miss the pillar and the route would get stuck.
## `pads` = how many pads the route has tied the wire to by now (START = 1).
## `want` = [[x, y, side], ...], the pillars after the last pad, in order.
func autopilot_sync_wraps(pads: int, want: Array) -> void:
	if _wire == null:
		return
	var pads_now := 0
	for c in _anchor_cells:
		if not _poles.has(c):
			pads_now += 1
	if pads_now != pads:
		return                  # he reached a pad a step before or after the route did: leave it
	var first := _anchor_cells.size()      # where the pillars after the last pad begin
	while first > 0 and _poles.has(_anchor_cells[first - 1]):
		first -= 1
	var keep := 0                          # how many of them already match the route
	while keep < want.size() and first + keep < _anchor_cells.size() \
			and _anchor_cells[first + keep] == Vector2i(int(want[keep][0]), int(want[keep][1])) \
			and _anchor_signs[first + keep] == float(want[keep][2]):
		keep += 1
	while _anchor_cells.size() > first + keep:     # off: the ones the route doesn't have
		_anchor_cells.pop_back()
		_anchor_signs.pop_back()
		_wire.remove_last_anchor()
	for k in range(keep, want.size()):             # on: the ones it does
		var c := Vector2i(int(want[k][0]), int(want[k][1]))
		_anchor_cells.append(c)
		_anchor_signs.append(float(want[k][2]))
		_wire.add_anchor(center_of(c))
		_tile_hit(c)
		_play("bend")
		pad_touched.emit("pole", _wire_room.index)
	_last_anchor = center_of(_anchor_cells[-1])


## When walking the route didn't work: PIP powers the room himself. The wire
## jumps from the START to the goal and the room is solved as usual.
func autopilot_force_solve(r: Room) -> void:
	if r.solved or _busy:
		return
	push_warning("Autopilot couldn't walk room %d, so PIP powered it directly. If the map changed, run: python tools/solver2.py Levels/level_%d.tscn --paths Data/routes/level_%d.json --margin 3" % [r.index + 1, level_number, level_number])
	if _wire == null:
		player.position = center_of(r.start)
		_current_room = r
		_try_grab()
	if _wire == null:
		return
	if r.target().x >= 0:
		_wire.add_anchor(center_of(r.target()))
	_solve(r)


## A walking path (tile by tile, sideways and up/down only) from one tile to
## another that avoids walls, closed doors and red tiles. A fuse door counts as
## open if you carry a fuse (walking into it opens it). [] = no way.
## Blinking grates are avoided if there's another way; if there isn't (Level 3
## has a START behind a row of them) the path crosses them. Only the autopilot
## uses this, and nothing zaps him while it runs.
func walk_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var path := _walk_bfs(from, to, false)
	if path.is_empty() and from != to:
		path = _walk_bfs(from, to, true)
	return path


func _walk_bfs(from: Vector2i, to: Vector2i, grates_ok: bool) -> Array[Vector2i]:
	var prev := {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size() and head < 6000:
		var c := queue[head]
		head += 1
		if c == to:
			break
		for d in DIRS4:
			var n := c + d
			# open space next to you: you can drift straight across to the next plate
			if kind_at(n) == "space":
				var k := 1
				while kind_at(c + d * k) == "space" and k < int(MAX_DRIFT / TILE):
					k += 1
				n = c + d * k
				if kind_at(n) == "space":
					continue                 # nothing to land on within reach
			if prev.has(n):
				continue
			var fuse_ok := kind_at(n) == "fuse_door" and _fuses > 0
			if (is_solid_for_walk(n) and not fuse_ok) or _is_red(n) or (kind_at(n) == "blinker" and not grates_ok):
				continue
			prev[n] = c
			queue.append(n)
	var path: Array[Vector2i] = []
	if not prev.has(to):
		return path
	var c := to
	while c != from:
		path.append(c)
		c = prev[c]
	path.reverse()
	return path


# ===================================================================== map helpers

## Reads every painted tile and asks it for its "kind" label.
func _read_layout() -> void:
	_kinds.clear()
	_floating_cells.clear()
	for c in layout.get_used_cells():
		var data := layout.get_cell_tile_data(c)
		if data == null:
			continue
		var kind := String(data.get_custom_data("kind"))
		if kind != "":
			_kinds[c] = kind
	# A movable crate isn't part of the map: it's a thing standing on the floor
	# (it moves). Remember where each one starts, and call its tile floor.
	_crate_homes.clear()
	for c in _kinds.keys():
		if _kinds[c] == "box":
			_crate_homes.append(c)
			_kinds[c] = "floor"
	# The "test start" tile is a note for the editor (F6 starts there, see
	# _apply_test_start). For the rules it's plain floor.
	_test_cells.clear()
	for c in _kinds.keys():
		if _kinds[c] == "test_start":
			_test_cells.append(c)
			_kinds[c] = "floor"
	# A power cell with open space on both sides (left and right, or above and
	# below) floats in space: that tile is open space (you drift past it), it
	# just has a cell on it. Otherwise the cell sits on the floor / hull.
	for c in _kinds.keys():
		if _kinds[c] != "cell":
			continue
		var across := _open(c + Vector2i.LEFT) and _open(c + Vector2i.RIGHT)
		var down := _open(c + Vector2i.UP) and _open(c + Vector2i.DOWN)
		if across or down:
			_floating_cells.append(c)
	for c in _floating_cells:
		_kinds[c] = "space"
	_rect = layout.get_used_rect().grow(1)
	# Tiles from the team's art sheets (every source but 0, the plain palette)
	# are shown as painted: the level copies them onto its Art layers instead of
	# drawing its own picture there. Their kind still gives them their rules.
	_art.clear()
	for c in layout.get_used_cells():
		var src := layout.get_cell_source_id(c)
		if src > 0:
			var data := layout.get_cell_tile_data(c)
			var kind := String(data.get_custom_data("kind")) if data else ""
			_art[c] = [src, layout.get_cell_atlas_coords(c), layout.get_cell_alternative_tile(c), kind]


## What is painted at tile `c`? "" means nothing (outside the map).
func kind_at(c: Vector2i) -> String:
	return _kinds.get(c, "")


## Open space (or nothing). Used to spot power cells floating in space.
func _open(c: Vector2i) -> bool:
	return kind_at(c) in ["space", "", "cell"]


## Pixel position -> tile coordinates. floori rounds down (e.g. 70 / 32 = 2.18 -> 2).
func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


## Tile coordinates -> the pixel in the middle of that tile.
func center_of(c: Vector2i) -> Vector2:
	return Vector2(c * TILE) + Vector2(TILE, TILE) * 0.5


func _walkable(kind: String) -> bool:
	return kind != "" and kind != "wall"


## Doors (all three kinds) and barriers aren't part of any room: they're what
## separates rooms/stages.
func _is_room_cell(kind: String) -> bool:
	return _walkable(kind) and not DOOR_KINDS.has(kind) and kind != "barrier"


## Can't walk through: nothing, walls, crates, cores, poles, a socket with the
## clamp in it, closed doors and barriers that haven't moved yet. Open space too,
## unless space_blocks is false (used for drifting: you float over space).
func is_solid_for_walk(c: Vector2i, space_blocks := true) -> bool:
	if _crates.has(c):
		return true
	var kind := kind_at(c)
	if kind == "" or kind == "wall" or kind == "crate" or kind == "core" or kind == "pole":
		return true
	if kind == "space":
		return space_blocks
	if DOOR_KINDS.has(kind) or kind == "barrier":
		return not _open_doors.has(c)
	if kind == "socket":
		return c == _clamp_at
	return false


## The wire can't pass over: nothing, walls, crates, cores, doors, the exit, live
## red tiles, and barriers until they've sunk away. (It can stretch across open space.)
func is_solid_for_wire(c: Vector2i) -> bool:
	if _crates.has(c):
		return true
	var kind := kind_at(c)
	if kind == "barrier":
		return not _open_doors.has(c)
	if kind == "discharge":
		return _is_red(c)                   # switched off by a power link or shorted by a crate = just floor
	return kind in ["", "wall", "crate", "core", "exit"] or DOOR_KINDS.has(kind)


## True if a box (centre `pos`, half-size `half`) overlaps anything solid.
func box_blocked(pos: Vector2, half: Vector2, space_blocks := true) -> bool:
	var x0 := floori((pos.x - half.x) / TILE)
	var x1 := floori((pos.x + half.x - 0.01) / TILE)
	var y0 := floori((pos.y - half.y) / TILE)
	var y1 := floori((pos.y + half.y - 0.01) / TILE)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if is_solid_for_walk(Vector2i(x, y), space_blocks):
				return true
	return false


## Walks along the line a->b in 2 px steps; returns the first point on a tile
## the wire can't cross, or b if the whole line is clear.
func _first_blocked_point(a: Vector2, b: Vector2) -> Vector2:
	var steps := maxi(1, ceili(a.distance_to(b) / 2.0))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		if is_solid_for_wire(cell_of(p)):
			return p
	return b


func _line_clear(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / 2.0))
	for i in steps + 1:
		if is_solid_for_wire(cell_of(a.lerp(b, float(i) / steps))):
			return false
	return true


## Asked by the player before every step: would the tight wire still reach `pos`?
## The tile you'd be standing on is ignored if it's a red tile, so you can walk
## onto red tiles while carrying the wire (and get shocked), instead of being stopped.
func wire_reaches(pos: Vector2) -> bool:
	var own := cell_of(pos)
	var steps := maxi(1, ceili(_last_anchor.distance_to(pos) / 2.0))
	for i in steps + 1:
		var c := cell_of(_last_anchor.lerp(pos, float(i) / steps))
		if c == own and kind_at(c) == "discharge":
			continue
		if is_solid_for_wire(c):
			return false
	return true


## Which room is this pixel in? (-1 = none). Used by the tutorial, story and floor guides.
func room_index_at(pos: Vector2) -> int:
	var r: Room = _room_of.get(cell_of(pos))
	return r.index if r != null else -1


## The room the player is in right now (-1 = none).
func current_room_index() -> int:
	return _current_room.index if _current_room != null else -1


## Is this tile outside the ship? Hull, open space, or anything right next to them.
func _is_outside(c: Vector2i) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var k := kind_at(c + Vector2i(dx, dy))
			if k == "hull" or k == "space":
				return true
	return false


## Open space or nothing at all: hull plates get an edge where they meet these.
func _is_void(c: Vector2i) -> bool:
	var k := kind_at(c)
	return k == "" or k == "space"


## A door with no wall beside it is out in space: a gangway (catwalk).
## The whole door counts, not just this tile: in a door 3 or more tiles tall,
## the middle tile only touches other door tiles and floor, but the door is
## still in a wall (before Nov 2026 that middle tile was drawn as a catwalk).
func _is_gangway(c: Vector2i) -> bool:
	if kind_at(c) != "door":
		return false
	for t in _door_group(c):
		for d in DIRS4:
			if kind_at(t + d) == "wall":
				return false
	return true


## A crate with no floor or hull beside it floats in space (debris).
func _is_floating(c: Vector2i) -> bool:
	for d in DIRS4:
		var k := kind_at(c + d)
		if k != "space" and k != "crate" and k != "":
			return false
	return true


# ===================================================================== visuals (also run in the editor)

func _build_visuals() -> void:
	_read_layout()
	var ts := _make_tileset()
	if _ground == null or not is_instance_valid(_ground):
		_ground = _new_layer("Ground", -10)
		_hull_edges = Node2D.new()
		_hull_edges.name = "HullEdges"
		_hull_edges.z_index = -10
		add_child(_hull_edges)
		_hull_edges.draw.connect(_draw_hull_edges)
		_walls = _new_layer("Walls", -9)
		_props = _new_layer("Props", -7)
		# in the editor only: the support pillars standing on the pole tiles, so you
		# see what you're painting (in the game each pole draws its own pillar)
		if Engine.is_editor_hint():
			_pillar_preview = Node2D.new()
			_pillar_preview.name = "PillarPreview"
			_pillar_preview.z_index = -6
			add_child(_pillar_preview)
			_pillar_preview.draw.connect(_draw_pillar_preview)
			# and the movable crates (in the game each crate draws itself)
			_crate_preview = Node2D.new()
			_crate_preview.name = "CratePreview"
			_crate_preview.z_index = -6
			add_child(_crate_preview)
			_crate_preview.draw.connect(func() -> void:
				for c in _crate_homes:
					var art := _art_texture(c)
					if art:
						_crate_preview.draw_texture(art, center_of(c) - Vector2(16, 16))
					else:
						PushCrate.draw_crate(_crate_preview, center_of(c)))
	for l in [_ground, _walls, _props]:
		l.tile_set = ts
		l.clear()
	# the team's art, copied from the Layout as it was painted (same z as ours).
	# Made on their own, not with the layers above: when Godot reloads this
	# script into a scene that's already open, the old layers are still there
	# but these new ones aren't yet.
	if _art_floor == null or not is_instance_valid(_art_floor):
		_art_floor = _new_layer("ArtFloor", -10)
		_art_walls = _new_layer("ArtWalls", -9)
		_art_props = _new_layer("ArtProps", -7)
	for l in [_art_floor, _art_walls, _art_props]:
		l.tile_set = layout.tile_set          # the same tiles you paint with (animations included)
		l.clear()
	for c in _kinds:
		var kind: String = _kinds[c]
		if _art.has(c):
			var a: Array = _art[c]
			match a[3]:
				"wall":
					_art_walls.set_cell(c, a[0], a[1], a[2])     # the team's wall, exactly as painted
					continue
				"floor":
					_art_floor.set_cell(c, a[0], a[1], a[2])
					continue                  # the team's floor instead of ours
				"box":
					pass                      # a crate you push draws itself (push_crate.gd): just floor here
				"goal":
					_show_goal_art(c, false)  # grey until its room has power
				_:
					_art_props.set_cell(c, a[0], a[1], a[2])   # pads, crates: drawn over our floor
		if kind == "wall":
			# a plain grey wall from the old palette: show the wall piece whose edge
			# follows the floor (tools/retile_walls.py paints these as real tiles)
			_art_walls.set_cell(c, SRC_ART_WALL, _wall_piece(c))
			continue
		if kind == "space":
			continue          # open space: draw nothing, the starfield shows through
		if kind == "door" and _is_gangway(c):
			if Engine.is_editor_hint() and not live_preview:
				_props.set_cell(c, SRC_PUZZLE, Vector2i(GANGWAY_FRAME, 0), 1 if _door_rotated(c) else 0)
			continue          # the catwalk is a PuzzleTile at runtime
		if kind == "crate" and _is_floating(c) and not _art.has(c):
			_props.set_cell(c, SRC_PUZZLE, Vector2i(PUZZLE_FRAME["crate"], 0))   # floating debris
			continue
		if _is_outside(c):
			_ground.set_cell(c, SRC_HULL, Vector2i(_hull_variant(c), 0))
		else:
			_ground.set_cell(c, SRC_FLOOR, Vector2i(_floor_variant(c), 0))
		# fixed cargo is drawn here; pads, doors and so on are real PuzzleTiles in
		# the game (and in the editor's live preview). With the preview off, the
		# editor shows their still pictures here instead.
		var still := Engine.is_editor_hint() and not live_preview
		if PUZZLE_FRAME.has(kind) and (still or kind == "crate") and not _art.has(c):
			var alt := 1 if (DOOR_KINDS.has(kind) and _door_rotated(c)) else 0
			_props.set_cell(c, SRC_PUZZLE, Vector2i(PUZZLE_FRAME[kind], 0), alt)
	_hull_edges.queue_redraw()
	if _pillar_preview:
		_pillar_preview.queue_redraw()
	if _crate_preview:
		_crate_preview.queue_redraw()
	if Engine.is_editor_hint():
		_update_room_info()
		_build_live_preview()


# ===================================================================== the editor's room labels
# Painting is all it takes to make a level: every tile in the palette carries its
# "kind", and the rules and the art come from that. What the tiles can't tell
# you is how the game reads them: which room is number 5, what it's called,
# how long its START gives you. So in the editor each room gets a label with
# exactly that, plus a red warning if something's missing. And when you paint
# a new room, the Room Titles and Room Wire Time lists grow to match.

func _update_room_info() -> void:
	_build_rooms(true)
	# one name (and one START time) per room, in walking order: grow the lists
	# when a new room appears, so they never fall behind the map
	var n := _rooms.size()
	if room_titles.size() < n:
		var t := room_titles.duplicate()
		while t.size() < n:
			t.append("ROOM %d" % (t.size() + 1))
		room_titles = t
	if room_wire_time.size() < n and not room_wire_time.is_empty():
		var w := room_wire_time.duplicate()
		while w.size() < n:
			w.append(0.0)
		room_wire_time = w
	if _room_info == null or not is_instance_valid(_room_info):
		_room_info = Node2D.new()
		_room_info.name = "RoomInfo"
		_room_info.z_index = 60                 # over the painted Layout (50)
		add_child(_room_info)
		_room_info.draw.connect(_draw_room_info)
	_room_info.queue_redraw()


func _draw_room_info() -> void:
	if not show_room_info:
		return
	var font := ThemeDB.fallback_font
	var taken: Array[Rect2] = []       # labels already drawn (a new one steps down past them)
	for r in _rooms:
		if r.cells.is_empty():
			continue
		var top := r.cells[0]
		for c in r.cells:
			if c.y < top.y or (c.y == top.y and c.x < top.x):
				top = c
		var lines: Array = []          # [text, colour]
		var i := r.index
		var title := room_titles[i] if i >= 0 and i < room_titles.size() else "ROOM %d" % (i + 1)
		if r.is_exit:
			lines.append(["EXIT", Color(0.6, 1.0, 0.6)])
		elif is_hall(r):
			lines.append(["%d  %s  (hall)" % [i + 1, title], Color(0.75, 0.8, 0.9)])
		else:
			lines.append(["%d  %s" % [i + 1, title], Color(1.0, 0.85, 0.4)])
			if r.start.x >= 0:
				var own := room_wire_time[i] if i < room_wire_time.size() else 0.0
				var secs := own if own > 0.0 else wire_time
				lines.append(["START %.1f s%s" % [secs, "" if own > 0.0 else " (level's)"], Color(0.8, 0.95, 0.8)])
			var starts := r.cells.filter(func(c: Vector2i) -> bool: return kind_at(c) == "start").size()
			var crates := _crate_homes.filter(func(c: Vector2i) -> bool: return _room_of.get(c) == r).size()
			if crates > 0:
				lines.append(["%d crate%s" % [crates, "" if crates == 1 else "s"], Color(0.8, 0.85, 0.95)])
			if r.airlock.x < 0:
				if starts == 0:
					lines.append(["needs a START pad", Color(1, 0.35, 0.3)])
				elif starts > 1:
					lines.append(["%d STARTs: use one" % starts, Color(1, 0.35, 0.3)])
				if r.target().x < 0:
					lines.append(["needs a GOAL (or a core)", Color(1, 0.35, 0.3)])
		var at := Vector2(top * TILE) + Vector2(3, 3)
		var w := 0.0
		for l in lines:
			w = maxf(w, font.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x)
		var box := Rect2(at, Vector2(w + 8, lines.size() * 12 + 4))
		while taken.any(func(t: Rect2) -> bool: return t.intersects(box)):
			box.position.y += 14.0
		taken.append(box)
		at = box.position
		_room_info.draw_rect(box, Color(0.03, 0.05, 0.1, 0.8))
		for k in lines.size():
			_room_info.draw_string(font, at + Vector2(4, 12 + k * 12), lines[k][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lines[k][1])


# ===================================================================== the editor's live preview
# Like a level editor in a game: what you paint is what you get. Every tile with
# something on it (pads, doors, red floor, grates, barriers, the core, power
# cells, fuses, the clamp) gets the very same object the game makes for it
# (PuzzleTile, PowerCell, Pickup), so it glows, sparks, bobs and blinks right
# there in the editor. Those scripts are @tool, which means Godot runs them in
# the editor too.
# These nodes have no owner, so Godot never saves them into the scene: they're
# thrown away and made again every time you paint (_build_visuals calls us).
# The game itself doesn't use any of this; it makes its own in _spawn_runtime_tiles.

func _build_live_preview() -> void:
	if _live_root != null and is_instance_valid(_live_root):
		_live_root.queue_free()
		_live_root = null
	if _live_marks != null and is_instance_valid(_live_marks):
		_live_marks.queue_free()
		_live_marks = null
	_live_grates.clear()
	if not live_preview:
		return
	_live_root = _new_root("LivePreview", -7)       # the same depth as the game's PuzzleTiles
	var preview_tiles := {}                          # tile -> PuzzleTile (for the main door lamps)
	for c in _kinds:
		var kind: String = _kinds[c]
		if not PUZZLE_FRAME.has(kind) or kind == "crate":
			continue                                 # nothing to show, or fixed cargo (on the Props layer)
		var t := PuzzleTile.new()
		t.position = center_of(c)
		t.art_from_map = _art.has(c)      # the team's picture is on the Art layer already
		_live_root.add_child(t)
		if kind == "door" and _is_gangway(c):
			t.setup(PuzzleTile.Kind.GANGWAY, _door_rotated(c))
		else:
			t.setup(PUZZLE_FRAME[kind], DOOR_KINDS.has(kind) and _door_rotated(c))
		preview_tiles[c] = t
		if kind == "blinker":
			_live_grates[c] = t
	for c in _floating_cells + _kinds.keys().filter(func(k: Vector2i) -> bool: return _kinds[k] == "cell"):
		var cell := PowerCell.new()
		cell.position = center_of(c)
		_live_root.add_child(cell)
	for c in _kinds:
		if _kinds[c] == "fuse" or _kinds[c] == "clamp":
			var p := Pickup.new()
			p.kind = _kinds[c]
			p.position = center_of(c)
			_live_root.add_child(p)
	_preview_main_lamps(preview_tiles)
	# spawn, exit, test start and open space have no picture in the game:
	# they get a small marker so you can see where you put them
	_live_marks = _new_root("LiveMarks", 55)          # over the Layout icons (50)
	# bind(): the node hands itself to the draw function. (When you paint, the old
	# node may draw one last time before it's deleted: it must draw on itself.)
	_live_marks.draw.connect(_draw_live_marks.bind(_live_marks))
	_live_marks.queue_redraw()


## Did someone paint? Godot 4.7's TileMapLayer doesn't send its "changed" signal
## when you paint a tile, so 5 times a second we take a fingerprint of the map
## (hash() turns all the painted tiles into one number) and compare it with the
## last one. A different number = something was painted: redraw everything.
func _watch_painting(delta: float) -> void:
	_map_check -= delta
	if _map_check > 0.0 or layout == null:
		return
	_map_check = 0.2
	var h := hash(layout.tile_map_data)
	if h != _map_hash:
		if _map_hash != 0:
			_queue_rebuild()
		_map_hash = h


## A main door shows one lamp per UNLOCK link pointing at it, like in the game.
func _preview_main_lamps(preview_tiles: Dictionary) -> void:
	var needs := {}                                  # main door tile -> lamps
	for link in find_children("*", "Marker2D", true, false):
		if not link is PowerLink or link.action != PowerLink.Action.UNLOCK:
			continue
		for target in link.target_cells(self):
			if kind_at(target) == "main_door":
				for tile in _door_group(target):
					needs[tile] = int(needs.get(tile, 0)) + 1
	for tile in needs:
		var t: PuzzleTile = preview_tiles.get(tile)
		if t:
			t.set_lamps(0, needs[tile])


## Every frame in the editor: the blinking grates run their wave, with the
## level's own grate_cycle / grate_live / grate_wave numbers.
func _tick_live_preview(delta: float) -> void:
	_watch_painting(delta)
	if _live_grates.is_empty():
		return
	_light_t += delta
	for c in _live_grates:
		var t: PuzzleTile = _live_grates[c]
		if is_instance_valid(t):
			t.set_live(blinker_live(c), _blinker_phase(c) > grate_cycle - 0.35)


func _draw_live_marks(ci: CanvasItem) -> void:
	var font := ThemeDB.fallback_font
	for c in _kinds:
		var at := Vector2(c * TILE)
		match _kinds[c]:
			"space":
				# open space: a few dim stars (the game shows the starfield here)
				ci.draw_rect(Rect2(at, Vector2(TILE, TILE)), Color(0.02, 0.03, 0.08, 0.6))
				var h := absi(c.x * 73856093 ^ c.y * 19349663)
				for i in 3:
					var p := Vector2((h >> (i * 5)) % 30 + 1, (h >> (i * 5 + 15)) % 30 + 1)
					ci.draw_rect(Rect2(at + p, Vector2.ONE), Color(0.8, 0.85, 1.0, 0.7))
			"spawn":
				_draw_mark(ci, font, at, "SPAWN", Color(0.45, 0.85, 1.0))
			"exit":
				_draw_mark(ci, font, at, "EXIT", Color(0.6, 1.0, 0.6))
	for c in _test_cells:
		var col := Color(0.3, 1.0, 0.45) if _test_cells.size() == 1 else Color(1, 0.35, 0.3)
		var at := Vector2(c * TILE)
		ci.draw_rect(Rect2(at + Vector2(15, 4), Vector2(2, 24)), col)        # a flag pole...
		ci.draw_colored_polygon(PackedVector2Array([at + Vector2(17, 4),
			at + Vector2(28, 8), at + Vector2(17, 12)]), col)                         # ...and its flag
		var label := "TEST START (F6)" if _test_cells.size() == 1 else "%d TEST STARTS: use one" % _test_cells.size()
		ci.draw_string(font, at + Vector2(0, TILE + 9), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)


## A thin coloured frame with a word in it, for tiles that are invisible in the game.
func _draw_mark(ci: CanvasItem, font: Font, at: Vector2, word: String, col: Color) -> void:
	ci.draw_rect(Rect2(at + Vector2(1, 1), Vector2(TILE - 2, TILE - 2)), col, false, 1.0)
	ci.draw_string(font, at + Vector2(2, 19), word, HORIZONTAL_ALIGNMENT_CENTER, TILE - 4, 7, col)


## Editor only: a support pillar on every pole tile (the same picture the game uses).
func _draw_pillar_preview() -> void:
	if live_preview:
		return            # the live preview's pole tiles stand their own pillars
	var tex := load(PuzzleTile.PILLAR_TEX) as Texture2D
	if tex == null:
		return
	for c in _kinds:
		if _kinds[c] == "pole":
			_pillar_preview.draw_texture(tex, center_of(c) + Vector2(-16, -PuzzleTile.PILLAR_FOOT))


## Walls are painted as real tiles: the team's front panels (wall.png) and the
## 47 wall pieces (wall_sides.png, tools/art_wall_sides.py), each shown exactly
## as painted. Only a plain grey "wall" from the old palette has no picture of
## its own; it borrows the piece whose light edge runs along exactly the sides
## (and corners) where there's floor next to it, the same piece
## tools/retile_walls.py would paint there. Open space and the outside of the
## map aren't floor: walls fade to dark there.
const SRC_ART_WALL := 3        # the 47 wall pieces (wall_sides.png)
const WALL_DIRS := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]   # N NE E SE S SW W NW
const WALL_NAMES := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


func _wall_piece(c: Vector2i) -> Vector2i:
	if _wall_pieces.is_empty():
		# wall_sides.json (written with the picture) lists each piece's floor sides
		var list = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/images/tiles/team/wall_sides.json"))
		for p in list:
			if p.has("panel_top") or p.has("panel"):
				continue                      # pieces next to a front panel: only painted by tools/retile_walls.py
			var bits := 0
			for d in p["open"]:
				bits |= 1 << WALL_NAMES.find(d)
			_wall_pieces[bits] = Vector2i(int(p["x"]), int(p["y"]))
	var bits := 0
	for i in 8:
		var k := kind_at(c + WALL_DIRS[i])
		if k != "" and k != "wall" and k != "space":
			bits |= 1 << i                    # floor (or a pad, a door...) on that side
	# a corner only counts when both sides next to it are wall (bits: N 1, NE 2, E 4, SE 8, S 16, SW 32, W 64, NW 128)
	for corner in [[1, 0, 2], [3, 2, 4], [5, 4, 6], [7, 6, 0]]:
		if bits & (1 << corner[1]) or bits & (1 << corner[2]):
			bits &= ~(1 << corner[0])
	return _wall_pieces.get(bits, Vector2i.ZERO)


## A goal painted with the team's art: the grey block while its room has no
## power, the animated blue goal once it has. (Any of the team's goal tiles,
## grey, blue or animated, works the same: the level picks the picture.)
const GOAL_OFF := [4, Vector2i(1, 7)]   # objects.png: the grey goal
const GOAL_ON := [6, Vector2i.ZERO]     # goal_anim.png


func _show_goal_art(c: Vector2i, powered: bool) -> void:
	if not _art.has(c) or _art[c][3] != "goal" or _art_props == null:
		return
	var look: Array = GOAL_ON if powered else GOAL_OFF
	_art_props.set_cell(c, look[0], look[1])


## The picture of the team's art tile painted at c (null if it isn't one).
## An AtlasTexture shows one square of a bigger picture.
func _art_texture(c: Vector2i) -> Texture2D:
	if not _art.has(c):
		return null
	var src := layout.tile_set.get_source(_art[c][0]) as TileSetAtlasSource
	if src == null:
		return null
	var t := AtlasTexture.new()
	t.atlas = src.texture
	t.region = src.get_tile_texture_region(_art[c][1])
	return t


func _new_layer(layer_name: String, z: int) -> TileMapLayer:
	var l := TileMapLayer.new()
	l.name = layer_name
	l.z_index = z     # lower z_index = drawn further behind
	# Draw the map in 8x8-tile chunks: each chunk only has to deal with the
	# few lights near it, which keeps lighting fast and correct.
	l.rendering_quadrant_size = 8
	add_child(l)
	return l


## A TileSet is the "palette" a TileMapLayer paints with. This one is built in
## code from our PNG files (the Layout layer uses its own .tres palette).
func _make_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	_add_atlas(ts, SRC_WALL, WALL_TEX, Vector2i(6, 4))
	_add_atlas(ts, SRC_FLOOR, FLOOR_TEX, Vector2i(3, 1))
	_add_atlas(ts, SRC_ROOF, ROOF_TEX, Vector2i(16, 16))
	var puzzle := _add_atlas(ts, SRC_PUZZLE, PUZZLE_TEX, Vector2i(17, 1))
	for frame in [PUZZLE_FRAME["door"], GANGWAY_FRAME, PUZZLE_FRAME["fuse_door"], PUZZLE_FRAME["main_door"]]:
		var alt := puzzle.create_alternative_tile(Vector2i(frame, 0), 1)
		puzzle.get_tile_data(Vector2i(frame, 0), alt).transpose = true   # turned sideways
	_add_atlas(ts, SRC_HULL, HULL_TEX, Vector2i(3, 1))
	return ts


func _add_atlas(ts: TileSet, id: int, path: String, grid: Vector2i) -> TileSetAtlasSource:
	var src := TileSetAtlasSource.new()
	src.texture = load(path)
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, id)
	for y in grid.y:
		for x in grid.x:
			src.create_tile(Vector2i(x, y))
	return src


## Mostly clean floor plates, sometimes a scuffed one. The "hash" looks random
## but always gives the same answer for the same tile.
func _floor_variant(c: Vector2i) -> int:
	var h := ((c.x * 73856093) ^ (c.y * 19349663)) & 0xffff
	var v := h % 100
	if v < 70:
		return 0
	return 1 if v < 85 else 2


## Same trick for hull plates: plain, scuffed, or with a vent.
func _hull_variant(c: Vector2i) -> int:
	var h := ((c.x * 73856093) ^ (c.y * 19349663)) & 0xffff
	var v := h % 100
	if v < 62:
		return 0
	return 1 if v < 93 else 2


## A door with floor to its left/right sits in a side wall: draw its bar upright.
func _door_rotated(c: Vector2i) -> bool:
	var l := kind_at(c + Vector2i.LEFT)
	var r := kind_at(c + Vector2i.RIGHT)
	return (_walkable(l) and not DOOR_KINDS.has(l) and l != "space") or (_walkable(r) and not DOOR_KINDS.has(r) and r != "space")


## Is the hull drawn under this tile? (Used to give the plates their edges.)
func _has_hull_ground(c: Vector2i) -> bool:
	var k := kind_at(c)
	if k == "" or k == "wall" or k == "space":
		return false
	if (k == "door" and _is_gangway(c)) or (k == "crate" and _is_floating(c)):
		return false
	return _is_outside(c)


## Gives the hull plates some thickness: a darker "side" under every plate with
## open space below it, and thin edge lines where a plate meets space.
func _draw_hull_edges() -> void:
	for c in _kinds:
		if not _has_hull_ground(c):
			continue
		var p := Vector2(c * TILE)
		if _is_void(c + Vector2i.DOWN):
			_hull_edges.draw_rect(Rect2(p + Vector2(0, TILE), Vector2(TILE, 6)), Color(0.33, 0.35, 0.42))
			_hull_edges.draw_rect(Rect2(p + Vector2(0, TILE + 6), Vector2(TILE, 1)), Color(0.12, 0.13, 0.17))
			for x in range(4, TILE, 8):
				_hull_edges.draw_rect(Rect2(p + Vector2(x, TILE + 2), Vector2(2, 2)), Color(0.22, 0.24, 0.3))
		if _is_void(c + Vector2i.UP):
			_hull_edges.draw_rect(Rect2(p, Vector2(TILE, 1)), Color(0.86, 0.89, 0.96))
		if _is_void(c + Vector2i.LEFT):
			_hull_edges.draw_rect(Rect2(p, Vector2(1, TILE)), Color(0.74, 0.77, 0.85))
		if _is_void(c + Vector2i.RIGHT):
			_hull_edges.draw_rect(Rect2(p + Vector2(TILE - 1, 0), Vector2(1, TILE)), Color(0.2, 0.22, 0.28))


# ===================================================================== rooms

## "Flood fill": start on a floor tile and keep stepping to neighbouring floor
## tiles until you can't. Everything you reached is one room.
## quiet = don't warn about missing pads (used for previews in the editor).
func _build_rooms(quiet := false) -> void:
	_rooms.clear()
	_room_of.clear()
	_poles.clear()
	_door_rooms.clear()
	var spawn_found := false
	for c in _kinds:
		if _kinds[c] == "spawn":
			_spawn = c
			spawn_found = true
		if _room_of.has(c) or not _is_room_cell(_kinds[c]):
			continue
		var room := Room.new()
		var queue: Array[Vector2i] = [c]
		_room_of[c] = room
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_back()
			room.cells.append(cur)
			match kind_at(cur):
				"start": room.start = cur
				"goal":
					room.goal = cur
					room.pads.append(cur)
				"node": room.pads.append(cur)
				"pole": _poles.append(cur)
				"exit": room.is_exit = true
				"airlock": room.airlock = cur
				"core": room.core = cur
				"hull", "space": room.outside = true
			for d in DIRS4:
				var n := cur + d
				if not _room_of.has(n) and _is_room_cell(kind_at(n)):
					_room_of[n] = room
					queue.append(n)
		_rooms.append(room)
	# doors (all kinds, and barriers) and which rooms they join
	for c in _kinds:
		if not DOOR_KINDS.has(_kinds[c]) and _kinds[c] != "barrier":
			continue
		var adj: Array = []
		for d in DIRS4:
			var r = _room_of.get(c + d)
			if r != null and not adj.has(r):
				adj.append(r)
		_door_rooms[c] = adj
		for r in adj:
			r.doors.append(c)
			for o in adj:
				if o != r and not r.neighbors.has(o):
					r.neighbors.append(o)
	_build_barrier_groups()
	# camera bounds: room tiles + 1 tile of wall, + 3 tiles above for the wall panels
	# (outside: 2 tiles of space all round)
	for r in _rooms:
		var mn := Vector2i(1 << 20, 1 << 20)
		var mx := Vector2i(-(1 << 20), -(1 << 20))
		for c in r.cells:
			mn = mn.min(c)
			mx = mx.max(c)
		if r.outside:
			r.bounds = Rect2i(mn.x - 2, mn.y - 2, mx.x - mn.x + 5, mx.y - mn.y + 5)
		else:
			r.bounds = Rect2i(mn.x - 1, mn.y - 3, mx.x - mn.x + 3, mx.y - mn.y + 5)
	_build_areas()
	if not spawn_found:
		if not quiet:
			push_warning("No spawn tile painted - starting next to the first START pad.")
		for r in _rooms:
			if r.start.x >= 0:
				_spawn = r.start + Vector2i.DOWN
				break
	# number the rooms in the order you reach them from the spawn
	var first: Room = _room_of.get(_spawn)
	if first == null and not _rooms.is_empty():
		first = _rooms[0]
	var order: Array = [first]
	var i := 0
	while i < order.size():
		for n in order[i].neighbors:
			if not order.has(n):
				order.append(n)
		i += 1
	for j in order.size():
		order[j].index = j
	_rooms_with_goal = 0
	for r in _rooms:
		if r.target().x >= 0 and not r.is_exit:
			_rooms_with_goal += 1
	if not quiet:
		_check_rooms()


## Barrier groups. Barrier tiles that touch each other form one group: a whole
## wall of cargo that moves together. A group sinks as soon as any stage next to
## it gets power. (So a barrier can also sit in the middle of a stage, not only
## between two.) The stages next to a group become neighbours.
func _build_barrier_groups() -> void:
	_barrier_groups.clear()
	_group_of.clear()
	for c in _kinds:
		if _kinds[c] != "barrier" or _group_of.has(c):
			continue
		var gi := _barrier_groups.size()
		var tiles: Array[Vector2i] = []
		var near: Array = []
		var queue: Array[Vector2i] = [c]
		_group_of[c] = gi
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_back()
			tiles.append(cur)
			for d in DIRS4:
				var n := cur + d
				var r = _room_of.get(n)
				if r != null and not near.has(r):
					near.append(r)
				if kind_at(n) == "barrier" and not _group_of.has(n):
					_group_of[n] = gi
					queue.append(n)
		_barrier_groups.append({"tiles": tiles, "rooms": near})
		for r in near:
			for o in near:
				if o != r and not r.neighbors.has(o):
					r.neighbors.append(o)


## The barrier groups that sink when room r gets power (every group touching it).
func _barrier_groups_of(r: Room) -> Array:
	return _barrier_groups.filter(func(g: Dictionary) -> bool: return g["rooms"].has(r))


## Areas. A room is one puzzle stage. Stages joined by a barrier (or, outside,
## by a catwalk) are really one big space, so they form an area: the camera can
## roam across the whole area, the room-name popup only shows when you walk into
## a new area, and a stage can use the nodes of stages you already
## powered in its area. Only real doors (with walls beside them) start a new area.
func _build_areas() -> void:
	var next_id := 0
	for r in _rooms:
		if r.area_id >= 0:
			continue
		# collect every room reachable through barriers / catwalks (breadth-first)
		var members: Array[Room] = [r]
		r.area_id = next_id
		var k := 0
		while k < members.size():
			for c in members[k].doors:
				var joined: Array = []
				if kind_at(c) == "barrier":
					joined = _barrier_groups[_group_of[c]]["rooms"]
				elif _is_gangway(c):
					joined = _door_rooms.get(c, [])
				for o in joined:
					if o.area_id < 0:
						o.area_id = next_id
						members.append(o)
			k += 1
		var b := members[0].bounds
		for m in members:
			b = b.merge(m.bounds)
		for m in members:
			m.area_bounds = b
		next_id += 1


## The game numbers the levels by file name (level_2.tscn is Level 2). If you
## copy a level to make a new one, change level_number too, or its results and
## autopilot routes would belong to the wrong level.
func _check_level_number() -> void:
	var file := scene_file_path.get_file()
	var m := RegEx.create_from_string("^level_(\\d+)\\.tscn$").search(file)
	if m and int(m.get_string(1)) != level_number:
		push_warning("%s has level_number %d: set it to %s (Inspector > Level)." % [file, level_number, m.get_string(1)])


## Friendly warnings in the Output panel when the map is missing something.
func _check_rooms() -> void:
	for r in _rooms:
		if r.is_exit or is_hall(r):
			continue
		var n := r.index + 1
		if r.airlock.x < 0:          # airlocks don't need pads
			if r.start.x < 0:
				push_warning("Room %d has no START pad." % n)
			if r.target().x < 0:
				push_warning("Room %d has no GOAL pad (or CORE)." % n)
		if _exit_doors(r).is_empty() and _barrier_groups_of(r).is_empty() and _links_from(r).is_empty():
			push_warning("Room %d has no door or barrier leading onward." % n)


## Doors that lead from room r to a later room (the ones r's goal opens).
## (Barriers work in groups instead: see _barrier_groups_of.)
func _exit_doors(r: Room) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in r.doors:
		if kind_at(d) != "door":
			continue
		for o in _door_rooms.get(d, []):
			if o != r and o.index > r.index:
				out.append(d)
				break
	return out


## In the game, pads are real nodes (PuzzleTile) so they can glow and spark.
func _spawn_runtime_tiles() -> void:
	# z_index = drawing order: lower is drawn first (further "down"). The player is 0,
	# so cables and pads are drawn under his feet.
	_conduit_root = _new_root("Conduits", -8)
	_tile_root = _new_root("PuzzleTiles", -7)
	_wire_root = _new_root("Wires", -5)
	for c in _kinds:
		var kind: String = _kinds[c]
		if not PUZZLE_FRAME.has(kind) or kind == "crate":
			continue
		var t := PuzzleTile.new()
		t.position = center_of(c)
		t.art_from_map = _art.has(c)      # the team's picture is on the Art layer already
		_tile_root.add_child(t)
		if kind == "door" and _is_gangway(c):
			t.setup(PuzzleTile.Kind.GANGWAY, _door_rotated(c))
		else:
			t.setup(PUZZLE_FRAME[kind], DOOR_KINDS.has(kind) and _door_rotated(c))
		_tiles[c] = t
		if kind == "blinker":
			_blinkers.append(c)
		if kind == "socket":
			_sockets.append(c)
	# movable crates draw themselves too (push_crate.gd)
	for c in _crate_homes:
		var k := PushCrate.new()
		k.home = c
		k.cell = c
		k.room = _room_of.get(c)
		k.position = center_of(c)
		k.art = _art_texture(c)           # the team's crate picture, if it was painted with one
		_tile_root.add_child(k)
		_crate_list.append(k)
		_crates[c] = k
	# fuses and the clamp lying on the floor draw themselves (pickup.gd)
	for c in _kinds:
		if _kinds[c] == "fuse" or _kinds[c] == "clamp":
			var p := Pickup.new()
			p.kind = _kinds[c]
			p.position = center_of(c)
			_tile_root.add_child(p)
			_pickups[c] = p


## Every "cell" tile becomes a PowerCell you can charge with the live wire.
func _spawn_power_cells() -> void:
	var spots: Array[Vector2i] = _floating_cells.duplicate()
	for c in _kinds:
		if _kinds[c] == "cell":
			spots.append(c)
	for c in spots:
		var cell := PowerCell.new()
		cell.position = center_of(c)
		_tile_root.add_child(cell)
		_cells[c] = cell
		var r: Room = _room_of.get(c)
		if r:
			r.power_cells.append(c)


func _new_root(root_name: String, z: int) -> Node2D:
	var n := Node2D.new()
	n.name = root_name
	n.z_index = z
	add_child(n)
	return n


## Levels with open space get a starfield behind everything.
func _setup_space() -> void:
	var count := 0
	var sum := Vector2.ZERO
	for c in _kinds:
		if _kinds[c] == "space":
			count += 1
			sum += center_of(c)
	if count == 0:
		return
	var sky_layer := CanvasLayer.new()
	sky_layer.name = "Sky"
	sky_layer.layer = -10        # behind the level, and untouched by its darkness
	add_child(sky_layer)
	var sky := Starfield.new()
	sky.focus = sum / count
	sky_layer.add_child(sky)


# ===================================================================== lighting

## The ship has no power: tint everything dark. Then add the flat "glow light"
## over the whole level, which only lights things that called LightFX.glow().
func _setup_darkness() -> void:
	_dark = CanvasModulate.new()
	_dark.color = darkness
	add_child(_dark)
	var area := Rect2(Vector2(_rect.position * TILE), Vector2(_rect.size * TILE))
	_glow_light = LightFX.make_glow_light(area)
	_glow_light.name = "GlowLight"
	add_child(_glow_light)


## Every room gets (a) a red emergency light that pulses while it has no power,
## and (b) a few ceiling lights that stay OFF until you power it.
## Outside rooms don't: the sun lights them, and they get hull beacons instead.
func _setup_room_lights() -> void:
	for r in _rooms:
		if r.is_exit or r.outside:
			continue
		var b := r.bounds
		# emergency light: top middle of the room, just under the wall panels
		var top := Vector2((b.position.x + b.size.x * 0.5) * TILE, (b.position.y + 4) * TILE)
		var red := LightFX.make(Color(1.0, 0.18, 0.12), 150.0, 0.5)
		red.position = top
		add_child(red)
		_emergency.append([red, r])
		# ceiling lights: spread evenly, roughly one per 7x7 tiles of floor
		var mn := Vector2(r.cells[0])
		var mx := mn
		for c in r.cells:
			mn = mn.min(Vector2(c))
			mx = mx.max(Vector2(c))
		var size := mx - mn + Vector2.ONE
		var nx := maxi(1, ceili(size.x / 7.0))
		var ny := maxi(1, ceili(size.y / 7.0))
		var lights: Array = []
		for j in ny:
			for i in nx:
				var spot := mn + Vector2((i + 0.5) * size.x / nx, (j + 0.5) * size.y / ny)
				var cell := Vector2i(spot.floor())
				if _room_of.get(cell) != r:
					cell = _nearest_room_cell(r, cell)    # U-shaped rooms: keep lights on floor
				var l := LightFX.make(Color(1.0, 0.95, 0.85), 210.0, 0.0)
				l.position = center_of(cell)
				l.visible = false       # invisible lights cost nothing
				add_child(l)
				lights.append(l)
		_room_lights[r] = lights


func _nearest_room_cell(r: Room, near: Vector2i) -> Vector2i:
	var best := r.cells[0]
	for c in r.cells:
		if Vector2(c - near).length_squared() < Vector2(best - near).length_squared():
			best = c
	return best


## Power on! Emergency light off, ceiling lights flicker on one after another.
func _power_room(r: Room) -> void:
	for pair in _emergency:
		if pair[1] == r:
			create_tween().tween_property(pair[0], "energy", 0.0, 0.4)
	var delay := 0.0
	for l in _room_lights.get(r, []):
		l.visible = true
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(l, "energy", room_light_energy, 0.06)
		tw.tween_property(l, "energy", 0.1, 0.06)
		tw.tween_property(l, "energy", room_light_energy, 0.08)
		tw.tween_property(l, "energy", 0.3, 0.05)
		tw.tween_property(l, "energy", room_light_energy, 0.25)
		delay += 0.15


## A hull section got power: navigation beacons start blinking along its edges.
func _light_hull(r: Room) -> void:
	var edge: Array[Vector2i] = []
	for c in r.cells:
		if kind_at(c) == "space":
			continue
		for d in DIRS4:
			if _is_void(c + d):
				edge.append(c)
				break
	edge.sort()
	var step := maxi(1, edge.size() / 6)
	var i := 0
	for k in range(0, edge.size(), step):
		var col := Color(0.35, 1.0, 0.55) if i % 2 == 0 else Color(1.0, 0.95, 0.8)
		var l := LightFX.make(col, 56.0, 0.0)
		l.position = center_of(edge[k])
		add_child(l)
		var dot := Node2D.new()
		dot.position = center_of(edge[k])
		dot.z_index = 4
		dot.draw.connect(func() -> void: dot.draw_rect(Rect2(-1, -1, 3, 3), col))
		LightFX.glow(dot)
		_tile_root.add_child(dot)
		_beacons.append([l, dot, i * 0.27, r])
		i += 1


## Inside: the dark ship and the ship music. Outside: the sunlit hull and space music.
func _update_environment(snap: bool) -> void:
	if _current_room == null:
		return
	var col := _env_color(_current_room, _ship_powered)
	if snap:
		if _env_tween:
			_env_tween.kill()
		_dark.color = col
	else:
		_tween_env(col, 1.2)
	if _music_override != "":
		_set_music(_music_override)
	elif _alert:
		_set_music("core")
	else:
		_set_music("space" if _current_room.outside else "ship")


## The darkness tint for room `r`. full = the whole ship has power.
func _env_color(r: Room, full: bool) -> Color:
	if r.outside:
		return space_light
	if _alert:
		return alert_light
	return full_power_light if full else darkness


## Fades the darkness tint to `col`. Kills the previous fade first, so two never fight.
func _tween_env(col: Color, secs: float) -> void:
	if _env_tween:
		_env_tween.kill()
	_env_tween = create_tween()
	_env_tween.tween_property(_dark, "color", col, secs)


## Draws an unpowered cable on the floor from each goal (or core) to the door it unlocks.
func _build_conduits() -> void:
	for r in _rooms:
		if r.target().x < 0:
			continue
		var targets := _exit_doors(r)
		for d in r.doors:
			if kind_at(d) == "barrier":
				targets.append(d)              # the cable also feeds the cargo lifts
		if targets.is_empty():
			continue
		var pts := _conduit_path(r, targets)
		if pts.size() < 2:
			continue
		var w := Wire.new(Wire.Style.CONDUIT)
		_conduit_root.add_child(w)
		w.set_points(pts)
		r.conduit = w


## Breadth-first search: explores outwards from the goal one tile at a time,
## remembering where it came from, until it reaches a tile next to a door.
## Following the "came from" links backwards gives the shortest path.
## (Cables can't cross open space, so they go round the hull.)
func _conduit_path(r: Room, doors: Array[Vector2i]) -> PackedVector2Array:
	var from := r.target()
	var prev := {from: from}
	var q: Array[Vector2i] = [from]
	var head := 0
	var found := false
	var end_cell := from
	var door := Vector2i.ZERO
	while head < q.size() and not found:
		var cur := q[head]
		head += 1
		for d in DIRS4:
			if doors.has(cur + d):
				found = true
				end_cell = cur
				door = cur + d
				break
		if found:
			break
		for d in DIRS4:
			var n := cur + d
			if prev.has(n) or _room_of.get(n) != r or kind_at(n) == "crate" or kind_at(n) == "space":
				continue
			prev[n] = cur
			q.append(n)
	var pts := PackedVector2Array()
	if not found:
		return pts
	var cells: Array[Vector2i] = []
	var c := end_cell
	while c != from:
		cells.append(c)
		c = prev[c]
	cells.append(from)
	cells.reverse()
	for cc in cells:
		pts.append(center_of(cc))
	pts.append((center_of(end_cell) + center_of(door)) * 0.5)
	return _simplify(pts)


## Keeps only the corner points of a path (drops points in the middle of straight runs).
func _simplify(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var a := (pts[i] - out[out.size() - 1]).normalized()
		var b := (pts[i + 1] - pts[i]).normalized()
		if not a.is_equal_approx(b):
			out.append(pts[i])
	out.append(pts[pts.size() - 1])
	return out


# ===================================================================== sound and music

func _setup_audio() -> void:
	for n in SOUNDS:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx_" + n
		var path := "res://Assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			p.stream = load(path)
		add_child(p)
		_sfx[n] = p
	_sfx["hum"].volume_db = -12.0
	_sfx["tick"].volume_db = -6.0
	_sfx["alarm"].volume_db = -6.0
	_sfx["hum"].finished.connect(_on_hum_finished)   # loop the hum while carrying
	# Background music (the team's tracks, listed in Game.MUSIC): inside the
	# ship, out on the hull, the rogue PIP fight, and the ending. One player
	# each, all silent at first; _set_music() fades between them.
	for n in Game.MUSIC:
		if n == "title":
			continue                     # that one's for the title screen
		var p := AudioStreamPlayer.new()
		p.name = "Music_" + n
		p.stream = Game.load_music(n)
		p.volume_db = -80.0
		add_child(p)
		_music[n] = p


## Sounds you hear again and again get a slightly different pitch each time
## (Juice.pitch), so they sound natural instead of like a recording on repeat.
## Tunes (fanfare, power-up, the level's last chord) always play as written.
const PITCH_VARIED := ["node", "bend", "clank", "push", "pickup", "grab", "puff", "door", "snap", "shock"]


## Plays sound `n`. `pitch` > 0 plays it at that pitch instead.
func _play(n: String, pitch := 0.0) -> void:
	var p: AudioStreamPlayer = _sfx.get(n)
	if p and p.stream:
		if pitch > 0.0:
			p.pitch_scale = pitch
		elif n in PITCH_VARIED:
			p.pitch_scale = Juice.pitch()
		p.play()


func _set_hum(on: bool) -> void:
	var p: AudioStreamPlayer = _sfx.get("hum")
	if p == null or p.stream == null:
		return
	if on:
		p.play()
	else:
		p.stop()


func _on_hum_finished() -> void:
	if _wire != null and not _busy:
		_sfx["hum"].play()


## Something else decides the music for now: rogue_pip.gd plays "ending" once
## PIP is back, or "none" for silence while he reboots. "" = back to normal
## (the room decides: ship / space / core).
func set_music_override(which: String) -> void:
	_music_override = which
	if which == "":
		_update_environment(false)
	else:
		_set_music(which)


## Cross-fade: the new music fades in while the old one fades out.
## ("none", or any name that isn't a track, fades everything out.)
func _set_music(which: String) -> void:
	if which == _music_now:
		return
	_music_now = which
	for n in _music:
		var p: AudioStreamPlayer = _music[n]
		if p.stream == null:
			continue
		if _music_tweens.has(n):
			_music_tweens[n].kill()          # stop a fade that's still running
		var tw := create_tween()
		_music_tweens[n] = tw
		if n == which:
			if not p.playing:
				p.play()
			tw.tween_property(p, "volume_db", float(Game.MUSIC[n]), 2.0)
		else:
			tw.tween_property(p, "volume_db", -80.0, 2.0)
			tw.tween_callback(p.stop)


# ===================================================================== every frame

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or player == null:
		return
	_input_cooldown = maxf(0.0, _input_cooldown - delta)
	if _complete:
		_results_input()
		return
	if not _cutscene:
		_play_time += delta         # the cutscene doesn't count towards your time
	_strain_cd = maxf(0.0, _strain_cd - delta)
	_drift_warn_cd = maxf(0.0, _drift_warn_cd - delta)
	if _busy or _dialogue_lock:
		_update_prompts()
		return
	if _input_cooldown <= 0.0 and not autopilot_on:
		if Input.is_action_just_pressed("restart"):
			_fail("restart")
			return
		if Game.judge_mode and Input.is_action_just_pressed("autopilot"):
			start_autopilot()           # judge mode: P = PIP walks this room for you
			return
		if Input.is_action_just_pressed("hint"):
			_try_hint()
	# a blinking grate can light up under you while you stand still (not on autopilot)
	if player.state != Astronaut.State.LOCKED and _is_live_tile(cell_of(player.position)) and not autopilot_on:
		_shock()
		return
	if _tick_o2(delta):
		return
	if _wire != null and player.is_wired():
		# E while walking with the wire = reel back to the last pad it's wrapped round
		var walking := player.state == Astronaut.State.WIRED
		if walking and _input_cooldown <= 0.0 and Input.is_action_just_pressed("interact") and not autopilot_on:
			_reel_back()
		# stood still a moment away from the last pad? remind them they can reel back
		_still_time = _still_time + delta if walking and not player.is_moving() else 0.0
		hud.set_reel_prompt(_still_time > 0.7 and player.position.distance_to(_last_anchor) > 24.0)
		_tick_timer(delta)
	else:
		hud.set_timer(false, 0.0, 0.0)
		hud.set_reel_prompt(false)
		if player.state == Astronaut.State.FREE and _input_cooldown <= 0.0 and Input.is_action_just_pressed("interact") \
				and not autopilot_on:
			_try_grab()
			if _wire == null:
				_try_clamp()                # not on a START: maybe next to a clamp socket
		# stranded? keep checking: if you find a safe way back, the [R] goes away
		if _stranded:
			_stranded_check -= delta
			if _stranded_check <= 0.0:
				_stranded_check = 0.5
				_check_stranded(_current_room)
	_update_prompts()


func _timer_paused() -> bool:
	return _paused_node.x >= 0 and _node_hold_left > 0.0


## NODE REST (the dev menu switch, Game.node_rest): the wire is latched on a
## node (that node is the last thing it touched, no pole after it) and you're
## within node_rest_radius of it. Then the timer waits for as long as you like.
func _node_rest() -> bool:
	if not Game.node_rest or _anchor_cells.is_empty():
		return false
	var c: Vector2i = _anchor_cells[-1]
	return kind_at(c) == "node" and player.position.distance_to(center_of(c)) <= node_rest_radius


func _tick_timer(delta: float) -> void:
	# PIP's autopilot never runs out of time, and neither does a node rest
	var paused := _timer_paused() or autopilot_on or _node_rest()
	if _timer_paused():
		_node_hold_left -= delta        # a node only holds the timer for so long
	elif not paused:
		_time_left -= delta
	var frac := clampf(_time_left / _max_time(), 0.0, 1.0)
	_wire.set_urgency(1.0 - frac)
	hud.set_timer(true, frac, maxf(_time_left, 0.0), paused)
	if _time_left < 1.5 and not paused:
		_tick_accum += delta
		if _tick_accum >= 0.25:
			_tick_accum = 0.0
			_play("tick")
	if _time_left <= 0.0:
		_fail("timeout")


## Oxygen drains while you're outside the ship. Returns true if it just ran out.
func _tick_o2(delta: float) -> bool:
	if not _o2_on or _current_room == null or not _current_room.outside or autopilot_on:
		return false
	_o2 -= delta
	hud.set_o2(true, _o2 / _o2_max)
	if _o2 < _o2_max * 0.3 and not _o2_warned:
		_o2_warned = true
		_pip_say(pip_o2_low)
	if _o2 < _o2_max * 0.15:
		_o2_beep -= delta
		if _o2_beep <= 0.0:
			_o2_beep = 1.0
			_play("alarm")
	if _o2 <= 0.0:
		_fail("oxygen")
		return true
	return false


func _refill_o2() -> void:
	_o2 = _o2_max
	_o2_warned = false
	hud.set_o2(_o2_on, 1.0)


# _process runs every drawn frame: good for things that are only visual.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_tick_live_preview(delta)     # the editor's blinking grates
		return
	if player == null:
		return
	if _wire != null and player.is_wired():
		_wire.set_live_end(player.hand_position())
	# unpowered rooms: the red emergency lights slowly pulse
	_light_t += delta
	for pair in _emergency:
		var r: Room = pair[1]
		if _alert:
			pair[0].energy = 0.55 + 0.35 * sin(_light_t * 6.0)    # red alert: every room flashes
		elif not r.solved and not r.full_power:
			pair[0].energy = 0.35 + 0.2 * sin(_light_t * 2.2)
	# powered hull sections: beacons blink one after another
	# (in the cutscene a section's beacons flash all together for a moment)
	for b in _beacons:
		var on := fmod(_light_t + float(b[2]), 1.6) < 0.3
		var flare: bool = _beacon_flare.get(b[3], 0.0) > _light_t
		if flare:
			on = int(_light_t * 10.0) % 2 == 0
		b[0].energy = (1.4 if flare else 0.8) if on else 0.05
		b[1].visible = on
	_update_blinkers()
	_update_camera(delta, false)


## Called by the player every time he moves. All the "did something happen?" checks.
func player_moved() -> void:
	if _busy or _complete:
		return
	if _safe_to_stand(player.position):
		_last_safe = player.position      # remembered, so a zap sends you back the way you came
	var c := cell_of(player.position)
	if _is_live_tile(c) and not autopilot_on:
		_shock()
		return
	_check_cells()
	_check_dungeon()                    # fuses, the clamp, fuse doors
	if player.state == Astronaut.State.FREE:
		var r: Room = _room_of.get(c)
		if r != null and r != _current_room:
			_enter_room(r)
			return
		if _current_room != null and _current_room.airlock.x >= 0 and not _current_room.cycled:
			if player.position.distance_to(center_of(_current_room.airlock)) <= AIRLOCK_RADIUS:
				_cycle_airlock(_current_room)
		return
	if _wire == null:
		return
	# Standing on a node pauses the timer; it starts again once you step off.
	# "On it" is the same test as touching it (feet, or a bit higher up), else
	# coming at a node from below would step you off it the moment you touch it.
	if _paused_node.x >= 0 and not _touching(center_of(_paused_node), NODE_RADIUS + 4.0):
		_set_paused_node(Vector2i(-1, -1))
	# Did the wire sweep across a pole (wrap round it), or back again (unwrap)?
	_update_wraps(_prev_feet, player.position)
	_prev_feet = player.position
	# Did we touch a pad we haven't used yet?
	for pad in _wire_pads:
		if _anchor_cells.has(pad):
			continue
		var kind := kind_at(pad)
		var radius := NODE_RADIUS if kind == "node" else GOAL_RADIUS
		var pc := center_of(pad)
		if not _touching(pc, radius):
			continue
		if not _line_clear(_last_anchor, pc):
			continue          # the wire can't reach that pad's centre
		_touch_pad(pad, kind)
		return
	_check_loop()


# ===================================================================== the core: wrap the wire round it

## How far the wire winds round room r's core, in radians (TAU = one full turn).
## The wire is straight lines: START -> each pad it's wrapped round -> your hands.
## Stand on the core and look at one straight piece: it sweeps some angle in
## front of you (angle_to gives it, with a sign for which way round). Add the
## pieces up. Going round and coming back cancels out; a full loop adds to TAU.
func _winding(r: Room) -> float:
	var c := center_of(r.core)
	var pts: Array[Vector2] = []
	for a in _anchor_cells:
		pts.append(center_of(a))
	pts.append(player.hand_position())
	var total := 0.0
	for i in range(1, pts.size()):
		total += (pts[i - 1] - c).angle_to(pts[i] - c)
	return total


## While you carry the wire in a core room: update the ring on the socket, and
## power the room once the wire has gone all the way round.
func _check_loop() -> void:
	var r := _wire_room
	if r == null or r.core.x < 0 or _wire == null or _busy:
		return
	var turn := _winding(r)
	var t: PuzzleTile = _tiles.get(r.core)
	if t:
		t.show_loop(true, (center_of(r.start) - center_of(r.core)).angle(), turn)
	if absf(turn) >= TAU:
		_plug_into_core(r)


## The loop is closed: the loose end leaves your hands and plugs into the core,
## so the wire ends IN the machine instead of hanging in the air. Then the room
## powers up as usual.
func _plug_into_core(r: Room) -> void:
	_busy = true                  # no more moves, fails or loop checks while it flies
	player.lock(true)
	var w := _wire
	_wire = null                  # (else _process keeps pinning the end to his hands)
	var hand := player.hand_position()
	var socket := center_of(r.core)
	w.add_anchor(hand)            # the loop's last bend stays where your hands were
	w.set_live_end(hand)
	var tw := create_tween()
	tw.tween_method(w.set_live_end, hand, socket, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	if not is_inside_tree():
		return
	w.add_anchor(socket)
	_play("clank")
	_wire = w
	_solve(r)


func _hide_loop(r: Room) -> void:
	if r == null or r.core.x < 0:
		return
	var t: PuzzleTile = _tiles.get(r.core)
	if t:
		t.show_loop(false, 0.0, 0.0)


## Where each core room's socket is, in walking order: [room index, pixel position].
## rogue_pip.gd uses this to know where to dock.
func core_spots() -> Array:
	var out: Array = []
	for r in _rooms:
		if r.core.x >= 0:
			out.append([r.index, center_of(r.core)])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return out


## The same, but for previews in the editor (rogue_pip.gd): works the rooms out
## from the map as it's painted right now. "quiet" = no warnings in the Output
## panel about rooms you're still busy painting.
func editor_core_spots() -> Array:
	if _kinds.is_empty():
		_read_layout()
	_build_rooms(true)
	return core_spots()


## The room you're carrying the wire in right now (-1 = you aren't carrying it).
func wire_room_index() -> int:
	return _wire_room.index if _wire != null and _wire_room != null and not _busy else -1


## PIP's shutdown pulse (rogue_pip.gd) cuts the wire you're carrying.
func cut_wire() -> void:
	if _wire != null and not _busy:
		_fail("cut")


## Red alert on/off: the ship goes red, the emergency lights flash in every
## room and the boss music plays (off: back to normal).
func set_alert(on: bool) -> void:
	_alert = on
	for r in _rooms:
		for l in _room_lights.get(r, []):
			if r.solved:
				create_tween().tween_property(l, "energy", 0.12 if on else room_light_energy, 0.4)
	if not on:
		for pair in _emergency:
			if pair[1].solved:
				create_tween().tween_property(pair[0], "energy", 0.0, 0.6)
	_update_environment(false)


## Shake the camera (other scripts can't reach _shake_cam: names starting with
## _ are "private" by convention).
func shake(duration: float, strength: float) -> void:
	_shake_cam(duration, strength)


## Another node asks the level to wait before it carries on after a room is
## powered (before it opens the doors and starts the lights-on cutscene).
## Like holding a lift door: the level waits until everyone has let go.
## rogue_pip.gd holds while PIP glitches, gets rebooted or flies away.
func hold() -> void:
	_holds += 1


func let_go() -> void:
	_holds = maxi(0, _holds - 1)


func _wait_for_holds() -> void:
	while _holds > 0 and is_inside_tree():
		await get_tree().process_frame


## Is the astronaut touching the spot `pc`? Measured from his feet and from a
## bit higher up his body (see BODY_UP), so it matches what you see on screen.
func _touching(pc: Vector2, radius: float) -> bool:
	return _touching_at(player.position, pc, radius)


func _touching_at(feet: Vector2, pc: Vector2, radius: float) -> bool:
	return feet.distance_to(pc) <= radius or (feet + Vector2(0, -BODY_UP)).distance_to(pc) <= radius


# ===================================================================== poles: the wire wraps round them
# Think of a rope tied at the last pad, running straight to your hands. If you
# walk so that the rope would swing across a post, the post catches it: the
# rope now bends there, and the straight part starts from the post. Walk back
# the other way and it comes off the post again.
#
# How we spot that, every time you move from `from` to `to`:
#   wrap:   the wire used to run (anchor -> from) and now runs (anchor -> to).
#           It swept across the triangle between those three points. If a
#           pole's centre is inside that triangle, the wire hit it.
#   unwrap: the wire bends round the last pole P (coming from Q before it).
#           cross(P - Q, hands - P) says which side of the line Q->P your hands
#           are on. When that side flips, the wire has straightened out again.

## Called from player_moved() while you carry the wire.
func _update_wraps(from: Vector2, to: Vector2) -> void:
	if from.is_equal_approx(to) or autopilot_wraps:
		return
	# unwrap first (maybe several poles in a row came free). _poles also has
	# the clamp while it stands in a socket, so it comes off the same way.
	while _anchor_cells.size() >= 2 and _poles.has(_anchor_cells[-1]):
		var p := center_of(_anchor_cells[-1])
		var q := center_of(_anchor_cells[-2])
		var side := signf((p - q).cross(to - p))
		if side == 0.0 or side == _anchor_signs[-1] or not _line_clear(q, to):
			break
		_anchor_cells.pop_back()
		_anchor_signs.pop_back()
		_last_anchor = q
		_wire.remove_last_anchor()
	# then wrap: the pole the sweep reaches first (smallest angle from the old wire)
	var a := _last_anchor
	var best := Vector2i(-1, -1)
	var best_angle := INF
	for pole in _poles:
		if not _anchor_cells.is_empty() and _anchor_cells[-1] == pole:
			continue
		var pc := center_of(pole)
		if pc.distance_to(a) < 2.0 or not _swept_over(pc, a, from, to):
			continue
		var ang := absf((from - a).angle_to(pc - a))
		if ang < best_angle:
			best_angle = ang
			best = pole
	if best.x < 0:
		return
	var pc := center_of(best)
	_anchor_cells.append(best)
	_anchor_signs.append(signf((from - a).cross(to - a)))   # which way the wire was swinging
	_last_anchor = pc
	_wire.add_anchor(pc)
	_tile_hit(best)
	_play("bend")
	pad_touched.emit("pole", _wire_room.index)     # the tutorial listens for this


## Did the wire, swinging round anchor a from (a -> from) to (a -> to), pass
## over point p? True if p is inside that triangle, or on the new wire, but not
## on the old wire (it was already lying there). A swing of no width (you
## walked straight along the wire) doesn't count.
func _swept_over(p: Vector2, a: Vector2, from: Vector2, to: Vector2) -> bool:
	var turn := (from - a).cross(to - a)
	if absf(turn) < 0.001:
		return false
	var s := signf(turn)
	return (from - a).cross(p - a) * s > 0.0 and (to - from).cross(p - from) * s >= 0.0 \
		and (a - to).cross(p - to) * s >= 0.0


## Reel back. Press E while carrying the wire and it pulls you back along the
## wire to the last pad it's wrapped round (the START or a node), unwrapping
## any poles on the way. The timer keeps running while you fly, so it costs a
## little time, but you never have to stand there waiting for it to run out.
func _reel_back() -> void:
	if _anchor_cells.is_empty():
		return
	# the way back: past each pole (just outside it, where the wire runs), then the pad
	var path: Array[Vector2] = []
	var hand := player.position
	var i := _anchor_cells.size() - 1
	while i > 0 and _poles.has(_anchor_cells[i]):
		var p := center_of(_anchor_cells[i])
		var q := center_of(_anchor_cells[i - 1])
		var out := -((q - p).normalized() + (hand - p).normalized())
		path.append(p + (out.normalized() if out.length() > 0.01 else (hand - p).normalized()) * 20.0)
		hand = p
		i -= 1
	var target := center_of(_anchor_cells[i])
	path.append(target)
	var dist := 0.0
	var at := player.position
	for pt in path:
		dist += at.distance_to(pt)
		at = pt
	if dist < 6.0:
		return
	player.lock(true)
	_play("puff")
	_wire.strain(player.hand_position())              # a flash and sparks at your hands
	_reel_tween = create_tween()
	at = player.position
	for pt in path:
		var secs := clampf(at.distance_to(pt) / 420.0, 0.05, 0.7)
		_reel_tween.tween_property(player, "position", pt, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		at = pt
	await _reel_tween.finished
	if not is_inside_tree(): return
	_reel_tween = null
	if _wire == null or _busy:
		return                                        # the timer ran out on the way
	# the poles came off on the way back
	while _anchor_cells.size() > i + 1:
		_anchor_cells.pop_back()
		_anchor_signs.pop_back()
		_wire.remove_last_anchor()
	_last_anchor = target
	_prev_feet = player.position
	player.grab_wire()                                # walking with the wire again
	var c: Vector2i = _anchor_cells[-1]
	if kind_at(c) == "node":
		_set_paused_node(c)                           # back on a node: it holds the timer again
		_node_hold_left = _node_hold()
	_play("clank")
	player.squash(Vector2(1.2, 0.82), 0.18)          # a bump as the wire stops pulling


## Charge any power cell you're touching, but only with the live wire in hand.
func _check_cells() -> void:
	if _cells.is_empty():
		return
	var wired := _wire != null and player.is_wired()
	for c in _cells:
		var cell: PowerCell = _cells[c]
		if cell.collected or not _touching(center_of(c), CELL_RADIUS):
			continue
		if wired and _room_of.get(c) == _wire_room:
			# The battery's charge goes into the wire: more time, right now.
			cell.collect("+%ds" % int(_cell_bonus()))
			_time_left = minf(_time_left + _cell_bonus(), _max_time())
			hud.pulse_timer()
			_cells_pending.append(c)
			# each cell on the same try sounds a little higher: a rising "combo"
			_play("pickup", 1.0 + 0.07 * (_cells_pending.size() - 1))
			hud.set_cells(_cells_banked + _cells_pending.size(), _cells.size(), true)
			if Game.first_time("cell_charged"):
				hud.show_toast(popup_cell_bonus.format({"bonus": int(_cell_bonus())}), 2.5)
			cell_collected.emit(_wire_room.index)
		elif not wired and not _cell_tip_shown:
			_cell_tip_shown = true
			empty_cell_touched.emit()        # PIP explains (a StoryBeat listens for this)


func _touch_pad(c: Vector2i, kind: String) -> void:
	var pc := center_of(c)
	var came_from := _last_anchor
	_anchor_cells.append(c)
	_anchor_signs.append(0.0)
	_last_anchor = pc        # the tight wire now starts from this pad
	_wire.add_anchor(pc)
	_tile_hit(c)
	pad_touched.emit(kind, _wire_room.index)     # the tutorial listens for this
	match kind:
		"node":
			_time_left = minf(_time_left + _node_time(), _max_time())
			_set_paused_node(c)
			_node_hold_left = _node_hold()    # it holds the timer for a moment
			_play("node")
			player.squash(Vector2(0.9, 1.12), 0.15)
			hud.pulse_timer()
		"goal":
			_solve(_wire_room)


func _set_paused_node(c: Vector2i) -> void:
	if _paused_node.x >= 0:
		var old: PuzzleTile = _tiles.get(_paused_node)
		if old:
			old.active = false
	_paused_node = c
	if c.x >= 0:
		var t: PuzzleTile = _tiles.get(c)
		if t:
			t.active = true


## Called by the player when the tight wire stops him walking somewhere.
func wire_strained(at: Vector2) -> void:
	if _wire == null or _strain_cd > 0.0:
		return
	_strain_cd = 0.4
	_wire.strain(_first_blocked_point(_last_anchor, at))
	_play("tick")
	if Game.first_time("strain"):
		_pip_say(pip_strain)     # the first time ever: why it stopped you


# ===================================================================== spacewalk: drifting

## Asked by the player when he walks into open space: if he pushed off in
## direction `dir`, where would he land? Steps 2 px at a time across the gap.
## Returns Vector2.INF ("nowhere") if there's no hull straight ahead, if he'd
## crash into something on the way, or if the wire would snag.
func drift_landing(from: Vector2, dir: Vector2, half: Vector2, wired: bool) -> Vector2:
	var p := from
	var crossed := false
	var travelled := 0.0
	while travelled < MAX_DRIFT:
		p += dir * 2.0
		travelled += 2.0
		if box_blocked(p, half, false):
			return Vector2.INF            # debris, a wall, or the edge of the map
		if wired and not wire_reaches(p):
			return Vector2.INF            # the wire would catch on something
		if box_blocked(p, half, true):
			crossed = true                # still over open space
		elif crossed:
			return p                      # boots back over solid hull: land here
	return Vector2.INF


func player_drift_begin(dir: Vector2) -> void:
	_play("puff")
	# stretched out along the way he pushes off
	player.squash(Vector2(1.25, 0.8) if absf(dir.x) > 0.5 else Vector2(0.8, 1.25), 0.25)
	var puff := Wire.make_sparks(Color(0.85, 0.92, 1.0), 12, 0.45)   # suit thruster puff
	puff.one_shot = true
	puff.explosiveness = 0.9
	puff.gravity = Vector2.ZERO
	puff.direction = -dir
	puff.spread = 25.0
	puff.position = player.position + Vector2(0, -12)
	_wire_root.add_child(puff)
	puff.emitting = true
	get_tree().create_timer(1.0).timeout.connect(puff.queue_free)
	drift_started.emit(room_index_at(player.position))


func player_drift_end() -> void:
	_play("clank")                        # mag boots grab the hull
	_shake_cam(0.08, 1.0)
	player.squash(Vector2(1.3, 0.72), 0.2)
	_dust_at(player.position)


## The player pushed towards open space but can't go. Show why.
func player_drift_refused(at: Vector2, dir: Vector2) -> void:
	if _drift_warn_cd > 0.0:
		return
	_drift_warn_cd = 0.8
	if player.is_wired() and drift_landing(at, dir, Astronaut.FEET_HALF, false).is_finite():
		wire_strained(at + dir * 24.0)    # there is a landing: it's the wire that's in the way
		return
	_play("tick")
	# a short red dotted line out into space: "you'd float away"
	var warn := Node2D.new()
	warn.z_index = 10
	var draw_dots := func() -> void:
		for i in range(1, 6):
			warn.draw_rect(Rect2(at + dir * (6.0 + i * 10.0) + Vector2(-1, -11), Vector2(3, 3)), Color(1.0, 0.3, 0.25))
	warn.draw.connect(draw_dots)
	LightFX.glow(warn)
	_wire_root.add_child(warn)
	var tw := warn.create_tween()
	tw.tween_property(warn, "modulate:a", 0.0, 0.6)
	tw.tween_callback(warn.queue_free)
	if not _drift_tip_shown:
		_drift_tip_shown = true
		_pip_say(pip_no_landing)


# ===================================================================== rooms, hints, prompts

func _update_prompts() -> void:
	for r in _rooms:
		if r.start.x < 0:
			continue
		var t: PuzzleTile = _tiles.get(r.start)
		if t:
			t.prompt = (not _busy and not _dialogue_lock and player.state == Astronaut.State.FREE and not r.solved
				and r == _current_room and player.position.distance_to(center_of(r.start)) <= START_RADIUS)
	# the [E] key over a clamp socket you could use right now
	var free := not _busy and not _dialogue_lock and player.state == Astronaut.State.FREE
	var reach := _socket_in_reach() if free else Vector2i(-1, -1)
	for s in _sockets:
		var t: PuzzleTile = _tiles.get(s)
		if t:
			t.prompt = s == reach


func _enter_room(r: Room) -> void:
	var new_area := _current_room == null or _current_room.area_id != r.area_id
	_current_room = r
	_entered_at[r] = player.position    # R in a hall with crates brings you back here
	_visited[r] = true
	if r.is_exit:
		_finish_level()
		return
	player.set_lamp(not r.solved)   # dark room = helmet lamp on, powered room = off
	if r.outside and _o2_on and not r.solved:
		_refill_o2()                # every new hull section has an oxygen port
	_update_environment(false)
	_update_hint_label()
	if new_area:
		_announce_room()            # the next stage of the same area gets no popup
	room_entered.emit(r.index)
	_point_out_crates(r)


## The first time you walk into a room, PIP points at every crate in it that
## moves (they look just like the bolted-down ones, so you'd never guess).
## Nearest first, one line each, and never while the autopilot is driving.
func _point_out_crates(r: Room) -> void:
	if _crates_shown.has(r) or r.solved or autopilot_on:
		return
	_crates_shown[r] = true
	var here: Array[Vector2i] = []
	for c in _crates:
		if room_index_at(center_of(c)) == r.index:
			here.append(c)
	here.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return center_of(a).distance_to(player.position) < center_of(b).distance_to(player.position))
	for i in mini(here.size(), 4):         # 4 lines at most, so PIP doesn't go on forever
		_pip_say(pip_crate_spot if i == 0 else pip_crate_spot_more, center_of(here[i]))


func _announce_room() -> void:
	if _current_room == null or _current_room.is_exit:
		return
	var i := _current_room.index
	var title := room_titles[i] if i >= 0 and i < room_titles.size() else "ROOM %d" % (i + 1)
	hud.show_toast(title)


## Does this room have a hint route (a FloorGuide with "Hint Only" ticked)?
func _room_has_hint(r: Room) -> bool:
	if r == null or r.solved:
		return false
	for g in get_tree().get_nodes_in_group("hint_guide"):
		if g is FloorGuide and g.room_index() == r.index:
			return true
	return false


func _update_hint_label() -> void:
	hud.set_hint_available(_room_has_hint(_current_room) and not _hints_shown.has(_current_room))


func _try_hint() -> void:
	var r := _current_room
	if not _room_has_hint(r) or _hints_shown.has(r):
		return
	_hints_shown[r] = true
	_hints_used += 1
	hint_shown.emit(r.index)        # the room's hint guide fades in
	hud.show_toast(popup_hint)
	_update_hint_label()


func _try_grab() -> void:
	var r := _current_room
	if r == null or r.solved or r.start.x < 0:
		return
	var sc := center_of(r.start)
	if player.position.distance_to(sc) > START_RADIUS:
		return
	_clear_stranded()
	_wire_room = r
	_wire_pads = _stage_pads(r)
	_anchor_cells = [r.start]
	_anchor_signs = [0.0]
	_last_anchor = sc
	_prev_feet = player.position
	_set_paused_node(Vector2i(-1, -1))
	_wire = Wire.new(Wire.Style.CABLE)
	_wire_root.add_child(_wire)
	_wire.begin(sc)
	_wire.set_live_end(player.hand_position())
	player.grab_wire()
	_time_left = _wire_time()     # the timer starts right away on the START pad
	_tick_accum = 0.0
	_play("grab")
	player.squash(Vector2(1.15, 0.87), 0.16)
	_set_hum(true)
	_tile_hit(r.start)
	_show_shared_pads(r)
	wire_grabbed.emit(r.index)      # the tutorial listens for this


## Nodes from stages you already powered in this area work for this
## wire too, but they're easy to miss. So when you grab the wire, each of them
## flashes, one after another. The first time ever, PIP points one out.
func _show_shared_pads(r: Room) -> void:
	var shared: Array[Vector2i] = []
	for p in _wire_pads:
		if not r.pads.has(p):
			shared.append(p)
	if shared.is_empty():
		return
	if Game.first_time("shared_pads"):
		_pip_say(pip_shared, center_of(shared[0]))
	for i in shared.size():
		var t: PuzzleTile = _tiles.get(shared[i])
		if t:
			get_tree().create_timer(0.15 + i * 0.12).timeout.connect(t.hit)


func _tile_hit(c: Vector2i) -> void:
	var t: PuzzleTile = _tiles.get(c)
	if t:
		t.hit()


# ===================================================================== dialogue

## PIP says one of his rule lines (the pip_... texts in the Inspector, group
## "PIP's rule lines"). {cells}, {o2_bonus} and {o2_per_cell} get the real
## numbers. An empty line = PIP keeps quiet. `point_at` = his blue arrow.
func _pip_say(text: String, point_at := Vector2.INF) -> void:
	if text.strip_edges() == "":
		return
	hud.say(PackedStringArray([text.format(Game.story_values())]), "PIP", false, point_at)


## PIP started / stopped a speech the player has to read: freeze / unfreeze him.
func _on_dialogue_blocking(on: bool) -> void:
	_dialogue_lock = on
	if on:
		if player.state == Astronaut.State.FREE:
			player.lock(false)
	else:
		_input_cooldown = 0.25        # the E that closed the speech shouldn't grab the wire
		if not _busy and not _complete and player.state == Astronaut.State.LOCKED:
			player.release()


## Story beats ask this before freezing the player: never while he carries the wire.
func can_pause_for_dialogue() -> bool:
	return _wire == null and not _complete and not autopilot_on


## Give control back, unless PIP is still talking (then he's released when PIP stops).
func _release_player() -> void:
	if _dialogue_lock:
		player.lock(false)
	else:
		player.release()


# ===================================================================== win / lose
# These use `await`: the function pauses at that line until the animation or
# timer finishes, then carries on. Meanwhile the rest of the game keeps running.

func _solve(r: Room) -> void:
	_busy = true
	player.lock(true)
	_set_hum(false)
	_set_paused_node(Vector2i(-1, -1))
	r.solved = true
	var kept := _cells_pending.size()
	_cells_banked += kept                     # cells charged on this try are yours to keep
	_cells_pending.clear()
	_rooms_powered += 1
	hud.set_timer(false, 0.0, 0.0)
	_play("powerup")
	_shake_cam(0.2, 1.5)
	Juice.hitstop(0.07)                       # a beat of stillness: you did it
	player.squash(Vector2(0.85, 1.18), 0.25)  # ...and he stands up tall
	var w := _wire
	_wire = null
	w.finish()
	await w.power_flow(0.8)
	if not is_inside_tree(): return
	_hide_loop(r)
	for c in [r.goal, r.start, r.core]:
		var t: PuzzleTile = _tiles.get(c)
		if t:
			t.set_powered(true)
	_show_goal_art(r.goal, true)
	if r.outside:
		_light_hull(r)              # beacons start blinking
		_refill_o2()                # ...and the relay tops up your suit
		hud.show_toast(popup_relay_online)
	else:
		_power_room(r)              # the lights come on!
		hud.show_toast(popup_power_on)
	player.set_lamp(false)          # ...so he doesn't need his helmet lamp any more
	hud.set_power(_rooms_powered, _rooms_with_goal)
	_update_hint_label()
	room_solved.emit(r.index)       # the tutorial, story and floor guides listen for this
	if kept > 0 and Game.first_time("cell_kept"):
		_pip_say(pip_cell_kept)
	if r.conduit:
		await r.conduit.power_flow(0.5)
		if not is_inside_tree(): return
	await _wait_for_holds()         # e.g. PIP glitching (rogue_pip.gd called hold())
	if not is_inside_tree(): return
	_open_exit_doors(r)
	await _apply_links(r)           # power links: things change elsewhere (the camera glances over)
	if not is_inside_tree(): return
	if _rooms_powered >= _rooms_with_goal:
		await _all_powered()        # the lights-on cutscene: wait here until it's over
		if not is_inside_tree(): return
	_busy = false
	_release_player()


# ===================================================================== RPG: skills
# Skills (SkillManager) change the rules a little, so every rule they touch
# asks one of these small functions instead of reading wire_time or
# cell_bonus directly.

## Seconds on the wire timer from the START: this room's time (room_wire_time,
## or else wire_time) + skills. Never above _max_time().
func _wire_time() -> float:
	var t := wire_time
	if _wire_room != null and _wire_room.index < room_wire_time.size() and room_wire_time[_wire_room.index] > 0.0:
		t = room_wire_time[_wire_room.index]
	return minf(t + SkillManager.bonus("wire_time"), _max_time())


## Seconds a NODE adds: node_time + skills.
func _node_time() -> float:
	return node_time + SkillManager.bonus("node_time")


## The most the timer can ever hold: max_wire_time + skills. (LONGER WIRE
## raises it too, so a longer START is never cut off by the cap.)
func _max_time() -> float:
	return max_wire_time + SkillManager.bonus("max_time") + SkillManager.bonus("wire_time")


## How long a NODE holds the clock while you stand on it: node_hold + skills.
func _node_hold() -> float:
	return node_hold + SkillManager.bonus("node_hold")


## Seconds a battery adds: cell_bonus + the SUPER CELLS skills.
func _cell_bonus() -> float:
	return cell_bonus + SkillManager.bonus("cell_bonus")


## You stepped on something live (a red tile or a lit grate). With the RUBBER
## BOOTS skill the first zap in each room doesn't count (INSULATED SOLES: the
## first two): a spark, and you hop back to the last spot you stood on safely.
## You even keep the wire.
func _shock() -> void:
	var r := _current_room
	var can_hop := player.state in [Astronaut.State.FREE, Astronaut.State.WIRED]
	var saves := int(SkillManager.bonus("boots"))
	if r != null and int(_boots_used.get(r, 0)) < saves and can_hop and _last_safe.is_finite():
		_boots_used[r] = int(_boots_used.get(r, 0)) + 1
		_sparks_at(player.position + Vector2(0, -4))     # sparks where the zap hit
		player.position = _last_safe
		_play("shock")
		_shake_cam(0.2, 2.0)
		Juice.hitstop(0.05)
		player.flash()
		hud.flash(Color(0.75, 0.95, 1.0), 0.3)
		hud.show_toast(popup_boots, 2.0)
		return
	_fail("shock")


## Skills that change something straight away (the others are read when needed).
## Runs at the start, and every time SkillManager says something changed.
func _apply_skills() -> void:
	player.speed_mult = 1.0 + SkillManager.bonus("walk_speed")
	if _o2_on:
		_o2_max = o2_seconds + Game.o2_bonus()


## quiet = no sounds or camera shake (used when a playtest skips rooms).
func _open_exit_doors(r: Room, quiet := false) -> void:
	var opened := false
	for d in _exit_doors(r):
		if _open_doors.has(d):
			continue
		_open_doors[d] = true
		opened = true
		var t: PuzzleTile = _tiles.get(d)
		if t:
			t.open_door()
	if opened and not quiet:
		_play("door")
	# every barrier group touching this stage sinks (the whole group, even the
	# crates that aren't right next to the stage)
	var barriers: Array[Vector2i] = []
	for g in _barrier_groups_of(r):
		for c in g["tiles"]:
			if not _open_doors.has(c):
				_open_doors[c] = true
				barriers.append(c)
	if not barriers.is_empty():
		_move_barriers(r, barriers, quiet)


## The power reaches the barriers: they sink into the floor one after another,
## starting with the one nearest the goal (so it looks like the power travels).
func _move_barriers(r: Room, barriers: Array[Vector2i], quiet := false) -> void:
	var from := center_of(r.target()) if r.target().x >= 0 else center_of(barriers[0])
	var nearer := func(a: Vector2i, b: Vector2i) -> bool: return from.distance_to(center_of(a)) < from.distance_to(center_of(b))
	barriers.sort_custom(nearer)
	for i in barriers.size():
		var t: PuzzleTile = _tiles.get(barriers[i])
		if t:
			t.open_door(i * 0.06)
	if quiet:
		return
	_play("clank")
	_shake_cam(0.3 + barriers.size() * 0.06, 1.5)


## The last room got power: fanfare, then the lights-on cutscene.
## _solve() waits ("await") until this is finished before letting you move.
func _all_powered() -> void:
	_play("fanfare")
	hud.flash(Color(1.0, 0.95, 0.7), 0.5)
	_shake_cam(0.4, 2.5)
	Juice.hitstop(0.1)
	hud.show_toast(popup_all_online, 2.5)
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree(): return
	await _power_tour()
	if not is_inside_tree(): return
	all_rooms_powered.emit()        # PIP says what to do next (StoryBeat: ALL_POWERED)


# ===================================================================== lights-on cutscene
# A cutscene is just a coroutine: a list of steps with `await` in between
# (glide there... light it up... wait a moment... next room). While it runs,
# _busy keeps the player frozen and _cutscene tells the camera to stop
# following him and look at _cut_cam instead.

## The camera glides back through every room, from the one you're in to the
## very first one, and each room lights up at full power as it arrives.
## Then a quick fade takes you back to the player.
func _power_tour() -> void:
	var order: Array[Room] = []
	for r in _rooms:
		if not r.is_exit:
			order.append(r)
	# highest room number first (= backwards to the start), and the room you're in first of all
	order.sort_custom(func(a: Room, b: Room) -> bool: return a.index > b.index)
	if order.has(_current_room):
		order.erase(_current_room)
		order.push_front(_current_room)
	_cutscene = true
	_cut_cam = _cam_pos
	hud.set_cinematic(true)          # black bars top and bottom, objective box hidden
	ship_lighting_up.emit()          # PIP talks over it (StoryBeat: SHIP_LIGHTS_UP)
	for i in order.size():
		var r := order[i]
		await _glide_to(r)
		if not is_inside_tree(): return
		_light_up(r, i)
		await get_tree().create_timer(1.1 if r.cells.size() > 12 else 0.7).timeout
		if not is_inside_tree(): return
	# let PIP finish what he's saying (but never wait forever)
	var wait := 4.0
	while hud.is_talking() and wait > 0.0:
		await get_tree().process_frame
		if not is_inside_tree(): return
		wait -= get_process_delta_time()
	await hud.fade_out(0.3)
	if not is_inside_tree(): return
	_cutscene = false
	_ship_powered = true             # the inside of the ship stays brighter from now on
	if _sfx.has("powerup"):
		_sfx["powerup"].pitch_scale = 1.0
	_update_camera(0.0, true)        # back to the player
	_update_environment(true)
	hud.set_cinematic(false)
	await hud.fade_in(0.4)


## Where the camera looks to show room `r`: the middle of the room.
func _room_view(r: Room) -> Vector2:
	var b := Rect2(Vector2(r.bounds.position * TILE), Vector2(r.bounds.size * TILE))
	return b.get_center()


## Moves the cutscene camera to room `r`: slow, fast, slow, like a film camera.
## On the way, the darkness goes back to how that room looked before.
func _glide_to(r: Room) -> void:
	var target := _room_view(r)
	var dist := _cut_cam.distance_to(target)
	if dist < 4.0:
		return
	var secs := clampf(dist / 600.0, 0.4, 1.2)
	_tween_env(_env_color(r, false), secs)
	var tw := create_tween()
	tw.tween_property(self, "_cut_cam", target, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


## One room goes to full power: brighter tint, lights flare, sparks, the floor
## cable flows again. `step` = how many rooms came before (each sounds higher).
func _light_up(r: Room, step: int) -> void:
	r.full_power = true
	var p: AudioStreamPlayer = _sfx.get("powerup")
	if p and p.stream:
		p.pitch_scale = 1.0 + step * 0.1
		p.play()
	if r.conduit:
		r.conduit.power_flow(0.6)
	if r.target().x >= 0:
		_tile_hit(r.target())
	if r.outside:
		# The hull is sunlit already, so a quick bright surge shows the power arriving.
		if _env_tween:
			_env_tween.kill()
		_env_tween = create_tween()
		_env_tween.tween_property(_dark, "color", space_light.lerp(Color.WHITE, 0.4), 0.12)
		_env_tween.tween_property(_dark, "color", space_light, 0.7)
		_beacon_flare[r] = _light_t + 1.0        # its beacons flash all together...
		_hull_running_lights(r)                  # ...and lights race along the plate edges
		return
	_tween_env(_env_color(r, true), 0.5)
	for pair in _emergency:
		if pair[1] == r:
			create_tween().tween_property(pair[0], "energy", 0.0, 0.3)
	var lights: Array = _room_lights.get(r, [])
	for k in lights.size():
		var l: PointLight2D = lights[k]
		l.visible = true
		var tw := create_tween()
		tw.tween_interval(k * 0.08)                              # one after another
		tw.tween_property(l, "energy", room_light_energy * 2.2, 0.08)
		tw.tween_property(l, "energy", room_light_energy, 0.45)
		_sparks_at(l.position)


## A shower of warm sparks (a ceiling light bursting on).
func _sparks_at(pos: Vector2) -> void:
	var s := Wire.make_sparks(Color(1.0, 0.95, 0.7), 10, 0.5)
	s.one_shot = true
	s.explosiveness = 1.0
	s.position = pos
	s.z_index = 10
	_wire_root.add_child(s)
	s.emitting = true
	get_tree().create_timer(1.0).timeout.connect(s.queue_free)


## A puff of grey dust at your feet (landing a drift on the hull).
func _dust_at(pos: Vector2) -> void:
	var d := Wire.make_sparks(Color(0.78, 0.82, 0.9, 0.8), 10, 0.35)
	d.one_shot = true
	d.explosiveness = 1.0
	d.gravity = Vector2.ZERO
	d.spread = 70.0
	d.initial_velocity_min = 15.0
	d.initial_velocity_max = 40.0
	d.position = pos
	d.z_index = 1
	_wire_root.add_child(d)
	d.emitting = true
	get_tree().create_timer(1.0).timeout.connect(d.queue_free)


## Little lights along every edge of a hull section, switching on in a wave that
## starts at its relay (GOAL). They stay on: the outside of the ship is lit too.
func _hull_running_lights(r: Room) -> void:
	var from := center_of(r.goal) if r.goal.x >= 0 else _room_view(r)
	for c in r.cells:
		if kind_at(c) == "space":
			continue
		for d in DIRS4:
			if not _is_void(c + d):
				continue
			var pos := center_of(c) + Vector2(d) * 13.0     # just inside the plate's edge
			var dot := Node2D.new()
			dot.position = pos
			dot.z_index = 4
			dot.modulate.a = 0.0
			dot.draw.connect(func() -> void:
				dot.draw_rect(Rect2(-1, -1, 3, 3), Color(1.0, 0.75, 0.3))
				dot.draw_rect(Rect2(0, 0, 1, 1), Color(1.0, 1.0, 0.85)))
			LightFX.glow(dot)
			_tile_root.add_child(dot)
			var tw := dot.create_tween()
			tw.tween_interval(from.distance_to(pos) / 900.0)   # further away = later: a wave
			tw.tween_property(dot, "modulate:a", 1.0, 0.1)


func _fail(kind: String) -> void:
	if _busy:
		return
	_busy = true
	_set_hum(false)
	_set_paused_node(Vector2i(-1, -1))
	if _reel_tween:
		_reel_tween.kill()          # stop a reel-back that was still pulling you
		_reel_tween = null
	hud.set_timer(false, 0.0, 0.0)
	hud.set_reel_prompt(false)
	var r := _wire_room if _wire_room != null else _current_room
	# Pressing R while not carrying the wire is just a reset, not a failed try.
	var counts := kind != "restart" or _wire != null
	var had_wire := _wire != null
	if counts and r != null and not r.solved:
		r.fails += 1
		_retries += 1
	var lost_cells := not _cells_pending.is_empty()
	_return_cells()
	_hide_loop(r)
	player.lock(_wire != null)
	match kind:
		"shock":
			_play("shock")
			player.play_shock()
			player.flash()
			_sparks_at(player.position + Vector2(0, -8))
			Juice.hitstop(0.12)           # the heaviest hit in the game: freeze for a moment
			hud.flash(Color(0.75, 0.95, 1.0), 0.85)
			_shake_cam(0.5, 4.0)
			hud.show_toast(popup_zap)
			await get_tree().create_timer(0.85).timeout
			if not is_inside_tree(): return
			player.play_burnt()
			await get_tree().create_timer(0.45).timeout
			if not is_inside_tree(): return
		"timeout":
			_play("snap")
			_sparks_at(player.hand_position())     # the wire burns out in your hands
			hud.flash(Color(1.0, 0.45, 0.15), 0.45)
			_shake_cam(0.25, 2.0)
			hud.show_toast(popup_overload)
		"oxygen":
			_play("alarm")
			hud.flash(Color(0.4, 0.7, 1.0), 0.5)
			_shake_cam(0.3, 2.0)
			hud.show_toast(popup_out_of_air)
			await get_tree().create_timer(0.8).timeout
			if not is_inside_tree(): return
		"cut":
			# PIP's shutdown pulse (rogue_pip.gd) reached the wire
			_play("pulse")
			_play("snap")
			_sparks_at(player.hand_position())
			Juice.hitstop(0.06)
			hud.flash(Color(1.0, 0.25, 0.2), 0.6)
			_shake_cam(0.45, 3.5)
			hud.show_toast(popup_pip_cut)
	if _wire != null:
		var w := _wire
		_wire = null
		await w.snap()
		if not is_inside_tree(): return
		w.queue_free()
	if kind == "restart":
		# R = "take me back": a quick fade and you're on the START pad again.
		await hud.fade_out(0.2)
		if not is_inside_tree(): return
		_respawn()
		if _o2_on:
			_refill_o2()
		await hud.fade_in(0.25)
		if not is_inside_tree(): return
	else:
		# Zapped / timer / oxygen: you stay where you fell. Walk back to the
		# START yourself (or press R to jump there).
		await _stay_after_fail()
		if not is_inside_tree(): return
		if _o2_on:
			_refill_o2()            # the suit switches to its reserve tank
		if _check_stranded(r):
			hud.show_toast(popup_stranded, 3.5)
			if Game.first_time("stranded"):
				_pip_say(pip_stranded)
		elif had_wire and Game.first_time("fail_walk_back"):
			hud.show_toast(popup_wire_gone, 3.0)
	_busy = false
	# The first time a charged cell drains, PIP explains why.
	if lost_cells and Game.first_time("cell_lost"):
		_pip_say(pip_cell_lost)
	# Failed twice here? PIP offers a hint (once per room).
	if counts and r != null and not r.solved and r.fails >= 2 and not _hint_offered.has(r):
		if Game.judge_mode:
			_hint_offered[r] = true
			_pip_say(pip_hint_judge)        # judge mode: P and PIP walks it
		elif _room_has_hint(r):
			_hint_offered[r] = true
			_pip_say(pip_hint)


## Cells charged on a failed try come back, uncharged.
func _return_cells() -> void:
	if _cells_pending.is_empty():
		return
	for c in _cells_pending:
		_cells[c].restore()
	_cells_pending.clear()
	hud.set_cells(_cells_banked, _cells.size())


## After a fail: the wire is gone, but you stay where you are. If that spot is
## somewhere you can't stand (a red tile, open space), a little push moves you
## back to safe floor. No teleport, no fade.
func _stay_after_fail() -> void:
	var r := _wire_room if _wire_room != null else _current_room
	_wire_room = null
	_anchor_cells.clear()
	var safe := _spot_after_fail(player.position)
	if safe.distance_to(player.position) > 0.5:
		var tw := create_tween()
		tw.tween_property(player, "position", safe, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await tw.finished
		if not is_inside_tree(): return
	var here: Room = _room_of.get(cell_of(player.position))
	if here != null:
		_current_room = here
	_release_player()
	if r != null and not r.solved:
		room_restarted.emit(r.index)   # the tutorial points you back to the START


## Where to put you after a fail. Where you are, if that's safe. Otherwise back
## to the last spot you stood on safely: that's the side you came FROM. (Just
## taking the nearest safe tile could push you through a wall of red tiles into
## a corner you can't get out of without crossing them again.) Only if that
## spot is far away or no longer safe do we search for the nearest one.
func _spot_after_fail(pos: Vector2) -> Vector2:
	if _safe_to_stand(pos):
		return pos
	if _last_safe.is_finite() and _last_safe.distance_to(pos) < 96.0 and _safe_to_stand(_last_safe):
		return _last_safe
	return _nearest_safe_spot(pos)


## The closest place you can safely stand: not a red tile, not open space,
## not inside a wall. Searches outwards tile by tile (breadth-first).
func _nearest_safe_spot(pos: Vector2) -> Vector2:
	if _safe_to_stand(pos):
		return pos
	var start := cell_of(pos)
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size() and head < 500:
		var c := queue[head]
		head += 1
		if c != start and _safe_to_stand(center_of(c)):
			return center_of(c)
		for d in DIRS4:
			var n := c + d
			if seen.has(n) or is_solid_for_walk(n, false):   # we may search across space
				continue
			seen[n] = true
			queue.append(n)
	return center_of(_spawn)


## After a fail: can you still walk back to room r's START without stepping on a
## red tile or a blinking grate? If not (say you got zapped on a node with grates
## all round it), you're stranded: an [R] key floats over you until you press it.
## Returns true if you're stranded.
func _check_stranded(r: Room) -> bool:
	_stranded = r != null and not r.solved and r.start.x >= 0 \
		and not _can_walk_to(cell_of(player.position), r.start)
	hud.set_restart_prompt(_stranded)
	return _stranded


## Breadth-first search over the floor, tile by tile, avoiding anything that
## zaps you. True if it gets from `from` to `to`.
func _can_walk_to(from: Vector2i, to: Vector2i) -> bool:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size() and head < 4000:
		var c := queue[head]
		head += 1
		if c == to:
			return true
		for d in DIRS4:
			var n := c + d
			if seen.has(n) or is_solid_for_walk(n):
				continue
			if _is_red(n) or kind_at(n) == "blinker":
				continue
			seen[n] = true
			queue.append(n)
	return false


func _clear_stranded() -> void:
	if _stranded:
		_stranded = false
		hud.set_restart_prompt(false)


func _safe_to_stand(pos: Vector2) -> bool:
	var k := kind_at(cell_of(pos))
	return not _is_red(cell_of(pos)) and k != "blinker" and not box_blocked(pos, Astronaut.FEET_HALF)


## The pads the wire from room r can use: its own, plus the nodes of
## stages you already powered in the same area. Once the cargo between them has
## sunk, those pads are right there, so a later stage can wrap the wire round
## them from a new angle.
func _stage_pads(r: Room) -> Array[Vector2i]:
	var out: Array[Vector2i] = r.pads.duplicate()
	for o in _rooms:
		if o == r or not o.solved or o.area_id != r.area_id:
			continue
		for p in o.pads:
			if kind_at(p) == "node":
				out.append(p)
	return out


# ===================================================================== blinking grates

## Is the grate at c lit right now? Each grate is lit for grate_live seconds out
## of every grate_cycle. Grates further along x are a little behind (grate_wave),
## so the light runs across the floor like a wave you can follow through the gap.
func blinker_live(c: Vector2i) -> bool:
	return _blinker_phase(c) < grate_live


## Will the grate at c be lit `dt` seconds from now? The wave is just a clock,
## so it can be worked out ahead. PIP's autopilot uses this to wait for the gap.
func blinker_live_in(c: Vector2i, dt: float) -> bool:
	return _blinker_phase(c, dt) < grate_live


func is_blinker(c: Vector2i) -> bool:
	return kind_at(c) == "blinker"


func _blinker_phase(c: Vector2i, dt := 0.0) -> float:
	return fposmod(_light_t + dt + c.x * grate_wave, grate_cycle)


## Would standing on tile c zap you right now? (red grates always, blinking ones when lit)
func _is_live_tile(c: Vector2i) -> bool:
	var k := kind_at(c)
	return _is_red(c) or (k == "blinker" and blinker_live(c))


## A red tile that's live (not switched off by a power link).
func _is_red(c: Vector2i) -> bool:
	return kind_at(c) == "discharge" and not _red_off.has(c) and not _grounded.has(c)


## Every frame: switch each blinking grate's picture on or off. Just before it
## lights up it flickers, so you can see it coming.
func _update_blinkers() -> void:
	for c in _blinkers:
		var t: PuzzleTile = _tiles.get(c)
		if t:
			t.set_live(blinker_live(c), _blinker_phase(c) > grate_cycle - 0.35)


func _respawn() -> void:
	var r := _wire_room if _wire_room != null else _current_room
	_wire_room = null
	_anchor_cells.clear()
	_clear_stranded()
	# R also puts this room's movable crates back (not once the room has power)
	if r != null and (not r.solved or is_hall(r)):
		reset_crates(r)
		if is_hall(r) and _room_has_crates(r):
			# A hall with crates has no START: R puts its crates back and you back
			# at the door you came in by (so the crates can't shut you in anywhere).
			player.position = _nearest_safe_spot(_entered_at.get(r, _dev_spot(r)))
			_last_safe = player.position
			_release_player()
			_update_camera(0.0, true)
			return
	var target := _spawn
	if r != null and r.start.x >= 0:
		target = r.start
	elif r != null and r.airlock.x >= 0:
		target = r.airlock
	_release_player()
	player.position = center_of(target)
	_last_safe = player.position
	_current_room = _room_of.get(target, r)
	if r != null and not r.solved:
		room_restarted.emit(r.index)   # the tutorial rewinds to this room's first step
	_update_camera(0.0, true)


## The airlock sequence: inner door shuts, the air hisses out, the outer door opens.
func _cycle_airlock(r: Room) -> void:
	r.cycled = true
	_busy = true
	player.lock(false)
	airlock_cycling.emit(r.index)            # PIP talks you through it (StoryBeat: AIRLOCK)
	# 1. seal the door you came in through
	var outer := _exit_doors(r)
	var closed := false
	for d in r.doors:
		if _open_doors.has(d) and not outer.has(d):
			_open_doors.erase(d)
			closed = true
			var t: PuzzleTile = _tiles.get(d)
			if t:
				t.close_door()
	if closed:
		_play("door")
	await get_tree().create_timer(0.9).timeout
	if not is_inside_tree(): return
	# 2. let the air out: hiss, a flashing red light, dust blowing towards the outer door
	_play("hiss")
	var warn := LightFX.make(Color(1.0, 0.35, 0.2), 110.0, 0.0)
	warn.position = center_of(r.airlock) + Vector2(0, -24)
	add_child(warn)
	var flashing := create_tween().set_loops(6)
	flashing.tween_property(warn, "energy", 1.0, 0.2)
	flashing.tween_property(warn, "energy", 0.15, 0.2)
	var dust := _air_particles(r, outer)
	for n in [3, 2, 1]:
		hud.show_toast("DEPRESSURIZING... %d" % n, 0.9)
		_play("alarm")
		await get_tree().create_timer(0.8).timeout
		if not is_inside_tree(): return
	# 3. the outer door opens onto space, and the oxygen meter starts
	_open_exit_doors(r)
	dust.emitting = false
	get_tree().create_timer(2.0).timeout.connect(dust.queue_free)
	flashing.kill()
	create_tween().tween_property(warn, "energy", 0.0, 0.5)
	_o2_on = true
	_o2_max = o2_seconds + Game.o2_bonus()
	_refill_o2()
	hud.show_toast(popup_outer_door, 2.0)
	_busy = false
	_release_player()


## Specks of air rushing out towards the outer door.
func _air_particles(r: Room, outer: Array[Vector2i]) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	var from := center_of(r.airlock)
	var to := center_of(outer[0]) if not outer.is_empty() else from + Vector2.RIGHT
	p.texture = Wire.spark_texture()
	p.amount = 40
	p.lifetime = 0.7
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(36, 28)
	p.position = from
	p.direction = (to - from).normalized()
	p.spread = 12.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 150.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = Color(0.85, 0.92, 1.0, 0.7)
	p.z_index = 5
	LightFX.glow(p)
	_wire_root.add_child(p)
	p.emitting = true
	return p


# ===================================================================== results

func _finish_level() -> void:
	_complete = true
	_input_cooldown = 1.5           # let the results screen appear before keys work
	if not Game.has_level(level_number + 1):
		set_music_override("ending")   # the very last results screen: the ending theme
		_input_cooldown = 999.0        # no keys while the ship flies away...
		await _fly_away()
		if not is_inside_tree(): return
		_input_cooldown = 1.5          # ...then the results screen as usual
	player.lock(false)
	hud.set_timer(false, 0.0, 0.0)
	_o2_on = false
	hud.set_o2(false, 0.0)
	var retry_goal := maxi(_rooms_with_goal, 1)
	var stars := 1                                  # you finished!
	if _cells_banked >= _cells.size():
		stars += 1                                  # every power cell
	if _retries <= retry_goal:
		stars += 1                                  # few retries
	# Skill points, but only the first time you finish this level (no farming
	# them with "play again"). Ask BEFORE record_level, which marks it finished.
	var points := 0 if Game.has_finished(level_number) else skill_points
	SkillManager.add_points(points)
	if points > 0:
		_play("fanfare")
	var stats := {"time": _play_time, "cells": _cells_banked, "cells_total": _cells.size(),
		"retries": _retries, "retry_goal": retry_goal, "stars": stars, "hints": _hints_used,
		"points": points}
	Game.record_level(level_number, stats)          # (this also saves the game)
	hud.show_summary(level_number, complete_message, stats, Game.has_level(level_number + 1))
	_play("complete")
	# New skill points: a popup, the dot on SKILLS pings, and the first time,
	# PIP explains them (not after the last level: there's nothing left to use them on)
	if points > 0:
		hud.notify_skill_points(points)
		if Game.has_level(level_number + 1) and Game.first_time("skill_points"):
			hud.say(PackedStringArray(Array(pip_skill_points).map(
				func(l: String) -> String: return l.format(Game.story_values()))), "PIP")
	level_completed.emit()


## The results screen's buttons (NEXT LEVEL, PLAY AGAIN) are in the HUD, which
## sends results_next / results_again (connected in _ready). R still plays again.
func _results_input() -> void:
	if _input_cooldown > 0.0 or _leaving:
		return
	if Input.is_action_just_pressed("restart"):
		_leave(level_number)


func _leave(number: int) -> void:
	if _leaving:
		return                            # (a second click while it fades)
	_leaving = true
	await hud.fade_out(0.5)
	if not is_inside_tree():
		return                      # (you quit to the title meanwhile)
	Game.go_to_level(number)


# ===================================================================== the ending: the ship flies away
# Another cutscene made of awaits. The trick: the camera is a child of the
# level, so moving the level would move the camera with it. Setting the
# camera's top_level makes it ignore its parent, so it stays put in space while
# we move and shrink the whole level (the ship) away from it.

## The last level's ending. Called from _finish_level() before the results.
func _fly_away() -> void:
	if camera == null:
		return
	_flying = true
	player.lock(false)
	hud.set_cinematic(true)                       # film bar, no arrows or timers
	_ensure_starfield()
	_tween_env(Color(0.95, 0.96, 1.0), 1.8)       # seen from outside, the ship is lit up
	if ending_lines.size() > 0:
		hud.say(PackedStringArray([ending_lines[0]]))
	# 1. pull the camera back until the whole deck fits above the console
	var ship := Rect2(Vector2(_rect.position * TILE), Vector2(_rect.size * TILE))
	var view := get_viewport_rect().size - Vector2(0, GameHUD.CONSOLE_H)
	var z := minf(view.x / ship.size.x, view.y / ship.size.y) * 0.8
	camera.top_level = true                       # from now on the camera stays put in space
	var cam_to := ship.get_center() + Vector2(0, GameHUD.CONSOLE_H * 0.5 / z)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(camera, "zoom", Vector2(z, z), 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(camera, "global_position", cam_to, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if not is_inside_tree(): return
	# 2. the engines light up at the back of the ship
	var back := -ending_direction.normalized()
	for spot in _engine_spots(ship, back):
		var flame := _engine_flame(back)
		flame.position = spot
		add_child(flame)
	_play("powerup")
	_play("puff")
	_shake_cam(0.8, 2.0)
	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree(): return
	# 3. off it goes: slowly at first, then faster and faster
	var far := ending_direction.normalized() * ship.size.length() * 2.5
	var away := create_tween().set_parallel(true)
	away.tween_property(self, "position", position + far, 2.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	away.tween_property(self, "scale", Vector2(0.55, 0.55), 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if ending_lines.size() > 1:
		hud.say(PackedStringArray([ending_lines[1]]))
	await get_tree().create_timer(2.0).timeout
	if not is_inside_tree(): return
	hud.flash(Color(1, 1, 1), 0.9)                # the jump
	_play("fanfare")
	await away.finished
	if not is_inside_tree(): return
	await get_tree().create_timer(0.8).timeout     # a moment of empty space
	if not is_inside_tree(): return
	hud.set_cinematic(false)


## Levels without open space have no starfield yet: the ending needs one.
func _ensure_starfield() -> void:
	if get_node_or_null("Sky") != null:
		return
	var sky_layer := CanvasLayer.new()
	sky_layer.name = "Sky"
	sky_layer.layer = -10        # behind the level, and untouched by its darkness
	add_child(sky_layer)
	var sky := Starfield.new()
	sky.focus = Vector2(_rect.get_center() * TILE)
	sky_layer.add_child(sky)


## Three spots along the back edge of the ship for the engines: on the rows (or
## columns) a quarter, a half and three quarters of the way along, at the
## furthest painted tile on that side.
func _engine_spots(ship: Rect2, back: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var horizontal := absf(back.x) >= absf(back.y)
	var s := signf(back.x) if horizontal else signf(back.y)     # -1 = the left (or top) side
	for k in [0.25, 0.5, 0.75]:
		var line := floori((ship.position.y + ship.size.y * k) / TILE) if horizontal \
			else floori((ship.position.x + ship.size.x * k) / TILE)
		var found := false
		var best := Vector2i.ZERO
		for c in _kinds:
			var on_line: bool = c.y == line if horizontal else c.x == line
			if not on_line:
				continue
			var along: float = c.x if horizontal else c.y
			var best_along: float = best.x if horizontal else best.y
			if not found or along * s > best_along * s:
				best = c
				found = true
		if found:
			var edge := Vector2(0.5 + 0.5 * s, 0.5) if horizontal else Vector2(0.5, 0.5 + 0.5 * s)
			out.append(Vector2(best * TILE) + edge * TILE)
	return out


## One engine: a long stream of hot sparks pointing out of the back of the ship.
func _engine_flame(back: Vector2) -> CPUParticles2D:
	var p := Wire.make_sparks(Color(1.0, 0.7, 0.3), 90, 0.9)
	p.direction = back
	p.spread = 7.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 260.0
	p.initial_velocity_max = 420.0
	p.scale_amount_min = 4.0
	p.scale_amount_max = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(4, 10) if absf(back.x) >= absf(back.y) else Vector2(10, 4)
	var ramp := Gradient.new()                     # white hot, then orange, then gone
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 1.0, 0.9, 1.0), Color(1.0, 0.6, 0.2, 0.9), Color(0.9, 0.2, 0.1, 0.0)])
	p.color = Color.WHITE                          # the ramp gives the colours
	p.color_ramp = ramp
	p.z_index = 10
	p.emitting = true
	return p


# ===================================================================== camera

## Shake the camera for `duration` seconds, at most `strength` pixels.
## The shaking itself is done by Juice.shake (juice.gd): it takes a strength
## from 0 to 1 and moves the view by that squared, so this works it backwards.
func _shake_cam(duration: float, strength: float) -> void:
	Juice.shake(sqrt(strength / Juice.MAX_SHAKE), duration)


## Follows the player but never shows outside the current area (all the stages
## joined to this one). If the area is smaller than the screen, the camera just
## sits in its middle. During the lights-on cutscene it looks at _cut_cam instead.
## The HUD's console covers the bottom CONSOLE_H pixels, so the "screen" we frame
## the room in is that much shorter, and the camera sits CONSOLE_H/2 lower than
## the point we want in the middle of it.
func _update_camera(delta: float, snap: bool) -> void:
	if camera == null or _current_room == null or _flying:
		return
	var below := Vector2(0, GameHUD.CONSOLE_H * 0.5)
	if _cutscene:
		_cam_pos = _cut_cam
		camera.position = (_cam_pos + below).round()
		return
	var view := get_viewport_rect().size - Vector2(0, GameHUD.CONSOLE_H)
	var b := _current_room.area_bounds
	var r := Rect2(Vector2(b.position * TILE), Vector2(b.size * TILE))
	var target := player.position + Vector2(0, -12)
	var half := view * 0.5
	if r.size.x <= view.x:
		target.x = r.get_center().x
	else:
		target.x = clampf(target.x, r.position.x + half.x, r.end.x - half.x)
	if r.size.y <= view.y:
		target.y = r.get_center().y
	else:
		target.y = clampf(target.y, r.position.y + half.y, r.end.y - half.y)
	if snap:
		_cam_pos = target
	else:
		# Move part of the way each frame = a smooth "easing" camera.
		_cam_pos = _cam_pos.lerp(target, 1.0 - exp(-delta * 7.0))
	camera.position = (_cam_pos + below).round()     # (Juice adds the shake on top, as camera.offset)
