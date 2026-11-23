# ---------------------------------------------------------------------------
# autopilot.gd: judge mode's "PIP walks it for you". Press R in judge mode and
# PIP takes over the suit: he walks to the next unpowered room, sets the clamp
# down if that room needs it, grabs the wire and walks the route, then gives
# you control back. Press R again for the next room.
#
# Where the routes come from: tools/solver2.py works out the most forgiving
# route of every room and writes it to Data/routes/level_N.json (feet positions
# every 4 px). This script steers the astronaut to every one of those points,
# like a player holding the stick, so walls, the wire and touching pads all
# work exactly as when a person plays. Three things need a little help:
#   - a jump in the route is a drift across open space: he walks straight off
#     the edge (only a straight push starts a drift, see player.gd _slide)
#   - a corner can block a diagonal step (the game moves sideways first, then
#     up/down), so when he's stuck he tries one direction at a time
#   - the pillar wraps follow the route's "wraps" list (level.gd
#     autopilot_sync_wraps), because some routes only just graze a pillar
#   - movable crates: the route's "pushes" list says which crate to push which
#     way, in order. He puts the room's crates back first (like R), then walks
#     behind each crate and leans on it until it rolls (_push)
# While it runs, the timer doesn't tick and nothing zaps him (level.gd checks
# autopilot_on), so it can't fail. If a room has no route (someone changed the
# map and didn't run the solver again) or he gets stuck, PIP powers the room
# straight away.
#
# The level owns this node (level.gd, start_autopilot). It's all one coroutine
# (run): every await waits a physics frame, a walk or a cutscene.
# ---------------------------------------------------------------------------
class_name Autopilot
extends Node

const ROUTES := "res://Data/routes/level_%d.json"
const DRIFT_GAP := 8.0       # route points further apart than this = a drift across space

var level: WireLevel
var running := false
var debug := false           # true: print each step PIP takes (for finding where he gets stuck)
var _routes := {}            # START tile -> {"points": Array[Vector2], "clamp": Vector2i, "wraps": {index: [pads, poles]}, "pushes": [[crate, dir]...]}


var _hall_plans: Array = []  # halls with crates: {"cell": a tile of the hall, "pushes": [[crate, dir]...], "done": bool}


func _note(s: String) -> void:
	if debug:
		print("[autopilot] %s  (at %s, state %d)" % [s, level.player.position.round(), level.player.state])


## Reads this level's routes (made by the solver).
func load_routes(number: int) -> void:
	var path := ROUTES % number
	if not FileAccess.file_exists(path):
		push_warning("No autopilot routes: run  python tools/solver2.py Scenes/level_%d.tscn --paths Data/routes/level_%d.json --margin 3" % [number, number])
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return
	for h in data.get("halls", []):
		var pushes: Array = []
		for e in h["pushes"]:
			pushes.append([Vector2i(int(e[0]), int(e[1])), Vector2i(int(e[2]), int(e[3]))])
		_hall_plans.append({"cell": Vector2i(int(h["hall"][0]), int(h["hall"][1])), "pushes": pushes, "done": false})
	for k in data:
		if k == "halls":
			continue
		var r: Dictionary = data[k]
		var pts: Array[Vector2] = []
		for p in r["points"]:
			pts.append(Vector2(p[0], p[1]))
		var clamp := Vector2i(-1, -1)
		if r.get("clamp") != null:
			clamp = Vector2i(int(r["clamp"][0]), int(r["clamp"][1]))
		var wraps := {}          # point index -> [pads touched, the pillars wrapped after the last pad]
		for e in r.get("wraps", []):
			wraps[int(e[0])] = [int(e[1]), e[2]]
		var pushes: Array = []   # [crate tile, direction] in order
		for e in r.get("pushes", []):
			pushes.append([Vector2i(int(e[0]), int(e[1])), Vector2i(int(e[2]), int(e[3]))])
		_routes[Vector2i(int(r["start"][0]), int(r["start"][1]))] = {"points": pts, "clamp": clamp, "wraps": wraps, "pushes": pushes}


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
	await _do_hall_plans()
	_note("room %d, START %s" % [r.index + 1, r.start])
	await _open_the_way(r.start)
	var route: Dictionary = _routes.get(r.start, {})
	# 0. the crates: put them back where they started, then push them like the route says
	var pushes: Array = route.get("pushes", [])
	if not pushes.is_empty():
		level.reset_crates(r, true)
		for p in pushes:
			if not await _push(p[0], p[1]):
				_note("couldn't push the crate at %s" % p[0])
				level.autopilot_force_solve(r)
				await _wait_quiet()
				return
	# 1. the clamp, if this room's route needs it in a socket
	var sock: Vector2i = route.get("clamp", Vector2i(-1, -1))
	if sock.x >= 0 and level.clamp_socket() != sock:
		if not await _fetch_clamp():
			_note("couldn't get the clamp")
			level.autopilot_force_solve(r)
			await _wait_quiet()
			return
		if not await _walk_next_to(sock):
			_note("couldn't reach socket %s" % sock)
			level.autopilot_force_solve(r)
			await _wait_quiet()
			return
		level.place_clamp_at(sock)
	# 2. any fuse lying where we can reach it (the next locked door might need it)
	await _collect_reachable_items()
	# 3. to the START, grab the wire, and walk the route
	if not await _walk_to_cell(r.start):
		_note("couldn't walk to the START")
		level.autopilot_force_solve(r)
		await _wait_quiet()
		return
	level.autopilot_grab()
	var pts: Array = route.get("points", [])
	if pts.is_empty():
		_note("no route for this room")
		level.autopilot_force_solve(r)
		await _wait_quiet()
		return
	var wraps: Dictionary = route.get("wraps", {})
	var want: Array = [1, []]                # [pads touched, pillars wrapped] where the route is now
	level.autopilot_wraps = true
	for i in pts.size():
		if r.solved or not is_inside_tree():
			break
		want = wraps.get(i, want)
		var ok: bool
		if i > 0 and pts[i].distance_to(pts[i - 1]) > DRIFT_GAP:
			ok = await _drift(pts[i - 1], pts[i])
		else:
			ok = await _steer_to(pts[i], 2.0)
		if not ok:
			_note("stuck on the route at point %d of %d, wanted %s" % [i, pts.size(), pts[i]])
			break
		level.autopilot_sync_wraps(want[0], want[1])
	if is_inside_tree():
		level.autopilot_wraps = false
	if not r.solved and is_inside_tree():
		await _steer_to(pts[-1], 1.5)
	# the room should be powering up now; if not, PIP does it
	var wait := 1.0
	while not r.solved and wait > 0.0 and is_inside_tree():
		await get_tree().physics_frame
		wait -= get_physics_process_delta_time()
	if not r.solved and is_inside_tree():
		_note("route walked but the room didn't power")
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
func _steer_to(target: Vector2, close_enough: float, stop_on_drift := false) -> bool:
	var p := level.player
	var best := p.position.distance_to(target)
	var stuck := 0.0
	while is_inside_tree():
		if stop_on_drift and p.state == Astronaut.State.DRIFT:
			p.auto_dir = Vector2.ZERO
			return true                                # already pushed off the edge: that's the drift
		if p.state == Astronaut.State.DRIFT or level.is_busy():
			p.auto_dir = Vector2.ZERO
			await get_tree().physics_frame             # floating across space, or a cutscene
			continue
		var d := target - p.position
		if d.length() <= close_enough:
			return true
		p.auto_dir = d.normalized()
		if stuck > 0.15:
			var axis := _free_axis(d)                  # a corner in the way: one direction at a time
			if axis != Vector2.ZERO:
				p.auto_dir = axis
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


## Stuck going diagonally? The game moves you sideways first and then up or
## down, so the corner of a wall (or of open space) can stop a diagonal step.
## A player would then press one direction at a time: so do we. Tries the
## bigger direction first, and only one he can really step into (not open
## space, which would start a drift).
func _free_axis(d: Vector2) -> Vector2:
	var pos := level.player.position
	var axes := [Vector2(signf(d.x), 0.0), Vector2(0.0, signf(d.y))]
	if absf(d.y) > absf(d.x):
		axes.reverse()
	for axis in axes:
		if axis == Vector2.ZERO:
			continue
		var next: Vector2 = pos + axis * 2.0
		if level.box_blocked(next, Astronaut.FEET_HALF):
			continue
		if level.player.is_wired() and not level.wire_reaches(next):
			continue
		return axis
	return Vector2.ZERO


## Two route points far apart = the route drifts across open space there.
## Get exactly onto the edge spot, push straight towards the gap (a straight
## push is what starts a drift), then float until he lands.
func _drift(from: Vector2, to: Vector2) -> bool:
	var p := level.player
	var d := to - from
	var dir := Vector2(signf(d.x), 0.0) if absf(d.x) > absf(d.y) else Vector2(0.0, signf(d.y))
	if not await _steer_to(from, 1.0, true):
		return false
	var t := 0.0
	while is_inside_tree() and p.state != Astronaut.State.DRIFT and t < 1.0:
		p.auto_dir = dir
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	p.auto_dir = Vector2.ZERO
	while is_inside_tree() and p.state == Astronaut.State.DRIFT:
		await get_tree().physics_frame
	return is_inside_tree() and p.position.distance_to(to) < 12.0


## A hall with movable crates (the hub): the solver worked out which pushes open
## the way to every door and item there. Do that once, as soon as he can walk
## into that hall (then the fuse in it can be picked up).
func _do_hall_plans() -> void:
	for plan in _hall_plans:
		if plan["done"] or plan["pushes"].is_empty():
			continue
		var hall = level.room_at_cell(plan["cell"])
		var first: Array = plan["pushes"][0]
		var here := level.cell_of(level.player.position)
		level.reset_crates(hall, true)
		if level.walk_path(here, first[0] - first[1]).is_empty() and here != first[0] - first[1]:
			continue                                   # can't get there yet
		_note("hall plan at %s" % plan["cell"])
		plan["done"] = true
		for p in plan["pushes"]:
			if not await _push(p[0], p[1]):
				_note("hall plan: couldn't push the crate at %s" % p[0])
				break
	await _collect_reachable_items()


## Pushes the crate on tile `c` one tile along `d`: walk to the tile behind it,
## then lean on it (like holding the stick that way) until it rolls.
func _push(c: Vector2i, d: Vector2i) -> bool:
	if not level.crate_at(c):
		return false
	var behind := c - d
	if not await _walk_to_cell(behind):
		return false
	if not await _steer_to(level.center_of(behind), 1.5):
		return false
	var p := level.player
	var t := 0.0
	while is_inside_tree() and level.crate_at(c) and t < 1.5:
		p.auto_dir = Vector2(d)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	p.auto_dir = Vector2.ZERO
	if not is_inside_tree() or level.crate_at(c):
		return false
	# let it finish rolling (and sinking, on a red tile) before the next one
	var wait := 0.0
	while is_inside_tree() and wait < PushCrate.SLIDE_TIME + 0.15:
		await get_tree().physics_frame
		wait += get_physics_process_delta_time()
	return is_inside_tree()


## Walks (no wire) to a tile, along a path round walls and red tiles.
func _walk_to_cell(goal: Vector2i) -> bool:
	if goal.x < 0:
		return false
	var here := level.cell_of(level.player.position)
	if here == goal:                                   # already on it: just step to its middle
		return await _steer_to(level.center_of(goal), 3.0)
	var path: Array[Vector2i] = level.walk_path(here, goal)
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
