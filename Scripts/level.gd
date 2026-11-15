# ---------------------------------------------------------------------------
# level.gd  -  reads the map you PAINT, makes it look nice, and runs the RULES.
#
# BIG PICTURE
#   1. You paint the level on the "Layout" TileMapLayer with simple tiles
#      (floor, wall, start, goal, node, bend, red, crate, door, spawn, exit,
#      cell, hull, space, airlock, barrier).
#      Each tile in the palette carries a hidden label called "kind"
#      (set in Assets/images/tiles/layout_tileset.tres -> Custom Data).
#   2. _read_layout() turns the painted tiles into a Dictionary:
#      tile position -> kind, e.g. Vector2i(3, 4) -> "node".
#   3. _build_visuals() uses that to draw the pretty version on 3 extra layers
#      (Ground, Walls, Props): tall wall panels, roof edges, floor variety, hull plates.
#      In the editor this re-runs every time you paint, so you see the result live.
#   4. _build_rooms() finds the rooms (floor areas separated by walls, doors
#      and barriers). Each room is one puzzle STAGE. Doors lead to the next
#      room. BARRIERS (cargo on a lift) split one room into several stages:
#      touching barrier tiles are a GROUP that sinks into the floor as soon as a
#      stage next to it is powered. Stages joined by barriers form one AREA:
#      the camera roams across it, and a later stage can wrap its wire round the
#      NODES and BENDS of the stages you already powered there. So powering
#      something really changes the room for the next puzzle.
#   5. During play the player calls player_moved() every frame and that function
#      checks the rules: red tiles, power cells, new room, touching pads...
#   6. Lighting: the ship starts dark (CanvasModulate). Glowing things (wires,
#      pad halos, floor guides) use light channel 2, lit by one flat "glow
#      light" - see light_fx.gd. Each room has a red emergency light, and
#      ceiling lights that switch on when you power it.
#      When EVERY room has power, a short CUTSCENE (_power_tour) takes the
#      camera back through all the rooms, lighting each one up at full power.
#   7. The level ANNOUNCES what happens with signals (wire_grabbed, pad_touched,
#      room_solved, ...). The tutorial, the story (PIP's lines) and the floor
#      guides listen to those - the level doesn't need to know they exist.
#
# THE WIRE RULES
#   - Press E on the START pad to grab the wire. The timer starts right away.
#   - You walk freely, but the wire is a tight straight line from the last pad
#     you touched to your hands. It can't pass through walls, crates or red
#     tiles - if a step would make it, you just can't take that step.
#   - NODE: wraps the wire, refills the timer and pauses it until you step off.
#   - BEND: stops you and shows two arrows; press one and it flings you 90 deg.
#   - GOAL: powers the stage and opens its doors / moves its barriers.
#   - Timer hits 0, or you step on a red tile (with or without the wire)
#     -> the wire snaps and the stage resets, but you STAY where you are
#     (pushed off the red tile). Walk back to the START, or press R to jump
#     there. The wire itself can't be stretched over red tiles.
#   - BLINKING GRATES switch on and off in a wave (grate_cycle, grate_live,
#     grate_wave). Lit = they zap your feet. The wire is fine over them.
#
# POWER CELLS (the reward for a clever route)
#   - "cell" tiles become PowerCells. Touch one WHILE CARRYING THE WIRE to charge
#     it. You keep it once the room is powered; if you fail, it comes back.
#   - At the exit you get up to 3 stars: finish, every cell, few retries.
#     Game (game_state.gd, an autoload) remembers the results, and every cell
#     gives you extra oxygen on later spacewalks.
#
# SPACEWALK (Level 2)
#   - "hull" = floor outside the ship, "space" = open space (stars show through).
#     A room with hull or space in it is an OUTSIDE room: sunlit, no ceiling
#     lights, its own music, and an OXYGEN meter that drains while you're there.
#   - Your feet can't go onto space. Walk into a hull edge and, if there's a
#     plate straight ahead to land on, you DRIFT across (player.gd, State.DRIFT).
#     The wire CAN stretch across open space.
#   - A door with no wall beside it is a GANGWAY: a catwalk over space that slides
#     out when the room before it is powered.
#   - "airlock" pad: stand on it and the airlock cycles: the door behind you
#     shuts, the air hisses out, the outer door opens and the oxygen meter starts.
#
# THE CORE (Level 3)
#   - A "core" tile is a round machine socket. A room with a core has no goal
#     pad: you power it by wrapping the wire ALL the way round the core.
#   - How we know: add up the angle each straight piece of wire sweeps round
#     the core, as seen from the core (_winding). A full turn = TAU radians
#     (360 degrees). A ring on the socket shows how far round you are.
#   - In Level 3, PIP's body docks on the cores (rogue_pip.gd). That script
#     isn't part of the rules: it LISTENS to the level's signals, and it can
#     call cut_wire(), set_alert(), hold() and let_go().
#
# THE RPG SIDE (XP, levels, suit upgrades - the numbers are in game_state.gd)
#   - Powering a room gives XP (more if you didn't fail there, and for every
#     battery kept); so does reaching the exit (_award_xp).
#   - Level up = after the room's power-up, the game pauses and you pick one
#     upgrade (_offer_upgrades -> hud.pick_upgrade). Upgrades change the rules
#     through _wire_time(), _cell_bonus(), _shock() and the player's speed_mult.
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
signal pad_touched(kind: String, index: int) # the wire reached a node / bend / goal
signal level_completed
signal cell_collected(index: int)            # a power cell got charged in room `index`
signal empty_cell_touched                    # you touched a cell without the wire (only sent once)
signal hint_shown(index: int)                # the player pressed H in room `index`
signal drift_started(index: int)             # you pushed off into open space
signal airlock_cycling(index: int)           # the airlock in room `index` started its sequence
signal ship_lighting_up                      # every room has power: the lights-on cutscene starts
signal all_rooms_powered                     # ...and the cutscene is over (you can move again)

const TILE := 32
const DIRS4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

# How close (in pixels, from a pad's centre) counts as touching it. A tile is 32 px.
# We measure from his feet AND from a point BODY_UP pixels higher: the sprite is
# taller than a tile, so when he LOOKS like he's on a pad his feet can be just below it.
# tools/solver2.py uses the same numbers - change them there too.
const START_RADIUS := 20.0
const NODE_RADIUS := 22.0
const GOAL_RADIUS := 22.0
const BEND_RADIUS := 20.0
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
const PUZZLE_FRAME := {"start": 0, "goal": 1, "node": 2, "bend": 3, "discharge": 4,
	"blinker": 5, "crate": 6, "door": 7, "airlock": 11, "barrier": 12, "core": 13}
const GANGWAY_FRAME := 9
const SRC_WALL := 0
const SRC_FLOOR := 1
const SRC_ROOF := 2
const SRC_PUZZLE := 3
const SRC_HULL := 4
const SOUNDS := ["grab", "hum", "node", "bend", "shock", "snap", "powerup", "door", "complete", "tick",
	"pickup", "hiss", "puff", "clank", "alarm", "fanfare", "pulse"]
const MUSIC_DB := -17.0

## The TileMapLayer you paint on. If empty, a child called "Layout" is used.
@export var layout: TileMapLayer
## Show the painted icons on top of the finished look while editing (off = preview the real look).
@export var show_layout_in_editor := true:
	set(value):
		show_layout_in_editor = value
		_apply_layout_visibility()

@export_group("Level")
## Which level this is. The order of the levels is in Game.LEVELS (game_state.gd).
@export var level_number := 1
## Shown in the pause menu.
@export var level_name := "ENGINEERING DECK"
## Shown on the results screen.
@export var complete_message := "Power's back on in this part of the ship."

@export_group("Rules")
## Seconds you get from the START pad, and again at every NODE.
@export var wire_time := 5.0
## Should the timer stop while you pick a direction on a BEND?
@export var bend_pauses_timer := true
## Seconds a POWER CELL adds to the wire's timer when you grab it with the wire.
@export var cell_bonus := 2.0

@export_group("Lighting")
## How dark the ship is before a room gets power (1,1,1 = no darkness at all).
@export var darkness := Color(0.2, 0.21, 0.3)
## How bright it is OUTSIDE the ship, where the sun lights the hull.
@export var space_light := Color(0.5, 0.54, 0.7)
## Brightness of a room's lights once it's powered.
@export var room_light_energy := 0.75
## How bright the inside of the ship gets once EVERY room has power
## (after the lights-on cutscene). Should be lighter than `darkness`.
@export var full_power_light := Color(0.42, 0.43, 0.52)
## The red tint inside the ship during an ALERT (Level 3: PIP is trying to shut
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

# Things PIP says because of the RULES, not the story. Each plays once at most.
# (Story lines are StoryBeat nodes under the "Story" node - see story_beat.gd.)
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
@export var pip_strain := "The wire can't go through that. Wrap it round a node to change its angle."
## The first time you grab a wire that can use a node from an earlier stage (PIP points at it).
@export var pip_shared := "That node from the last machine is still live. Wrap this wire round it."
## After a fail, when there's no way back to the START without crossing red tiles or grates.
@export var pip_stranded := "No safe way back from there. Press R and I'll bring you to the start."
## After you pick your very first suit upgrade.
@export var pip_level_up := "Nice. The suit learns as you go. Every level up, you get another upgrade."

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
## {lv} = your new level.
@export var popup_level_up := "LEVEL UP! LV {lv}"
@export var popup_boots := "RUBBER BOOTS SAVED YOU"


# An inner class: a little bundle of data describing one room.
class Room:
	var index := -1
	var cells: Array[Vector2i] = []
	var start := Vector2i(-1, -1)
	var goal := Vector2i(-1, -1)
	var pads: Array[Vector2i] = []      # nodes, bends and the goal
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
var _anchor_cells: Array[Vector2i] = []   # pads the wire is wrapped around, in order
var _last_anchor := Vector2.ZERO          # pixel position the tight wire starts from
var _paused_node := Vector2i(-1, -1)      # node you're standing on (timer paused)
var _choosing_bend := Vector2i(-1, -1)    # bend you're stopped on (picking a direction)
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
var _bend_side := {}                      # bend tile -> its first way out (for reeling back to it)
var _preview_paths: Array = []            # [from, end, what] for each way out of the bend you're on
var _preview_node: Node2D                 # draws those dotted fling previews
var _reel_tween: Tween                    # the reel-back pull, while it's happening
var _still_time := 0.0                    # how long you've stood still holding the wire
var _last_safe := Vector2.INF             # the last spot you stood on safely (for after a zap)
var _stranded := false                    # after a fail: no safe path back to the START
var _stranded_check := 0.0

# --- RPG
var _xp_gained := 0                       # XP earned in this level (for the results screen)
var _boots_used := {}                     # Room -> true: RUBBER BOOTS already saved you there

# --- the core (Level 3)
var _alert := false            # red alert: the ship's tinted red, the boss music plays
var _holds := 0                # how many other nodes asked the level to wait (hold / let_go)

# --- playtesting from the editor (TestStart marker, F6)
## The room a TestStart marker put you in (-1 = normal start). The story,
## tutorial and rogue PIP read this to catch up with the rooms you skipped.
var test_room := -1
## The marker said "skip PIP's level intro".
var test_skip_intro := false

# lights-on cutscene
var _cutscene := false         # true while the cutscene moves the camera
var _cut_cam := Vector2.ZERO   # where the cutscene camera looks (a Tween moves it)
var _ship_powered := false     # every room has power: the inside of the ship is brighter
var _env_tween: Tween          # the tween changing the darkness tint (so two never fight)

# --- state
var _busy := false             # true during win/lose animations: ignore input
var _complete := false
var _leaving := false
var _dialogue_lock := false    # PIP is talking and the player has to read
var _input_cooldown := 0.0     # ignore keys for a moment (so one E press doesn't do two things)
var _cam_pos := Vector2.ZERO
var _shake := 0.0
var _shake_strength := 0.0
var _sfx := {}
var _music := {}               # "ship" / "space" -> AudioStreamPlayer
var _music_tweens := {}
var _music_now := ""
var _tile_root: Node2D
var _conduit_root: Node2D
var _wire_root: Node2D

# --- lighting
var _dark: CanvasModulate     # tints the whole level dark (or sunlit outside)
var _glow_light: PointLight2D  # one flat light that ONLY lights glowing things (channel 2)
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
	hud.can_block = can_pause_for_dialogue
	hud.set_level_info("LEVEL %d: %s" % [level_number, level_name])
	hud.set_cells(0, _cells.size())
	hud.set_power(0, _rooms_with_goal)
	_apply_upgrades()                      # suit upgrades from earlier levels (and LV in the console)
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
	else:
		layout.visible = false     # in the game you only see the pretty layers


func _ensure_input_actions() -> void:
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

## A TestStart marker (test_start.gd) that's switched on - or null.
## Only counts when you run THIS level scene from the editor (F6): exported
## games don't have the "editor" feature, and Game.playing_through is true
## whenever the game itself loaded the level (F5 from the title).
func _active_test_start() -> TestStart:
	if not OS.has_feature("editor") or Game.playing_through:
		return null
	for child in get_children():
		if child is TestStart and child.active:
			return child
	return null


## Start the playtest at the TestStart marker. Every room before it is powered
## QUIETLY (no cutscenes, no PIP lines): lights on, doors open, cargo sunk.
## The story, tutorial and rogue PIP read `test_room` and catch up themselves.
func _apply_test_start() -> void:
	var ts := _active_test_start()
	if ts == null:
		return
	var at := to_local(ts.global_position)
	var r: Room = _room_of.get(cell_of(at))
	if r == null:
		push_warning("TestStart isn't on the floor of a room - starting at the spawn.")
		return
	test_room = r.index
	test_skip_intro = not ts.play_intro
	player.position = _nearest_safe_spot(at)
	_last_safe = player.position
	_current_room = r
	if ts.skip_earlier_rooms:
		for o in _rooms:
			if o.index < r.index and not o.is_exit:
				_power_quietly(o)
	if r.outside and (_o2_on or ts.skip_earlier_rooms):
		_o2_on = true                       # you're outside: the airlock was "used" already
		_o2_max = o2_seconds + Game.o2_bonus()
		_refill_o2()
	player.set_lamp(not r.solved)
	hud.set_power(_rooms_powered, _rooms_with_goal)
	print("TestStart: playtest starts in room %d (%d rooms before it powered)." % [r.index + 1, _rooms_powered])


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
	# A power cell with open space on both sides (left AND right, or above AND
	# below) floats in space: that tile IS open space (you drift past it), it
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


## What is painted at tile `c`? "" means nothing (outside the map).
func kind_at(c: Vector2i) -> String:
	return _kinds.get(c, "")


## Open space (or nothing) - used to spot power cells floating in space.
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


## Doors and barriers aren't part of any room: they're what separates rooms/stages.
func _is_room_cell(kind: String) -> bool:
	return _walkable(kind) and kind != "door" and kind != "barrier"


## Can't WALK through: nothing, walls, crates, cores, closed doors and barriers
## that haven't moved yet - and open space, unless space_blocks is false (used
## for drifting: you float over space).
func is_solid_for_walk(c: Vector2i, space_blocks := true) -> bool:
	var kind := kind_at(c)
	if kind == "" or kind == "wall" or kind == "crate" or kind == "core":
		return true
	if kind == "space":
		return space_blocks
	if kind == "door" or kind == "barrier":
		return not _open_doors.has(c)
	return false


## The WIRE can't pass over: nothing, walls, crates, cores, doors, the exit, live
## red tiles, and barriers until they've sunk away. (It CAN stretch across open space.)
func is_solid_for_wire(c: Vector2i) -> bool:
	var kind := kind_at(c)
	if kind == "barrier":
		return not _open_doors.has(c)
	return kind in ["", "wall", "crate", "core", "door", "exit", "discharge"]


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
## The tile you'd be standing on is ignored if it's a red tile - so you CAN walk
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


## A door with no wall beside it is out in space: a GANGWAY (catwalk).
func _is_gangway(c: Vector2i) -> bool:
	if kind_at(c) != "door":
		return false
	for d in DIRS4:
		if kind_at(c + d) == "wall":
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
	for l in [_ground, _walls, _props]:
		l.tile_set = ts
		l.clear()
	var depth := _face_depths()
	var slices := _face_slices(depth)
	for c in _kinds:
		var kind: String = _kinds[c]
		if kind == "wall":
			if depth.has(c):
				# part of a wall panel: pick the right 32x32 slice of wall_face.png
				_walls.set_cell(c, SRC_WALL, Vector2i(int(slices.get(c, 1)), 3 - int(depth[c])))
			else:
				# top of a wall: the roof tile whose rim matches the floor around it
				var m := _roof_mask(c)
				_walls.set_cell(c, SRC_ROOF, Vector2i(m & 15, m >> 4))
			continue
		if kind == "space":
			continue          # open space: draw nothing, the starfield shows through
		if kind == "door" and _is_gangway(c):
			if Engine.is_editor_hint():
				_props.set_cell(c, SRC_PUZZLE, Vector2i(GANGWAY_FRAME, 0), 1 if _door_rotated(c) else 0)
			continue          # the catwalk is a PuzzleTile at runtime
		if kind == "crate" and _is_floating(c):
			_props.set_cell(c, SRC_PUZZLE, Vector2i(PUZZLE_FRAME["crate"], 0))   # floating debris
			continue
		if _is_outside(c):
			_ground.set_cell(c, SRC_HULL, Vector2i(_hull_variant(c), 0))
		elif int(depth.get(c + Vector2i.UP, 0)) == 1:
			_ground.set_cell(c, SRC_WALL, Vector2i(0, 3))   # light strip under a wall panel
		else:
			_ground.set_cell(c, SRC_FLOOR, Vector2i(_floor_variant(c), 0))
		if PUZZLE_FRAME.has(kind) and (Engine.is_editor_hint() or kind == "crate"):
			var alt := 1 if (kind == "door" and _door_rotated(c)) else 0
			_props.set_cell(c, SRC_PUZZLE, Vector2i(PUZZLE_FRAME[kind], 0), alt)
	_hull_edges.queue_redraw()


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
	var puzzle := _add_atlas(ts, SRC_PUZZLE, PUZZLE_TEX, Vector2i(14, 1))
	for frame in [PUZZLE_FRAME["door"], GANGWAY_FRAME]:
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


## Wall tiles 1-3 above a floor tile become the wall panel (1 = bottom row).
func _face_depths() -> Dictionary:
	var d := {}
	for y in range(_rect.end.y, _rect.position.y - 1, -1):
		for x in range(_rect.position.x, _rect.end.x):
			var c := Vector2i(x, y)
			if kind_at(c) != "wall":
				continue
			var below := kind_at(c + Vector2i.DOWN)
			if _walkable(below) and below != "door":
				d[c] = 1
			elif below == "wall":
				var bd := int(d.get(c + Vector2i.DOWN, 0))
				if bd == 1 or bd == 2:
					d[c] = bd + 1
	return d


## Picks which column of the 6-wide wall panel each wall tile uses
## (left cap, plain middle, centre tab, right cap) so panels of any width look right.
func _face_slices(depth: Dictionary) -> Dictionary:
	var out := {}
	for y in range(_rect.position.y, _rect.end.y):
		var x := _rect.position.x
		while x < _rect.end.x:
			if int(depth.get(Vector2i(x, y), 0)) != 1:
				x += 1
				continue
			var x1 := x
			while int(depth.get(Vector2i(x1 + 1, y), 0)) == 1:
				x1 += 1
			var sl := _panel_slices(x1 - x + 1)
			for i in sl.size():
				var col := Vector2i(x + i, y)
				out[col] = sl[i]
				for k in [1, 2]:
					var up := col + Vector2i(0, -k)
					if int(depth.get(up, 0)) == k + 1:
						out[up] = sl[i]
			x = x1 + 1
	return out


func _panel_slices(length: int) -> Array[int]:
	var parts: Array[int] = []
	if length <= 8:
		parts.append(length)
	else:
		var k := maxi(1, roundi(length / 6.0))
		var base := floori(float(length) / k)
		for i in k:
			parts.append(base + (1 if i < length % k else 0))
	var out: Array[int] = []
	for n in parts:
		if n == 1:
			out.append(1)
			continue
		var s: Array[int] = []
		s.resize(n)
		s.fill(1)
		s[0] = 0
		s[n - 1] = 5
		if n >= 4:
			var m := floori((n - 2) / 2.0)
			s[m] = 2
			s[m + 1] = 3
			for i in range(m + 2, n - 1):
				s[i] = 4
		out.append_array(s)
	return out


## 8 yes/no questions ("is there floor N, E, S, W, NE, SE, SW, NW?") packed
## into one number 0-255 using bits. That number picks one of 256 roof tiles.
func _roof_mask(c: Vector2i) -> int:
	var m := 0
	if _walkable(kind_at(c + Vector2i(0, -1))): m |= 1
	if _walkable(kind_at(c + Vector2i(1, 0))): m |= 2
	if _walkable(kind_at(c + Vector2i(0, 1))): m |= 4
	if _walkable(kind_at(c + Vector2i(-1, 0))): m |= 8
	if _walkable(kind_at(c + Vector2i(1, -1))): m |= 16
	if _walkable(kind_at(c + Vector2i(1, 1))): m |= 32
	if _walkable(kind_at(c + Vector2i(-1, 1))): m |= 64
	if _walkable(kind_at(c + Vector2i(-1, -1))): m |= 128
	return m


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
	return (_walkable(l) and l != "door" and l != "space") or (_walkable(r) and r != "door" and r != "space")


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
				"node", "bend": room.pads.append(cur)
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
	# doors (and barriers) and which rooms they join
	for c in _kinds:
		if _kinds[c] != "door" and _kinds[c] != "barrier":
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


## BARRIER GROUPS. Barrier tiles that touch each other form one group: a whole
## wall of cargo that moves together. A group sinks as soon as ANY stage next to
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


## AREAS. A room is one puzzle STAGE. Stages joined by a BARRIER (or, outside,
## by a catwalk) are really one big space, so they form an AREA: the camera can
## roam across the whole area, the room-name popup only shows when you walk into
## a new area, and a stage can use the NODES and BENDS of stages you already
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


## Friendly warnings in the Output panel when the map is missing something.
func _check_rooms() -> void:
	for r in _rooms:
		if r.is_exit:
			continue
		var n := r.index + 1
		if r.airlock.x < 0:          # airlocks don't need pads
			if r.start.x < 0:
				push_warning("Room %d has no START pad." % n)
			if r.target().x < 0:
				push_warning("Room %d has no GOAL pad (or CORE)." % n)
		if _exit_doors(r).is_empty() and _barrier_groups_of(r).is_empty():
			push_warning("Room %d has no door or barrier leading onward." % n)


## DOORS that lead from room r to a LATER room (the ones r's goal opens).
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
	_preview_node = _new_root("FlingPreview", 20)
	LightFX.glow(_preview_node)
	_preview_node.draw.connect(_draw_fling_preview)
	for c in _kinds:
		var kind: String = _kinds[c]
		if not PUZZLE_FRAME.has(kind) or kind == "crate":
			continue
		var t := PuzzleTile.new()
		t.position = center_of(c)
		_tile_root.add_child(t)
		if kind == "door" and _is_gangway(c):
			t.setup(PuzzleTile.Kind.GANGWAY, _door_rotated(c))
		else:
			t.setup(PUZZLE_FRAME[kind], kind == "door" and _door_rotated(c))
		_tiles[c] = t
		if kind == "blinker":
			_blinkers.append(c)


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
	if _alert:
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
	# Background music: soft loops for inside the ship and for space, and a
	# tense one for red alerts (the PIP boss in Level 3).
	for n in ["ship", "space", "core"]:
		var p := AudioStreamPlayer.new()
		p.name = "Music_" + n
		var path := "res://Assets/audio/music_%s.wav" % n
		if ResourceLoader.exists(path):
			var s = load(path)
			if s is AudioStreamWAV:
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD      # play it round and round
				s.loop_begin = 0
				s.loop_end = int(s.get_length() * s.mix_rate)
			p.stream = s
		p.volume_db = -80.0
		add_child(p)
		_music[n] = p


func _play(n: String) -> void:
	var p: AudioStreamPlayer = _sfx.get(n)
	if p and p.stream:
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


## Cross-fade: the new music fades in while the old one fades out.
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
			tw.tween_property(p, "volume_db", MUSIC_DB, 2.0)
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
	if _input_cooldown <= 0.0:
		if Input.is_action_just_pressed("restart"):
			_fail("restart")
			return
		if Input.is_action_just_pressed("hint"):
			_try_hint()
	# a blinking grate can light up under you while you stand still
	if player.state != Astronaut.State.LOCKED and _is_live_tile(cell_of(player.position)):
		_shock()
		return
	if _tick_o2(delta):
		return
	if _wire != null and player.is_wired():
		# E while walking with the wire = reel back to the last pad it's wrapped round
		var walking := player.state == Astronaut.State.WIRED
		if walking and _input_cooldown <= 0.0 and Input.is_action_just_pressed("interact"):
			_reel_back()
		# stood still a moment away from the last pad? remind them they can reel back
		_still_time = _still_time + delta if walking and not player.is_moving() else 0.0
		hud.set_reel_prompt(_still_time > 0.7 and player.position.distance_to(_last_anchor) > 24.0)
		_tick_timer(delta)
	else:
		hud.set_timer(false, 0.0, 0.0)
		hud.set_reel_prompt(false)
		if player.state == Astronaut.State.FREE and _input_cooldown <= 0.0 and Input.is_action_just_pressed("interact"):
			_try_grab()
		# stranded? keep checking: if you find a safe way back, the [R] goes away
		if _stranded:
			_stranded_check -= delta
			if _stranded_check <= 0.0:
				_stranded_check = 0.5
				_check_stranded(_current_room)
	_update_prompts()


func _timer_paused() -> bool:
	if _paused_node.x >= 0:
		return true
	return _choosing_bend.x >= 0 and bend_pauses_timer


func _tick_timer(delta: float) -> void:
	var paused := _timer_paused()
	if not paused:
		_time_left -= delta
	var frac := clampf(_time_left / _wire_time(), 0.0, 1.0)
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
	if not _o2_on or _current_room == null or not _current_room.outside:
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
	if Engine.is_editor_hint() or player == null:
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
	if _is_live_tile(c):
		_shock()
		return
	_check_cells()
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
	if _paused_node.x >= 0 and player.position.distance_to(center_of(_paused_node)) > NODE_RADIUS + 4.0:
		_set_paused_node(Vector2i(-1, -1))
	# Did we touch a pad we haven't used yet?
	for pad in _wire_pads:
		if _anchor_cells.has(pad):
			continue
		var kind := kind_at(pad)
		var radius := BEND_RADIUS
		if kind == "node":
			radius = NODE_RADIUS
		elif kind == "goal":
			radius = GOAL_RADIUS
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
		_wire.add_anchor(player.hand_position())    # the loop's last piece stays where it is
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


## The same, but for previews IN THE EDITOR (rogue_pip.gd): works the rooms out
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


## RED ALERT on/off: the ship goes red, the emergency lights flash in every
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


## Another node asks the level to WAIT before it carries on after a room is
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


func _pad_radius(kind: String) -> float:
	match kind:
		"node": return NODE_RADIUS
		"goal": return GOAL_RADIUS
	return BEND_RADIUS


# ===================================================================== bends: preview and reel back

## Where would a fling from the bend at `from` in direction `dir` end? Same
## steps as the real fling (player.gd, 2 px at a time): it stops at anything
## solid, on a pad the wire can reach, or on a live red tile.
## Returns {"end": Vector2, "what": "stop" / "shock" / "node" / "bend" / "goal"}.
func predict_fling(from: Vector2, dir: Vector2, bend: Vector2i) -> Dictionary:
	var p := from
	for i in 500:
		var next := p + dir * 2.0
		if box_blocked(next, Astronaut.FEET_HALF):
			return {"end": p, "what": "stop"}
		p = next
		if _is_live_tile(cell_of(p)):
			return {"end": p, "what": "shock"}
		for pad in _wire_pads:
			if pad == bend or _anchor_cells.has(pad):
				continue
			var kind := kind_at(pad)
			if _touching_at(p, center_of(pad), _pad_radius(kind)) and _line_clear(from, center_of(pad)):
				return {"end": center_of(pad), "what": kind}
	return {"end": p, "what": "stop"}


## Stopped on a bend: show where each of its two ways out would throw you.
func _show_fling_preview(c: Vector2i, side: Vector2) -> void:
	var pc := center_of(c)
	_preview_paths.clear()
	for d in [side, -side]:
		var res := predict_fling(pc, d, c)
		_preview_paths.append([pc, res["end"], res["what"]])
	_preview_node.queue_redraw()


func _hide_fling_preview() -> void:
	_preview_paths.clear()
	_preview_node.queue_redraw()


## A dotted line for each way out, and a marker where it ends: a ring in the
## pad's colour if you'd land on a pad, a red X if you'd get zapped, a bar if
## you'd just hit something.
func _draw_fling_preview() -> void:
	for path in _preview_paths:
		var a: Vector2 = path[0]
		var b: Vector2 = path[1]
		var what: String = path[2]
		var col := Color(0.92, 0.75, 1.0, 0.9)
		match what:
			"node": col = Color(1.0, 0.6, 0.25)
			"goal": col = Color(0.45, 0.75, 1.0)
			"bend": col = Color(0.8, 0.55, 1.0)
			"shock": col = Color(1.0, 0.3, 0.25)
		var dist := a.distance_to(b)
		var dir := (b - a).normalized() if dist > 0.0 else Vector2.ZERO
		var y := -10.0                              # drawn at hand height, like the wire
		var t := 20.0
		while t < dist:
			_preview_node.draw_rect(Rect2(a + dir * t + Vector2(-1, y - 1), Vector2(2, 2)), col)
			t += 6.0
		var e := b + Vector2(0, y)
		match what:
			"shock":
				for k in range(-3, 4):
					_preview_node.draw_rect(Rect2(e + Vector2(k, k) - Vector2.ONE * 0.5, Vector2(2, 2)), col)
					_preview_node.draw_rect(Rect2(e + Vector2(k, -k) - Vector2.ONE * 0.5, Vector2(2, 2)), col)
			"stop":
				var side := Vector2(-dir.y, dir.x)
				for k in range(-4, 5):
					_preview_node.draw_rect(Rect2(e + side * k - Vector2.ONE, Vector2(2, 2)), col)
			_:
				_preview_node.draw_arc(e, 7.0, 0.0, TAU, 16, col, 2.0)


## REEL BACK. Press E while carrying the wire and it yanks you back to the last
## pad it's wrapped round (the START, a node or a bend). Took a bend the wrong
## way? Reel back and pick again. The timer keeps running while you fly, so it
## costs a little time - but you never have to stand there waiting for it to run out.
func _reel_back() -> void:
	var target := _last_anchor
	var dist := player.position.distance_to(target)
	if dist < 6.0 or _anchor_cells.is_empty():
		return
	player.lock(true)
	_play("puff")
	_wire.strain(player.hand_position())              # a flash and sparks at your hands
	_reel_tween = create_tween()
	var secs := clampf(dist / 420.0, 0.12, 0.7)
	_reel_tween.tween_property(player, "position", target, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _reel_tween.finished
	_reel_tween = null
	if _wire == null or _busy:
		return                                        # the timer ran out on the way
	var c: Vector2i = _anchor_cells[-1]
	player.grab_wire()                                # walking with the wire again...
	match kind_at(c):
		"bend":                                       # ...or back to picking a way out
			var side: Vector2 = _bend_side.get(c, Vector2.RIGHT)
			_choosing_bend = c
			var t: PuzzleTile = _tiles.get(c)
			if t:
				t.show_choice(true, side)
			_show_fling_preview(c, side)
			var options: Array[Vector2] = [side, -side]
			player.choose_fling(center_of(c), options)
		"node":
			_set_paused_node(c)                       # standing on a node: timer paused
	_play("clank")


## Charge any power cell you're touching - but only with the live wire in hand.
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
			_time_left = minf(_time_left + _cell_bonus(), _wire_time() + _cell_bonus())
			hud.pulse_timer()
			_cells_pending.append(c)
			_play("pickup")
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
	_last_anchor = pc        # the tight wire now starts from this pad
	_wire.add_anchor(pc)
	_tile_hit(c)
	pad_touched.emit(kind, _wire_room.index)     # the tutorial listens for this
	match kind:
		"node":
			player.land()                  # a fling stops on a node
			_time_left = _wire_time()
			_set_paused_node(c)
			_play("node")
			hud.pulse_timer()
		"bend":
			_play("bend")
			# The two ways out are 90 degrees either side of the way the wire came in.
			var d := _snap8(pc - came_from)
			var side := Vector2(d.y, -d.x)
			_bend_side[c] = side                # remembered for reeling back here
			_choosing_bend = c
			var t: PuzzleTile = _tiles.get(c)
			if t:
				t.show_choice(true, side)
			_show_fling_preview(c, side)
			var options: Array[Vector2] = [side, -side]
			player.choose_fling(pc, options)
		"goal":
			_solve(_wire_room)


## Called by the player when he picks one of the bend's two arrows.
func bend_chosen() -> void:
	var t: PuzzleTile = _tiles.get(_choosing_bend)
	if t:
		t.show_choice(false, Vector2.ZERO)
	_choosing_bend = Vector2i(-1, -1)
	_hide_fling_preview()


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


## Rounds a direction to the nearest of the 8 compass directions.
func _snap8(v: Vector2) -> Vector2:
	var k := roundi(v.angle() / (PI / 4.0))
	return Vector2.RIGHT.rotated(k * PI / 4.0)


## Called by the player when the tight wire stops him walking somewhere.
func wire_strained(at: Vector2) -> void:
	if _wire == null or _strain_cd > 0.0:
		return
	_strain_cd = 0.4
	_wire.strain(_first_blocked_point(_last_anchor, at))
	_play("tick")
	if Game.first_time("strain"):
		_pip_say(pip_strain)     # the first time ever: why it stopped you


## A fling hit a wall or crate before reaching a pad.
func fling_stopped() -> void:
	_shake_cam(0.12, 1.5)


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


## The player pushed towards open space but can't go. Show why.
func player_drift_refused(at: Vector2, dir: Vector2) -> void:
	if _drift_warn_cd > 0.0:
		return
	_drift_warn_cd = 0.8
	if player.is_wired() and drift_landing(at, dir, Astronaut.FEET_HALF, false).is_finite():
		wire_strained(at + dir * 24.0)    # there IS a landing: it's the wire that's in the way
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


func _enter_room(r: Room) -> void:
	var new_area := _current_room == null or _current_room.area_id != r.area_id
	_current_room = r
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
	_bend_side.clear()
	_anchor_cells = [r.start]
	_last_anchor = sc
	_set_paused_node(Vector2i(-1, -1))
	_choosing_bend = Vector2i(-1, -1)
	_wire = Wire.new(Wire.Style.CABLE)
	_wire_root.add_child(_wire)
	_wire.begin(sc)
	_wire.set_live_end(player.hand_position())
	player.grab_wire()
	_time_left = _wire_time()     # the timer starts right away on the START pad
	_tick_accum = 0.0
	_play("grab")
	_set_hum(true)
	_tile_hit(r.start)
	_show_shared_pads(r)
	wire_grabbed.emit(r.index)      # the tutorial listens for this


## Nodes and bends from stages you already powered in this area work for this
## wire too - but they're easy to miss. So when you grab the wire, each of them
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

## PIP says one of his RULE lines (the pip_... texts in the Inspector, group
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
	return _wire == null and not _complete


## Give control back - unless PIP is still talking (then he's released when PIP stops).
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
	var w := _wire
	_wire = null
	w.finish()
	await w.power_flow(0.8)
	_hide_loop(r)
	for c in [r.goal, r.start, r.core]:
		var t: PuzzleTile = _tiles.get(c)
		if t:
			t.set_powered(true)
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
	# XP: for the room, for the batteries you kept, and a bonus if you never failed here
	_award_xp(Game.XP_ROOM + kept * Game.XP_CELL + (Game.XP_CLEAN if r.fails == 0 else 0))
	room_solved.emit(r.index)       # the tutorial, story and floor guides listen for this
	if kept > 0 and Game.first_time("cell_kept"):
		_pip_say(pip_cell_kept)
	if r.conduit:
		await r.conduit.power_flow(0.5)
	await _wait_for_holds()         # e.g. PIP glitching (rogue_pip.gd called hold())
	_open_exit_doors(r)
	if _rooms_powered >= _rooms_with_goal:
		await _all_powered()        # the lights-on cutscene: wait here until it's over
	await _offer_upgrades()         # levelled up? pick a suit upgrade now
	_busy = false
	_release_player()


# ===================================================================== RPG: XP, level ups, upgrades
# Doing well earns XP (Game.add_xp). Enough XP = LEVEL UP: the game pauses and
# you pick one suit upgrade (hud.pick_upgrade). Upgrades change the rules a
# little, so every rule they touch asks one of these small functions instead of
# reading wire_time or cell_bonus directly.

## Seconds on the wire timer: this level's wire_time + the LONGER WIRE upgrade.
func _wire_time() -> float:
	return wire_time + Game.wire_bonus()


## Seconds a battery adds: cell_bonus + the SUPER CELLS upgrade.
func _cell_bonus() -> float:
	return cell_bonus + Game.cell_bonus_extra()


## You stepped on something live (a red tile or a lit grate). With the RUBBER
## BOOTS upgrade the first zap in each room doesn't count: a spark, and you hop
## back to the last spot you stood on safely. You even keep the wire.
func _shock() -> void:
	var r := _current_room
	var can_hop := player.state in [Astronaut.State.FREE, Astronaut.State.WIRED, Astronaut.State.FLUNG]
	if Game.perk("boots") > 0 and r != null and not _boots_used.has(r) and can_hop and _last_safe.is_finite():
		_boots_used[r] = true
		player.land()                   # a fling stops right here
		player.position = _last_safe
		_play("shock")
		_shake_cam(0.2, 2.0)
		hud.flash(Color(0.75, 0.95, 1.0), 0.3)
		hud.show_toast(popup_boots, 2.0)
		return
	_fail("shock")


## Give XP: it floats up over the astronaut, and the console's XP bar fills.
## A level up is only REMEMBERED here (Game.upgrades_waiting); you pick the
## upgrade when it's safe (_offer_upgrades), not in the middle of a puzzle.
func _award_xp(amount: int) -> void:
	if amount <= 0:
		return
	_xp_gained += amount
	var ups := Game.add_xp(amount)
	hud.float_text("+%d XP" % amount)
	hud.set_xp(Game.lv, Game.level_progress())
	if ups > 0:
		_play("fanfare")
		hud.show_toast(popup_level_up.format({"lv": Game.lv}), 2.5)


## For every level up you haven't used yet: pause and pick an upgrade.
func _offer_upgrades() -> void:
	var picked := false
	while Game.upgrades_waiting > 0 and is_inside_tree():
		var choices := Game.upgrade_choices(3)
		if choices.is_empty():
			Game.upgrades_waiting = 0     # you've got every upgrade already
			break
		var id: String = await hud.pick_upgrade(choices, Game.lv)
		Game.take_upgrade(id)
		_apply_upgrades()
		picked = true
		_input_cooldown = 0.3           # the E that picked the card shouldn't grab a wire too
	if picked and Game.first_time("level_up"):
		_pip_say(pip_level_up)


## Upgrades that change something straight away (the others are read when needed).
func _apply_upgrades() -> void:
	player.speed_mult = Game.walk_multiplier()
	if _o2_on:
		_o2_max = o2_seconds + Game.o2_bonus()
	hud.set_xp(Game.lv, Game.level_progress())


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
	# every barrier group touching this stage sinks - the whole group, even the
	# crates that aren't right next to the stage
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
	hud.show_toast(popup_all_online, 2.5)
	await get_tree().create_timer(0.8).timeout
	await _power_tour()
	all_rooms_powered.emit()        # PIP says what to do next (StoryBeat: ALL_POWERED)


# ===================================================================== lights-on cutscene
# A cutscene is just a coroutine: a list of steps with `await` in between
# (glide there... light it up... wait a moment... next room). While it runs,
# _busy keeps the player frozen and _cutscene tells the camera to stop
# following him and look at _cut_cam instead.

## The camera glides back through every room - from the one you're in to the
## very first one - and each room lights up at FULL power as it arrives.
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
		_light_up(r, i)
		await get_tree().create_timer(1.1 if r.cells.size() > 12 else 0.7).timeout
	# let PIP finish what he's saying (but never wait forever)
	var wait := 4.0
	while hud.is_talking() and wait > 0.0:
		await get_tree().process_frame
		wait -= get_process_delta_time()
	await hud.fade_out(0.3)
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


## Moves the cutscene camera to room `r`: slow - fast - slow, like a film camera.
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


## One room goes to FULL power: brighter tint, lights flare, sparks, the floor
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
	bend_chosen()                   # hide the bend arrows if we were choosing
	if _reel_tween:
		_reel_tween.kill()          # stop a reel-back that was still pulling you
		_reel_tween = null
	hud.set_timer(false, 0.0, 0.0)
	hud.set_reel_prompt(false)
	var r := _wire_room if _wire_room != null else _current_room
	# Pressing R while NOT carrying the wire is just a reset, not a failed try.
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
			hud.flash(Color(0.75, 0.95, 1.0), 0.85)
			_shake_cam(0.5, 4.0)
			hud.show_toast(popup_zap)
			await get_tree().create_timer(0.85).timeout
			player.play_burnt()
			await get_tree().create_timer(0.45).timeout
		"timeout":
			_play("snap")
			hud.flash(Color(1.0, 0.45, 0.15), 0.45)
			_shake_cam(0.25, 2.0)
			hud.show_toast(popup_overload)
		"oxygen":
			_play("alarm")
			hud.flash(Color(0.4, 0.7, 1.0), 0.5)
			_shake_cam(0.3, 2.0)
			hud.show_toast(popup_out_of_air)
			await get_tree().create_timer(0.8).timeout
		"cut":
			# PIP's shutdown pulse (rogue_pip.gd) reached the wire
			_play("pulse")
			_play("snap")
			hud.flash(Color(1.0, 0.25, 0.2), 0.6)
			_shake_cam(0.45, 3.5)
			hud.show_toast(popup_pip_cut)
	if _wire != null:
		var w := _wire
		_wire = null
		await w.snap()
		w.queue_free()
	if kind == "restart":
		# R = "take me back": a quick fade and you're on the START pad again.
		await hud.fade_out(0.2)
		_respawn()
		if _o2_on:
			_refill_o2()
		await hud.fade_in(0.25)
	else:
		# Zapped / timer / oxygen: you stay where you fell. Walk back to the
		# START yourself (or press R to jump there).
		await _stay_after_fail()
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
	if counts and r != null and not r.solved and r.fails >= 2 and _room_has_hint(r) and not _hint_offered.has(r):
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
## back to safe floor - no teleport, no fade.
func _stay_after_fail() -> void:
	var r := _wire_room if _wire_room != null else _current_room
	_wire_room = null
	_anchor_cells.clear()
	var safe := _spot_after_fail(player.position)
	if safe.distance_to(player.position) > 0.5:
		var tw := create_tween()
		tw.tween_property(player, "position", safe, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await tw.finished
	var here: Room = _room_of.get(cell_of(player.position))
	if here != null:
		_current_room = here
	_release_player()
	if r != null and not r.solved:
		room_restarted.emit(r.index)   # the tutorial points you back to the START


## Where to put you after a fail. Where you are, if that's safe. Otherwise back
## to the last spot you stood on safely: that's the side you came FROM. (Just
## taking the nearest safe tile could push you THROUGH a wall of red tiles into
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


## After a fail: can you still WALK back to room r's START without stepping on a
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
			if kind_at(n) == "discharge" or kind_at(n) == "blinker":
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
	return k != "discharge" and k != "blinker" and not box_blocked(pos, Astronaut.FEET_HALF)


## The pads the wire from room r can use: its own, plus the NODES and BENDS of
## stages you already powered in the same area. Once the cargo between them has
## sunk, those pads are right there - so a later stage can wrap the wire round
## them from a new angle.
func _stage_pads(r: Room) -> Array[Vector2i]:
	var out: Array[Vector2i] = r.pads.duplicate()
	for o in _rooms:
		if o == r or not o.solved or o.area_id != r.area_id:
			continue
		for p in o.pads:
			if kind_at(p) == "node" or kind_at(p) == "bend":
				out.append(p)
	return out


# ===================================================================== blinking grates

## Is the grate at c lit right now? Each grate is lit for grate_live seconds out
## of every grate_cycle. Grates further along x are a little behind (grate_wave),
## so the light runs across the floor like a wave you can follow through the gap.
func blinker_live(c: Vector2i) -> bool:
	return _blinker_phase(c) < grate_live


func _blinker_phase(c: Vector2i) -> float:
	return fposmod(_light_t + c.x * grate_wave, grate_cycle)


## Would standing on tile c zap you right now? (red grates always, blinking ones when lit)
func _is_live_tile(c: Vector2i) -> bool:
	var k := kind_at(c)
	return k == "discharge" or (k == "blinker" and blinker_live(c))


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
	# 3. the outer door opens onto space - and the oxygen meter starts
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
	_award_xp(Game.XP_FINISH)                       # XP for reaching the exit
	var stats := {"time": _play_time, "cells": _cells_banked, "cells_total": _cells.size(),
		"retries": _retries, "retry_goal": retry_goal, "stars": stars, "hints": _hints_used,
		"xp": _xp_gained}
	Game.record_level(level_number, stats)
	await _offer_upgrades()                         # a level up at the exit? pick it first
	if not is_inside_tree():
		return
	hud.show_summary(level_number, complete_message, stats, Game.has_level(level_number + 1))
	_play("complete")
	level_completed.emit()


func _results_input() -> void:
	if _input_cooldown > 0.0 or _leaving:
		return
	if Input.is_action_just_pressed("interact"):
		_leave(level_number + 1)          # (no next level = back to the title screen)
	elif Input.is_action_just_pressed("restart"):
		_leave(level_number)


func _leave(number: int) -> void:
	_leaving = true
	await hud.fade_out(0.5)
	Game.go_to_level(number)


# ===================================================================== camera

func _shake_cam(duration: float, strength: float) -> void:
	_shake = duration
	_shake_strength = strength


## Follows the player but never shows outside the current AREA (all the stages
## joined to this one). If the area is smaller than the screen, the camera just
## sits in its middle. During the lights-on cutscene it looks at _cut_cam instead.
## The HUD's console covers the bottom CONSOLE_H pixels, so the "screen" we frame
## the room in is that much shorter, and the camera sits CONSOLE_H/2 lower than
## the point we want in the middle of it.
func _update_camera(delta: float, snap: bool) -> void:
	if camera == null or _current_room == null:
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
	var shake := Vector2.ZERO
	if _shake > 0.0:
		_shake -= delta
		shake = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength
	camera.position = (_cam_pos + below + shake).round()
