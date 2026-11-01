# ---------------------------------------------------------------------------
# level.gd  -  reads the map you PAINT, makes it look nice, and runs the RULES.
#
# BIG PICTURE
#   1. You paint the level on the "Layout" TileMapLayer with simple tiles
#      (floor, wall, start, goal, node, bend, red, crate, door, spawn, exit).
#      Each tile in the palette carries a hidden label called "kind"
#      (set in Assets/images/tiles/layout_tileset.tres -> Custom Data).
#   2. _read_layout() turns the painted tiles into a Dictionary:
#      tile position -> kind, e.g. Vector2i(3, 4) -> "node".
#   3. _build_visuals() uses that to draw the pretty version on 3 extra layers
#      (Ground, Walls, Props): tall wall panels, roof edges, floor variety.
#      In the editor this re-runs every time you paint, so you see the result live.
#   4. _build_rooms() finds the rooms (floor areas separated by walls/doors).
#   5. During play the player calls player_moved() every frame and that function
#      checks the rules: red tiles, new room, touching pads...
#   6. Lighting: the ship starts dark (CanvasModulate). Glowing things (wires,
#      pad halos, floor guides) use light channel 2, lit by one flat "glow
#      light" - see light_fx.gd. Each room has a red emergency light, and
#      ceiling lights that switch on when you power it.
#   7. The level ANNOUNCES what happens with signals (wire_grabbed, pad_touched,
#      room_solved, ...). The tutorial listens to those to know when to move on.
#
# THE WIRE RULES
#   - Press E on the START pad to grab the wire. The timer starts right away.
#   - You walk freely, but the wire is a tight straight line from the last pad
#     you touched to your hands. It can't pass through walls, crates or red
#     tiles - if a step would make it, you just can't take that step.
#   - NODE: wraps the wire, refills the timer and pauses it until you step off.
#   - BEND: stops you and shows two arrows; press one and it flings you 90 deg.
#   - GOAL: powers the room and opens the door.
#   - Timer hits 0, or you step on a red tile (with or without the wire)
#     -> the room restarts. The wire itself can't be stretched over red tiles.
# ---------------------------------------------------------------------------
@tool
class_name WireLevel
extends Node2D

# Signals: announcements other nodes can listen to. The tutorial listens to all
# of these; the floor guides listen to room_solved so they fade once a room is done.
signal room_entered(index: int)
signal room_solved(index: int)
signal room_restarted(index: int)            # you failed and the room reset
signal wire_grabbed(index: int)              # you picked up the wire in room `index`
signal pad_touched(kind: String, index: int) # the wire reached a node / bend / goal
signal level_completed

const TILE := 32
const DIRS4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

# How close (in pixels, from a pad's centre) counts as touching it. A tile is 32 px.
const START_RADIUS := 20.0
const NODE_RADIUS := 22.0
const GOAL_RADIUS := 20.0
const BEND_RADIUS := 16.0

const WALL_TEX := "res://Assets/images/tiles/wall_face.png"
const FLOOR_TEX := "res://Assets/images/tiles/floor.png"
const ROOF_TEX := "res://Assets/images/tiles/roof.png"
const PUZZLE_TEX := "res://Assets/images/tiles/puzzle_tiles.png"
# Which picture in puzzle_tiles.png belongs to which kind.
const PUZZLE_FRAME := {"start": 0, "goal": 1, "node": 2, "bend": 3, "discharge": 4,
	"discharge_off": 5, "crate": 6, "door": 7}
const SRC_WALL := 0
const SRC_FLOOR := 1
const SRC_ROOF := 2
const SRC_PUZZLE := 3
const SOUNDS := ["grab", "hum", "node", "bend", "shock", "snap", "powerup", "door", "complete", "tick"]

## The TileMapLayer you paint on. If empty, a child called "Layout" is used.
@export var layout: TileMapLayer
## Show the painted icons on top of the finished look while editing (off = preview the real look).
@export var show_layout_in_editor := true:
	set(value):
		show_layout_in_editor = value
		_apply_layout_visibility()

@export_group("Rules")
## Seconds you get from the START pad, and again at every NODE.
@export var wire_time := 5.0
## Should the timer stop while you pick a direction on a BEND?
@export var bend_pauses_timer := true

@export_group("Lighting")
## How dark the ship is before a room gets power (1,1,1 = no darkness at all).
@export var darkness := Color(0.2, 0.21, 0.3)
## Brightness of a room's lights once it's powered.
@export var room_light_energy := 0.75

@export_group("Room names")
## Shown for a moment when you walk into each room (in the order you reach them).
@export var room_titles: PackedStringArray = [
	"ROOM 1 - POWER UP",
	"ROOM 2 - NODES",
	"ROOM 3 - BENDS",
	"ROOM 4 - DISCHARGE",
]


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


# --- map data
var _kinds := {}               # Vector2i -> "floor" / "wall" / "node" / ...
var _rect := Rect2i()          # the area that has painted tiles
var _ground: TileMapLayer
var _walls: TileMapLayer
var _props: TileMapLayer
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

# --- state
var _busy := false             # true during win/lose animations: ignore input
var _complete := false
var _cam_pos := Vector2.ZERO
var _shake := 0.0
var _shake_strength := 0.0
var _sfx := {}
var _tile_root: Node2D
var _conduit_root: Node2D
var _wire_root: Node2D

# --- lighting
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
	_build_conduits()
	_setup_room_lights()
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
	_current_room = _room_of.get(_spawn)
	if camera:
		camera.make_current()
		_update_camera(0.0, true)
	_announce_room()


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
	# Backup in case the E / R actions are missing from Project Settings > Input Map.
	_add_key_action("interact", [KEY_E, KEY_SPACE])
	_add_key_action("restart", [KEY_R])


func _add_key_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ===================================================================== map helpers

## Reads every painted tile and asks it for its "kind" label.
func _read_layout() -> void:
	_kinds.clear()
	for c in layout.get_used_cells():
		var data := layout.get_cell_tile_data(c)
		if data == null:
			continue
		var kind := String(data.get_custom_data("kind"))
		if kind != "":
			_kinds[c] = kind
	_rect = layout.get_used_rect().grow(1)


## What is painted at tile `c`? "" means nothing (outside the ship).
func kind_at(c: Vector2i) -> String:
	return _kinds.get(c, "")


## Pixel position -> tile coordinates. floori rounds down (e.g. 70 / 32 = 2.18 -> 2).
func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


## Tile coordinates -> the pixel in the middle of that tile.
func center_of(c: Vector2i) -> Vector2:
	return Vector2(c * TILE) + Vector2(TILE, TILE) * 0.5


func _walkable(kind: String) -> bool:
	return kind != "" and kind != "wall"


func _is_room_cell(kind: String) -> bool:
	return _walkable(kind) and kind != "door"


## Can't WALK through: nothing, walls, crates, closed doors.
func is_solid_for_walk(c: Vector2i) -> bool:
	var kind := kind_at(c)
	if kind == "" or kind == "wall" or kind == "crate":
		return true
	if kind == "door":
		return not _open_doors.has(c)
	return false


## The WIRE can't pass over: nothing, walls, crates, doors, the exit, live red tiles.
func is_solid_for_wire(c: Vector2i) -> bool:
	return kind_at(c) in ["", "wall", "crate", "door", "exit", "discharge"]


## True if a box (centre `pos`, half-size `half`) overlaps anything solid.
func box_blocked(pos: Vector2, half: Vector2) -> bool:
	var x0 := floori((pos.x - half.x) / TILE)
	var x1 := floori((pos.x + half.x - 0.01) / TILE)
	var y0 := floori((pos.y - half.y) / TILE)
	var y1 := floori((pos.y + half.y - 0.01) / TILE)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if is_solid_for_walk(Vector2i(x, y)):
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


## Which room is this pixel in? (-1 = none). Used by the tutorial and floor guides.
func room_index_at(pos: Vector2) -> int:
	var r: Room = _room_of.get(cell_of(pos))
	return r.index if r != null else -1


# ===================================================================== visuals (also run in the editor)

func _build_visuals() -> void:
	_read_layout()
	var ts := _make_tileset()
	if _ground == null or not is_instance_valid(_ground):
		_ground = _new_layer("Ground", -10)
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
		if int(depth.get(c + Vector2i.UP, 0)) == 1:
			_ground.set_cell(c, SRC_WALL, Vector2i(0, 3))   # light strip under a wall panel
		else:
			_ground.set_cell(c, SRC_FLOOR, Vector2i(_floor_variant(c), 0))
		if PUZZLE_FRAME.has(kind) and (Engine.is_editor_hint() or kind == "crate"):
			var alt := 1 if (kind == "door" and _door_rotated(c)) else 0
			_props.set_cell(c, SRC_PUZZLE, Vector2i(PUZZLE_FRAME[kind], 0), alt)


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
## code from our 4 PNG files (the Layout layer uses its own .tres palette).
func _make_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	_add_atlas(ts, SRC_WALL, WALL_TEX, Vector2i(6, 4))
	_add_atlas(ts, SRC_FLOOR, FLOOR_TEX, Vector2i(3, 1))
	_add_atlas(ts, SRC_ROOF, ROOF_TEX, Vector2i(16, 16))
	var puzzle := _add_atlas(ts, SRC_PUZZLE, PUZZLE_TEX, Vector2i(9, 1))
	var alt := puzzle.create_alternative_tile(Vector2i(7, 0), 1)
	puzzle.get_tile_data(Vector2i(7, 0), alt).transpose = true   # door turned sideways
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


## A door with floor to its left/right sits in a side wall: draw its bar upright.
func _door_rotated(c: Vector2i) -> bool:
	var l := kind_at(c + Vector2i.LEFT)
	var r := kind_at(c + Vector2i.RIGHT)
	return (_walkable(l) and l != "door") or (_walkable(r) and r != "door")


# ===================================================================== rooms

## "Flood fill": start on a floor tile and keep stepping to neighbouring floor
## tiles until you can't. Everything you reached is one room.
func _build_rooms() -> void:
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
			for d in DIRS4:
				var n := cur + d
				if not _room_of.has(n) and _is_room_cell(kind_at(n)):
					_room_of[n] = room
					queue.append(n)
		_rooms.append(room)
	# doors and which rooms they join
	for c in _kinds:
		if _kinds[c] != "door":
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
	# camera bounds: room tiles + 1 tile of wall, + 3 tiles above for the wall panels
	for r in _rooms:
		var mn := Vector2i(1 << 20, 1 << 20)
		var mx := Vector2i(-(1 << 20), -(1 << 20))
		for c in r.cells:
			mn = mn.min(c)
			mx = mx.max(c)
		r.bounds = Rect2i(mn.x - 1, mn.y - 3, mx.x - mn.x + 3, mx.y - mn.y + 5)
	if not spawn_found:
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
	_check_rooms()


## Friendly warnings in the Output panel when the map is missing something.
func _check_rooms() -> void:
	for r in _rooms:
		if r.is_exit:
			continue
		var n := r.index + 1
		if r.start.x < 0:
			push_warning("Room %d has no START pad." % n)
		if r.goal.x < 0:
			push_warning("Room %d has no GOAL pad." % n)
		if _exit_doors(r).is_empty():
			push_warning("Room %d has no door leading onward." % n)


## Doors that lead from room r to a LATER room (the ones r's goal opens).
func _exit_doors(r: Room) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in r.doors:
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
		_tile_root.add_child(t)
		t.setup(PUZZLE_FRAME[kind], kind == "door" and _door_rotated(c))
		_tiles[c] = t


func _new_root(root_name: String, z: int) -> Node2D:
	var n := Node2D.new()
	n.name = root_name
	n.z_index = z
	add_child(n)
	return n


# ===================================================================== lighting

## The ship has no power: tint everything dark. Then add the flat "glow light"
## over the whole level, which only lights things that called LightFX.glow().
func _setup_darkness() -> void:
	var dark := CanvasModulate.new()
	dark.color = darkness
	add_child(dark)
	var area := Rect2(Vector2(_rect.position * TILE), Vector2(_rect.size * TILE))
	_glow_light = LightFX.make_glow_light(area)
	_glow_light.name = "GlowLight"
	add_child(_glow_light)


## Every room gets (a) a red emergency light that pulses while it has no power,
## and (b) a few ceiling lights that stay OFF until you power the room.
func _setup_room_lights() -> void:
	for r in _rooms:
		if r.is_exit:
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


## Draws an unpowered cable on the floor from each goal to the door it unlocks.
func _build_conduits() -> void:
	for r in _rooms:
		if r.goal.x < 0:
			continue
		var targets := _exit_doors(r)
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
func _conduit_path(r: Room, doors: Array[Vector2i]) -> PackedVector2Array:
	var prev := {r.goal: r.goal}
	var q: Array[Vector2i] = [r.goal]
	var head := 0
	var found := false
	var end_cell := r.goal
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
			if prev.has(n) or _room_of.get(n) != r or kind_at(n) == "crate":
				continue
			prev[n] = cur
			q.append(n)
	var pts := PackedVector2Array()
	if not found:
		return pts
	var cells: Array[Vector2i] = []
	var c := end_cell
	while c != r.goal:
		cells.append(c)
		c = prev[c]
	cells.append(r.goal)
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
	_sfx["hum"].finished.connect(_on_hum_finished)   # loop the hum while carrying


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


# ===================================================================== every frame

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or player == null:
		return
	if _complete:
		if Input.is_action_just_pressed("restart") or Input.is_action_just_pressed("interact"):
			get_tree().reload_current_scene()
		return
	_strain_cd = maxf(0.0, _strain_cd - delta)
	if _busy:
		_update_prompts()
		return
	if Input.is_action_just_pressed("restart"):
		_fail("restart")
		return
	if _wire != null and player.is_wired():
		_tick_timer(delta)
	else:
		hud.set_timer(false, 0.0, 0.0)
		if player.state == Astronaut.State.FREE and Input.is_action_just_pressed("interact"):
			_try_grab()
	_update_prompts()


func _timer_paused() -> bool:
	if _paused_node.x >= 0:
		return true
	return _choosing_bend.x >= 0 and bend_pauses_timer


func _tick_timer(delta: float) -> void:
	var paused := _timer_paused()
	if not paused:
		_time_left -= delta
	var frac := clampf(_time_left / wire_time, 0.0, 1.0)
	_wire.set_urgency(1.0 - frac)
	hud.set_timer(true, frac, maxf(_time_left, 0.0), paused)
	if _time_left < 1.5 and not paused:
		_tick_accum += delta
		if _tick_accum >= 0.25:
			_tick_accum = 0.0
			_play("tick")
	if _time_left <= 0.0:
		_fail("timeout")


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
		if not r.solved:
			pair[0].energy = 0.35 + 0.2 * sin(_light_t * 2.2)
	_update_camera(delta, false)


## Called by the player every time he moves. All the "did something happen?" checks.
func player_moved() -> void:
	if _busy or _complete:
		return
	var c := cell_of(player.position)
	if kind_at(c) == "discharge":
		_fail("shock")
		return
	if player.state == Astronaut.State.FREE:
		var r: Room = _room_of.get(c)
		if r != null and r != _current_room:
			_enter_room(r)
		return
	if _wire == null:
		return
	# Standing on a node pauses the timer; it starts again once you step off.
	if _paused_node.x >= 0 and player.position.distance_to(center_of(_paused_node)) > NODE_RADIUS + 4.0:
		_set_paused_node(Vector2i(-1, -1))
	# Did we touch a pad we haven't used yet?
	for pad in _wire_room.pads:
		if _anchor_cells.has(pad):
			continue
		var kind := kind_at(pad)
		var radius := BEND_RADIUS
		if kind == "node":
			radius = NODE_RADIUS
		elif kind == "goal":
			radius = GOAL_RADIUS
		var pc := center_of(pad)
		if player.position.distance_to(pc) > radius:
			continue
		if not _line_clear(_last_anchor, pc):
			continue          # the wire can't reach that pad's centre
		_touch_pad(pad, kind)
		return


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
			_time_left = wire_time
			_set_paused_node(c)
			_play("node")
			hud.pulse_timer()
		"bend":
			_play("bend")
			# The two ways out are 90 degrees either side of the way the wire came in.
			var d := _snap8(pc - came_from)
			var side := Vector2(d.y, -d.x)
			_choosing_bend = c
			var t: PuzzleTile = _tiles.get(c)
			if t:
				t.show_choice(true, side)
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


## A fling hit a wall or crate before reaching a pad.
func fling_stopped() -> void:
	_shake_cam(0.12, 1.5)


func _update_prompts() -> void:
	for r in _rooms:
		if r.start.x < 0:
			continue
		var t: PuzzleTile = _tiles.get(r.start)
		if t:
			t.prompt = (not _busy and player.state == Astronaut.State.FREE and not r.solved
				and r == _current_room and player.position.distance_to(center_of(r.start)) <= START_RADIUS)


func _enter_room(r: Room) -> void:
	_current_room = r
	if r.is_exit:
		_finish_level()
		return
	player.set_lamp(not r.solved)   # dark room = helmet lamp on, powered room = off
	_announce_room()
	room_entered.emit(r.index)


func _announce_room() -> void:
	if _current_room == null or _current_room.is_exit:
		return
	var i := _current_room.index
	var title := room_titles[i] if i >= 0 and i < room_titles.size() else "ROOM %d" % (i + 1)
	hud.show_toast(title)


func _try_grab() -> void:
	var r := _current_room
	if r == null or r.solved or r.start.x < 0:
		return
	var sc := center_of(r.start)
	if player.position.distance_to(sc) > START_RADIUS:
		return
	_wire_room = r
	_anchor_cells = [r.start]
	_last_anchor = sc
	_set_paused_node(Vector2i(-1, -1))
	_choosing_bend = Vector2i(-1, -1)
	_wire = Wire.new(Wire.Style.CABLE)
	_wire_root.add_child(_wire)
	_wire.begin(sc)
	_wire.set_live_end(player.hand_position())
	player.grab_wire()
	_time_left = wire_time        # the timer starts right away on the START pad
	_tick_accum = 0.0
	_play("grab")
	_set_hum(true)
	_tile_hit(r.start)
	wire_grabbed.emit(r.index)      # the tutorial listens for this


func _tile_hit(c: Vector2i) -> void:
	var t: PuzzleTile = _tiles.get(c)
	if t:
		t.hit()


# ===================================================================== win / lose
# These use `await`: the function pauses at that line until the animation or
# timer finishes, then carries on. Meanwhile the rest of the game keeps running.

func _solve(r: Room) -> void:
	_busy = true
	player.lock(true)
	_set_hum(false)
	_set_paused_node(Vector2i(-1, -1))
	r.solved = true
	hud.set_timer(false, 0.0, 0.0)
	_play("powerup")
	_shake_cam(0.2, 1.5)
	var w := _wire
	_wire = null
	w.finish()
	await w.power_flow(0.8)
	for c in [r.goal, r.start]:
		var t: PuzzleTile = _tiles.get(c)
		if t:
			t.set_powered(true)
	_power_room(r)                  # the lights come on!
	player.set_lamp(false)          # ...so he doesn't need his helmet lamp any more
	hud.show_toast("POWER RESTORED!")
	room_solved.emit(r.index)       # the tutorial and floor guides listen for this
	if r.conduit:
		await r.conduit.power_flow(0.5)
	var opened := false
	for d in _exit_doors(r):
		if not _open_doors.has(d):
			_open_doors[d] = true
			opened = true
			var t: PuzzleTile = _tiles.get(d)
			if t:
				t.open_door()
	if opened:
		_play("door")
	player.release()
	_busy = false


func _fail(kind: String) -> void:
	if _busy:
		return
	_busy = true
	_set_hum(false)
	_set_paused_node(Vector2i(-1, -1))
	bend_chosen()                   # hide the bend arrows if we were choosing
	hud.set_timer(false, 0.0, 0.0)
	player.lock(_wire != null)
	match kind:
		"shock":
			_play("shock")
			player.play_shock()
			hud.flash(Color(0.75, 0.95, 1.0), 0.85)
			_shake_cam(0.5, 4.0)
			hud.show_toast("ZAP!")
			await get_tree().create_timer(0.85).timeout
			player.play_burnt()
			await get_tree().create_timer(0.45).timeout
		"timeout":
			_play("snap")
			hud.flash(Color(1.0, 0.45, 0.15), 0.45)
			_shake_cam(0.25, 2.0)
			hud.show_toast("WIRE OVERLOADED!")
	if _wire != null:
		var w := _wire
		_wire = null
		await w.snap()
		w.queue_free()
	await hud.fade_out(0.2)
	_respawn()
	await hud.fade_in(0.25)
	_busy = false


func _respawn() -> void:
	var r := _wire_room if _wire_room != null else _current_room
	_wire_room = null
	_anchor_cells.clear()
	var target := _spawn
	if r != null and r.start.x >= 0:
		target = r.start
	player.release()
	player.position = center_of(target)
	_current_room = _room_of.get(target, r)
	if r != null and not r.solved:
		room_restarted.emit(r.index)   # the tutorial rewinds to this room's first step
	_update_camera(0.0, true)


func _finish_level() -> void:
	_complete = true
	player.lock(false)
	hud.set_timer(false, 0.0, 0.0)
	hud.show_complete()
	_play("complete")
	level_completed.emit()


# ===================================================================== camera

func _shake_cam(duration: float, strength: float) -> void:
	_shake = duration
	_shake_strength = strength


## Follows the player but never shows outside the current room. If the room is
## smaller than the screen, the camera just sits in the room's middle.
func _update_camera(delta: float, snap: bool) -> void:
	if camera == null or _current_room == null:
		return
	var view := get_viewport_rect().size
	var b := _current_room.bounds
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
	camera.position = (_cam_pos + shake).round()
