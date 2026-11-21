# ---------------------------------------------------------------------------
# puzzle_tile.gd: one interactive floor tile. Start, goal, node, pole,
# red discharge, door, gangway (a door out in space: a catwalk that extends
# across the gap when the hull section is powered), airlock pad, barrier
# (a cargo stack on a lift that sinks into the floor when its stage is powered),
# blinking grate (Kind.DISCHARGE_OFF: the level turns it on and off), or core
# (Level 3: a round socket you wrap the wire round; a ring shows how far round
# you've got, see show_loop).
#
# The level creates these in code (PuzzleTile.new() + setup()). Each one has:
#   - a Sprite2D showing the right 32x32 picture (gets darker when the ship is dark)
#   - a "glow" copy drawn with add blending (colours add up = brighter). It's on
#     the glow light channel (LightFX.glow), so the darkness doesn't dim it and
#     the pad looks like it shines. Sparks and arrows are on that channel too.
#   - a small PointLight2D that lights up the floor around it.
# The tile doesn't know any game rules. The level just calls hit(),
# set_powered(), open_door() etc. and the tile plays the matching animation.
# ---------------------------------------------------------------------------
class_name PuzzleTile
extends Node2D

# An enum is a list of named numbers: Kind.START == 0, Kind.GOAL == 1, ...
# The order matches the pictures in puzzle_tiles.png from left to right
# (DOOR_OPEN and GANGWAY_OPEN are the "after" pictures of a door / gangway).
enum Kind { START, GOAL, NODE, POLE, DISCHARGE, DISCHARGE_OFF, CRATE, DOOR,
	DOOR_OPEN, GANGWAY, GANGWAY_OPEN, AIRLOCK, BARRIER, CORE }

const SHEET_PATH := "res://Assets/images/tiles/puzzle_tiles.png"
const DOOR_OPEN_FRAME := 8
const GLOW := {
	Kind.START: Color(1.0, 0.85, 0.3),
	Kind.GOAL: Color(0.35, 0.65, 1.0),
	Kind.NODE: Color(1.0, 0.55, 0.2),
	Kind.POLE: Color(0.75, 0.45, 1.0),
	Kind.DISCHARGE: Color(1.0, 0.25, 0.25),
	Kind.DISCHARGE_OFF: Color(1.0, 0.25, 0.25),   # a blinking grate (red while lit)
	Kind.DOOR: Color(0.4, 1.0, 0.55),
	Kind.GANGWAY: Color(1.0, 0.75, 0.3),
	Kind.AIRLOCK: Color(1.0, 0.78, 0.3),
	Kind.BARRIER: Color(1.0, 0.6, 0.2),
	Kind.CORE: Color(0.35, 1.0, 0.6),
}
const LOOP_COLOR := Color(1.0, 0.82, 0.25)    # the same yellow as the live wire
const DOOR_LOCKED := Color(1.0, 0.3, 0.25)

# "static" = shared by all tiles, so the picture is only loaded once.
static var _sheet: Texture2D
static var _add_mat: CanvasItemMaterial

var kind: int = Kind.START
var powered := false          # room solved: shine brightly
var active := false           # this node is the one you're standing on (timer paused)
var is_open := false          # doors only
var live := false             # blinking grates: lit right now
var _warning := false         # blinking grates: about to light up
## Shows the floating [E] key above START pads.
var prompt := false:
	set(v):
		if v != prompt:
			prompt = v
			if _prompt_node:
				_prompt_node.queue_redraw()

var _sprite: Sprite2D
var _glow: Sprite2D
var _light: PointLight2D
var _crackle: CPUParticles2D
var _prompt_node: Node2D
var _post_node: Node2D        # poles: the post standing on the purple plate
var _loop_node: Node2D
var _loop_on := false
var _loop_from := 0.0         # the angle the loop starts at (towards the START pad)
var _loop_turn := 0.0         # how far round the wire has gone (TAU = all the way)
var _t := 0.0
var _flick := 0.0


## `rotated`: turn the picture 90 degrees (doors in side walls).
func setup(p_kind: int, rotated := false) -> PuzzleTile:
	kind = p_kind
	if _sheet == null:
		_sheet = load(SHEET_PATH)
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sprite = _make_sprite(kind)
	add_child(_sprite)
	if kind == Kind.GANGWAY:
		LightFX.glow(_sprite)      # the retracted catwalk's outline shines in space
	if GLOW.has(kind):
		var col: Color = DOOR_LOCKED if _is_door() else GLOW[kind]   # locked doors glow red
		_glow = _make_sprite(kind)
		_glow.material = _add_mat
		_glow.modulate = Color(col, 0.0)
		_add_fx(_glow)
		# a small light so the floor around the pad is lit too
		if kind != Kind.DISCHARGE and kind != Kind.DISCHARGE_OFF:
			_light = LightFX.make(col, 44.0, 0.55)
			add_child(_light)
	if rotated:
		_sprite.rotation = PI / 2.0
		if _glow:
			_glow.rotation = PI / 2.0
	if kind == Kind.DISCHARGE or kind == Kind.DISCHARGE_OFF:
		_crackle = Wire.make_sparks(Color(1.0, 0.45, 0.4), 4, 0.3)
		_crackle.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		_crackle.emission_rect_extents = Vector2(11, 11)
		_crackle.initial_velocity_min = 10.0
		_crackle.initial_velocity_max = 35.0
		_crackle.gravity = Vector2.ZERO
		_crackle.randomness = 1.0
		_add_fx(_crackle)
		_crackle.emitting = kind == Kind.DISCHARGE      # blinking grates only crackle while lit
	if kind == Kind.START:
		_prompt_node = _make_overlay(_draw_prompt)
	if kind == Kind.POLE:
		_post_node = Node2D.new()
		_post_node.z_index = 6      # relative to the tile (-7): -1, so just under the player
		add_child(_post_node)
		_post_node.draw.connect(_draw_post)
	if kind == Kind.CORE:
		_loop_node = _make_overlay(_draw_loop)
		_loop_node.z_index = 6      # relative to the tile (-7): -1, so just under the player
	_t = randf() * TAU
	return self


## Adds a glowing extra (halo, sparks, arrows) to this tile.
func _add_fx(n: Node2D) -> void:
	LightFX.glow(n)
	add_child(n)


## A node we draw on ourselves (arrows, the [E] key). Its "draw" signal is
## connected to one of our functions, which does the actual drawing.
func _make_overlay(draw_func: Callable) -> Node2D:
	var n := Node2D.new()
	n.z_index = 20      # relative to the tile (-7): 13, so above the player (0)
	_add_fx(n)
	n.draw.connect(draw_func)
	return n


func _make_sprite(frame: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _sheet
	s.region_enabled = true                       # only show part of the sheet...
	s.region_rect = Rect2(frame * 32, 0, 32, 32)  # ...this 32x32 square
	return s


func _process(delta: float) -> void:
	_t += delta
	if _glow and not is_open:
		var a := 0.0
		match kind:
			Kind.START, Kind.GOAL, Kind.NODE, Kind.POLE, Kind.AIRLOCK, Kind.CORE:
				a = 0.18 + 0.12 * sin(_t * 3.0)     # slow gentle pulse
			Kind.DISCHARGE:
				a = 0.3 + 0.2 * sin(_t * 9.0)
			Kind.DISCHARGE_OFF:
				if live:
					a = 0.3 + 0.2 * sin(_t * 9.0)
				elif _warning:
					a = 0.25 if int(_t * 20.0) % 2 == 0 else 0.0     # quick flicker: "watch out"
			Kind.DOOR, Kind.GANGWAY, Kind.BARRIER:
				a = 0.12 + 0.08 * sin(_t * 2.0)
		if active:
			a = 0.5 + 0.25 * sin(_t * 10.0)       # fast pulse: "timer paused here"
		if powered:
			a = 0.5 + 0.2 * sin(_t * 8.0)
		_glow.modulate.a = a
	if _light:
		var e := 0.5 + 0.08 * sin(_t * 3.0)
		if active:
			e = 0.8 + 0.2 * sin(_t * 10.0)
		if powered:
			e = 0.9
		_light.energy = e
	if kind == Kind.DISCHARGE or (kind == Kind.DISCHARGE_OFF and live):
		_flick -= delta
		if _flick <= 0.0:
			_flick = randf_range(0.04, 0.35)
			_sprite.modulate = Color(1.5, 1.4, 1.4) if randf() < 0.3 else Color.WHITE
	if prompt and _prompt_node:
		_prompt_node.queue_redraw()
	if _post_node:
		_post_node.queue_redraw()        # the cap glows softly
	if _loop_on and _loop_node:
		_loop_node.queue_redraw()


## Draws a little keyboard key with an "E" on it above the START pad.
func _draw_prompt() -> void:
	if not prompt:
		return
	var bob := roundf(sin(_t * 5.0) * 1.5)
	var o := Vector2(-6, -46 + bob)
	_prompt_node.draw_rect(Rect2(o + Vector2(0, 1), Vector2(13, 13)), Color(0.05, 0.05, 0.1, 0.9))
	_prompt_node.draw_rect(Rect2(o, Vector2(13, 13)), Color(0.95, 0.95, 1.0))
	_prompt_node.draw_rect(Rect2(o + Vector2(1, 1), Vector2(11, 10)), Color(0.82, 0.84, 0.92))
	var ink := Color(0.12, 0.12, 0.2)
	_prompt_node.draw_rect(Rect2(o + Vector2(4, 3), Vector2(1, 6)), ink)
	_prompt_node.draw_rect(Rect2(o + Vector2(4, 3), Vector2(5, 1)), ink)
	_prompt_node.draw_rect(Rect2(o + Vector2(4, 5), Vector2(4, 1)), ink)
	_prompt_node.draw_rect(Rect2(o + Vector2(4, 8), Vector2(5, 1)), ink)


## POLE: a short purple post on its plate. The wire wraps round its middle
## (the tile's centre, where level.gd puts the corner of the wire).
func _draw_post() -> void:
	var dark := Color(0.22, 0.1, 0.34)
	var body := Color(0.55, 0.3, 0.8)
	var light := Color(0.85, 0.65, 1.0)
	_post_node.draw_rect(Rect2(-6, 1, 12, 4), Color(0, 0, 0, 0.35))          # shadow on the floor
	_post_node.draw_rect(Rect2(-5, -15, 10, 18), dark)                       # outline
	_post_node.draw_rect(Rect2(-4, -14, 8, 16), body)                        # the post
	_post_node.draw_rect(Rect2(-3, -14, 2, 16), light)                       # it catches the light
	_post_node.draw_rect(Rect2(2, -14, 2, 16), body.darkened(0.3))           # ...and the shade
	var glow := 0.6 + 0.4 * sin(_t * 3.0) if not powered else 1.0
	_post_node.draw_rect(Rect2(-5, -17, 10, 3), dark)                        # the cap
	_post_node.draw_rect(Rect2(-4, -16, 8, 2), Color(1.0, 0.8, 1.0, glow))


## CORE: the level calls this every frame while you carry the wire in its room.
## `from` = the angle the loop starts at, `turn` = how far round the wire has
## gone (radians, positive or negative depending on which way you're going round).
func show_loop(on: bool, from: float, turn: float) -> void:
	_loop_on = on
	_loop_from = from
	_loop_turn = turn
	if _loop_node:
		_loop_node.queue_redraw()


## A dim circle round the socket, and a bright yellow arc over it: as far round
## as the wire has gone. When the arc meets its own start, the loop is closed.
func _draw_loop() -> void:
	if not _loop_on:
		return
	var r := 22.0
	_loop_node.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(LOOP_COLOR, 0.18), 3.0)
	# a tick where the loop starts (and has to end)
	var tick := Vector2.RIGHT.rotated(_loop_from)
	_loop_node.draw_line(tick * (r - 4.0), tick * (r + 4.0), Color(1, 1, 1, 0.8), 2.0)
	var amount := clampf(_loop_turn, -TAU, TAU)
	if absf(amount) > 0.02:
		var near_done := absf(amount) > TAU * 0.75
		var col := LOOP_COLOR.lerp(Color.WHITE, 0.4 + 0.3 * sin(_t * 12.0)) if near_done else LOOP_COLOR
		var steps := maxi(4, int(absf(amount) / TAU * 40.0))
		_loop_node.draw_arc(Vector2.ZERO, r, _loop_from, _loop_from + amount, steps, Color(0.1, 0.06, 0.0), 5.0)
		_loop_node.draw_arc(Vector2.ZERO, r, _loop_from, _loop_from + amount, steps, col, 3.0)


## Blinking grates: the level switches them on and off every frame.
## warning = it's about to light up (the glow flickers).
func set_live(on: bool, warning := false) -> void:
	_warning = warning and not on
	if on == live:
		return
	live = on
	var frame := Kind.DISCHARGE if on else Kind.DISCHARGE_OFF
	_sprite.region_rect = Rect2(frame * 32, 0, 32, 32)
	if _glow:
		_glow.region_rect = _sprite.region_rect
	if _crackle:
		_crackle.emitting = on
	if not on:
		_sprite.modulate = Color.WHITE


## Quick flash + spark burst when the wire touches this tile.
func hit() -> void:
	burst(GLOW.get(kind, Color.WHITE), 14)
	_sprite.scale = Vector2(1.25, 1.25)
	# A Tween animates a property over time: here, scale goes back to 1 in 0.18 s.
	var tw := create_tween()
	tw.tween_property(_sprite, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _glow:
		_glow.modulate.a = 0.9


func set_powered(on: bool) -> void:
	powered = on
	if on:
		burst(GLOW.get(kind, Color.WHITE), 20)


## One-off explosion of little square sparks.
func burst(color: Color, amount: int) -> void:
	var p := Wire.make_sparks(color, amount, 0.45)
	p.one_shot = true
	p.explosiveness = 1.0
	p.z_index = 10      # sparks fly over the player too
	_add_fx(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)   # delete it after 1 s


func _is_door() -> bool:
	return kind == Kind.DOOR or kind == Kind.GANGWAY


## Door bar flickers out, leaving the open door frame. Its light goes red -> green.
## A gangway instead slides its catwalk out across the gap.
## A barrier shudders, then sinks into the floor. `delay` lets a row of barriers
## go one after another, like a wave.
func open_door(delay := 0.0) -> void:
	if is_open:
		return
	is_open = true
	if kind == Kind.BARRIER:
		_sink(delay)
		return
	if _light:
		_light.color = GLOW[Kind.DOOR]
	if kind == Kind.GANGWAY:
		_sprite.region_rect = Rect2(Kind.GANGWAY_OPEN * 32, 0, 32, 32)
		_sprite.light_mask = 1          # a real catwalk: lit like the hull around it
		_sprite.scale = Vector2(1.0, 0.05)
		var tw := create_tween()
		tw.tween_property(_sprite, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_callback(_finish_open)
		return
	var tw := create_tween()
	for i in 5:
		tw.tween_property(_sprite, "modulate", Color(2.0, 2.0, 2.0), 0.05)
		tw.tween_property(_sprite, "modulate", Color(1, 1, 1, 0.3), 0.05)
	tw.tween_callback(_finish_open)


func _finish_open() -> void:
	_sprite.modulate = Color.WHITE
	var open_frame := Kind.GANGWAY_OPEN if kind == Kind.GANGWAY else DOOR_OPEN_FRAME
	_sprite.region_rect = Rect2(open_frame * 32, 0, 32, 32)
	if _glow:
		_glow.region_rect = _sprite.region_rect
		_glow.modulate.a = 0.0
	burst(Color(0.4, 1.0, 0.55), 22)


## Barrier: a quick shudder, then the crate stack slides down into the floor.
## (Shrinking the height while moving down by the same amount keeps the bottom
## edge still, so it looks like it drops through a slot in the floor.)
func _sink(delay: float) -> void:
	var tw := create_tween()
	tw.tween_interval(delay)
	for i in 3:
		tw.tween_property(_sprite, "position:x", 1.0, 0.03)
		tw.tween_property(_sprite, "position:x", -1.0, 0.03)
	tw.tween_property(_sprite, "position:x", 0.0, 0.02)
	tw.tween_callback(burst.bind(Color(0.8, 0.75, 0.65), 10))         # dust
	tw.set_parallel(true)
	tw.tween_property(_sprite, "scale:y", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_sprite, "position:y", 16.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _glow:
		tw.tween_property(_glow, "modulate:a", 0.0, 0.2)
	if _light:
		tw.tween_property(_light, "energy", 0.0, 0.35)
	tw.set_parallel(false)
	tw.tween_callback(_set_shown.bind(false))


func _set_shown(on: bool) -> void:
	_sprite.visible = on
	if _glow:
		_glow.visible = on
	if _light:
		_light.visible = on


## The opposite of open_door: the bar flickers back on (used by the airlock's inner door).
## A barrier rises back up out of the floor.
func close_door() -> void:
	if not is_open:
		return
	is_open = false
	if kind == Kind.BARRIER:
		_set_shown(true)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_sprite, "scale:y", 1.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_sprite, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return
	_sprite.region_rect = Rect2(kind * 32, 0, 32, 32)
	if _glow:
		_glow.region_rect = _sprite.region_rect
	if _light:
		_light.color = DOOR_LOCKED
	var tw := create_tween()
	for i in 4:
		tw.tween_property(_sprite, "modulate", Color(1, 1, 1, 0.3), 0.05)
		tw.tween_property(_sprite, "modulate", Color(2.0, 2.0, 2.0), 0.05)
	tw.tween_property(_sprite, "modulate", Color.WHITE, 0.05)
	burst(DOOR_LOCKED, 14)
