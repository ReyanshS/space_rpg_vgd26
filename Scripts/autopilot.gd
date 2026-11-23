# ---------------------------------------------------------------------------
# autopilot.gd: judge mode's "PIP walks it for you". Press R in judge mode and
# PIP takes over the suit: he walks to the next unpowered room, sets the clamp
# down if that room needs it, grabs the wire and walks the route, then gives
# you control back. Press R again for the next room.
#
# Where the routes come from: tools/solver2.py works out the most forgiving
# route of every room and writes it to Data/routes/level_N.json (feet positions
# every 4 px). This script just steers the astronaut along those points, like
# a player holding the stick, so walls, the wire, wrapping round pillars and
# touching pads all work exactly as when a person plays. While it runs, the
# timer doesn't tick and nothing zaps him (level.gd checks autopilot_on), so it
# can't fail. If a room has no route (someone changed the map and didn't run
# the solver again) or he gets stuck, PIP powers the room straight away.
#
# The level owns this node (level.gd, start_autopilot). It's all one coroutine
# (run): every await waits a physics frame, a walk or a cutscene.
# ---------------------------------------------------------------------------
class_name Autopilot
extends Node

const ROUTES := "res://Data/routes/level_%d.json"
const STEP_EVERY := 3        # follow every 3rd route point (they're 4 px apart)

var level: WireLevel
var running := false
var _routes := {}            # START tile -> {"points": Array[Vector2], "clamp": Vector2i}


## Reads this level's routes (made by the solver).
func load_routes(number: int) -> void:
	var path := ROUTES % number
	if not FileAccess.file_exists(path):
		push_warning("No autopilot routes: run  python tools/solver2.py Scenes/level_%d.tscn --paths Data/routes/level_%d.json --margin 3" % [number, number])
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return
	for k in data:
		var r: Dictionary = data[k]
		var pts: Array[Vector2] = []
		for p in r["points"]:
			pts.append(Vector2(p[0], p[1]))
		var clamp := Vector2i(-1, -1)
		if r.get("clamp") != null:
			clamp = Vector2i(int(r["clamp"][0]), int(r["clamp"][1]))
		_routes[Vector2i(int(r["start"][0]), int(r["start"][1]))] = {"points": pts, "clamp": clamp}


## One press of R: do the next room.
func run() -> void:
	if running:
		return
	running = true
	level.autopilot_begin()
	await _do_next_room()
	if is_inside_tree():
		level.autopilot_end()
	running = false


func _do_next_room() -> void:
	var r = level.autopilot_target()
	if r == null:
		await _open_the_way(level.exit_cell())
		if not await _walk_to_cell(level.exit_cell()):    # everything's done: off to the exit
			level.autopilot_to_exit()
		return
	await _open_the_way(r.start)
	var route: Dictionary = _routes.get(r.start, {})
	# 1. the clamp, if this room's route needs it in a socket
	var sock: Vector2i = route.get("clamp", Vector2i(-1, -1))
	if sock.x >= 0 and level.clamp_socket() != sock:
		if not await _fetch_clamp():
			level.autopilot_force_solve(r)
			await _wait_quiet()
			return
		if not await _walk_next_to(sock):
			level.autopilot_force_solve(r)
			await _wait_quiet()
			return
		level.place_clamp_at(sock)
	# 2. any fuse lying where we can reach it (the next locked door might need it)
	await _collect_reachable_items()
	# 3. to the START, grab the wire, and walk the route
	if not await _walk_to_cell(r.start):
		level.autopilot_force_solve(r)
		await _wait_quiet()
		return
	level.autopilot_grab()
	var pts: Array = route.get("points", [])
	if pts.is_empty():
		level.autopilot_force_solve(r)
		await _wait_quiet()
		return
	for i in range(0, pts.size(), STEP_EVERY):
		if r.solved or not is_inside_tree():
			break
		if not await _steer_to(pts[i], 2.0):
			break
	if not r.solved and is_inside_tree():
		await _steer_to(pts[-1], 1.5)
	# the room should be powering up now; if not, PIP does it
	var wait := 1.0
	while not r.solved and wait > 0.0 and is_inside_tree():
		await get_tree().physics_frame
		wait -= get_physics_process_delta_time()
	if not r.solved and is_inside_tree():
		level.autopilot_force_solve(r)
	await _wait_quiet()


## No way to `goal` yet? Maybe an airlock has to cycle first (the outer door
## only opens once you step on its pad): walk onto the pad and wait for it.
func _open_the_way(goal: Vector2i) -> void:
	if goal.x < 0:
		return
	var here := level.cell_of(level.player.position)
	if not level.walk_path(here, goal).is_empty():
		return
	for pad in level.airlock_cells():
		if not level.walk_path(here, pad).is_empty():
			await _walk_to_cell(pad)
			await get_tree().physics_frame
			await _wait_quiet()
			return


## Waits until the level isn't busy (win animation, links, cutscenes).
func _wait_quiet() -> void:
	var t := 0.0
	while is_inside_tree() and (level.is_busy() or level.player.state == Astronaut.State.LOCKED) and t < 25.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


## Steer towards a point, like holding the stick that way. Returns false if he
## stops getting closer (stuck against something) for a while.
func _steer_to(target: Vector2, close_enough: float) -> bool:
	var p := level.player
	var best := p.position.distance_to(target)
	var stuck := 0.0
	while is_inside_tree():
		if p.state == Astronaut.State.DRIFT or level.is_busy():
			p.auto_dir = Vector2.ZERO
			await get_tree().physics_frame             # floating across space, or a cutscene
			continue
		var d := target - p.position
		if d.length() <= close_enough:
			return true
		p.auto_dir = d.normalized()
		await get_tree().physics_frame
		var now := p.position.distance_to(target)
		if now < best - 0.05:
			best = now
			stuck = 0.0
		else:
			stuck += get_physics_process_delta_time()
			if stuck > 0.8:
				p.auto_dir = Vector2.ZERO
				return false
	return false


## Walks (no wire) to a tile, along a path round walls and red tiles.
func _walk_to_cell(goal: Vector2i) -> bool:
	if goal.x < 0:
		return false
	var path: Array[Vector2i] = level.walk_path(level.cell_of(level.player.position), goal)
	if path.is_empty():
		return false
	for c in path:
		if not await _steer_to(level.center_of(c), 3.0):
			return false
	return true


## Walks to a floor tile next to `c` (for a socket, which you stand beside).
func _walk_next_to(c: Vector2i) -> bool:
	for d in WireLevel.DIRS4:
		var n: Vector2i = c + d
		if not level.walk_path(level.cell_of(level.player.position), n).is_empty():
			return await _walk_to_cell(n)
	return false


## Gets the clamp into your hands: pick it up off the floor, or out of the
## socket it's standing in.
func _fetch_clamp() -> bool:
	if level.has_clamp():
		return true
	var at := level.clamp_socket()
	if at.x >= 0:
		if not await _walk_next_to(at):
			return false
		level.take_clamp()
		return true
	var item := level.item_cell("clamp")
	if item.x < 0 or not await _walk_to_cell(item):
		return false
	await get_tree().physics_frame                     # the level picks it up as he walks on it
	return level.has_clamp()


func _collect_reachable_items() -> void:
	for kind in ["fuse", "clamp"]:
		var c := level.item_cell(kind)
		while c.x >= 0 and not level.walk_path(level.cell_of(level.player.position), c).is_empty():
			await _walk_to_cell(c)
			await get_tree().physics_frame
			var next := level.item_cell(kind)
			if next == c:
				break
			c = next
