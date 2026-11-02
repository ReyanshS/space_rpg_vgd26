# ---------------------------------------------------------------------------
# puzzle_tile.gd  -  one interactive floor tile: start, goal, node, bend,
# red discharge, or door.
#
# The level creates these in code (PuzzleTile.new() + setup()). Each one has:
#   - a Sprite2D showing the right 32x32 picture (gets darker when the ship is dark)
#   - a "glow" copy drawn with ADD blending (colours add up = brighter). It's on
#     the GLOW light channel (LightFX.glow), so the darkness doesn't dim it and
#     the pad looks like it shines. Sparks and arrows are on that channel too.
#   - a small PointLight2D that lights up the floor around it.
# The tile doesn't know any game rules - the level just calls hit(),
# set_powered(), open_door() etc. and the tile plays the matching animation.
# ---------------------------------------------------------------------------
class_name PuzzleTile
extends Node2D

# An enum is a list of named numbers: Kind.START == 0, Kind.GOAL == 1, ...
# The order matches the pictures in puzzle_tiles.png from left to right.
enum Kind { START, GOAL, NODE, BEND, DISCHARGE, DISCHARGE_OFF, CRATE, DOOR }

const SHEET_PATH := "res://Assets/images/tiles/puzzle_tiles.png"
const DOOR_OPEN_FRAME := 8
const GLOW := {
	Kind.START: Color(1.0, 0.85, 0.3),
	Kind.GOAL: Color(0.35, 0.65, 1.0),
	Kind.NODE: Color(1.0, 0.55, 0.2),
	Kind.BEND: Color(0.75, 0.45, 1.0),
	Kind.DISCHARGE: Color(1.0, 0.25, 0.25),
	Kind.DOOR: Color(0.4, 1.0, 0.55),
}
const DOOR_LOCKED := Color(1.0, 0.3, 0.25)

# "static" = shared by ALL tiles, so the picture is only loaded once.
static var _sheet: Texture2D
static var _add_mat: CanvasItemMaterial

var kind: int = Kind.START
var powered := false          # room solved: shine brightly
var active := false           # this node is the one you're standing on (timer paused)
var is_open := false          # doors only
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
var _preview_node: Node2D
var _preview_on := false
var _preview_side := Vector2.ZERO
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
	if GLOW.has(kind):
		var col: Color = DOOR_LOCKED if kind == Kind.DOOR else GLOW[kind]   # locked doors glow red
		_glow = _make_sprite(kind)
		_glow.material = _add_mat
		_glow.modulate = Color(col, 0.0)
		_add_fx(_glow)
		# a small light so the floor around the pad is lit too
		if kind != Kind.DISCHARGE:
			_light = LightFX.make(col, 44.0, 0.55)
			add_child(_light)
	if rotated:
		_sprite.rotation = PI / 2.0
		if _glow:
			_glow.rotation = PI / 2.0
	if kind == Kind.DISCHARGE:
		_crackle = Wire.make_sparks(Color(1.0, 0.45, 0.4), 4, 0.3)
		_crackle.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		_crackle.emission_rect_extents = Vector2(11, 11)
		_crackle.initial_velocity_min = 10.0
		_crackle.initial_velocity_max = 35.0
		_crackle.gravity = Vector2.ZERO
		_crackle.randomness = 1.0
		_add_fx(_crackle)
		_crackle.emitting = true
	if kind == Kind.START:
		_prompt_node = _make_overlay(_draw_prompt)
	if kind == Kind.BEND:
		_preview_node = _make_overlay(_draw_preview)
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
			Kind.START, Kind.GOAL, Kind.NODE, Kind.BEND:
				a = 0.18 + 0.12 * sin(_t * 3.0)     # slow gentle pulse
			Kind.DISCHARGE:
				a = 0.3 + 0.2 * sin(_t * 9.0)
			Kind.DOOR:
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
	if kind == Kind.DISCHARGE:
		_flick -= delta
		if _flick <= 0.0:
			_flick = randf_range(0.04, 0.35)
			_sprite.modulate = Color(1.5, 1.4, 1.4) if randf() < 0.3 else Color.WHITE
	if prompt and _prompt_node:
		_prompt_node.queue_redraw()
	if _preview_on and _preview_node:
		_preview_node.queue_redraw()     # keep the bend arrows pulsing


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


## BEND pads: while you're stopped on one, show its two ways out as arrows.
## `side` is one way; the other way is the exact opposite (-side).
func show_choice(on: bool, side: Vector2) -> void:
	_preview_on = on
	_preview_side = side
	if _preview_node:
		_preview_node.queue_redraw()


func _draw_preview() -> void:
	if not _preview_on:
		return
	var pulse := 0.6 + 0.4 * sin(_t * 10.0)
	var col := Color(0.92, 0.7, 1.0, pulse)
	var outline := Color(0.15, 0.05, 0.25, pulse)
	for dir in [_preview_side, -_preview_side]:
		var tip: Vector2 = dir * (32.0 + 2.0 * sin(_t * 10.0))
		var base: Vector2 = dir * 22.0
		var side: Vector2 = Vector2(-dir.y, dir.x) * 6.0
		var tri := PackedVector2Array([tip, base + side, base - side])
		_preview_node.draw_colored_polygon(tri, col)
		_preview_node.draw_polyline(PackedVector2Array([tip, base + side, base - side, tip]), outline, 1.0)


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


## Door bar flickers out, leaving the open door frame. Its light goes red -> green.
func open_door() -> void:
	if is_open:
		return
	is_open = true
	if _light:
		_light.color = GLOW[Kind.DOOR]
	var tw := create_tween()
	for i in 5:
		tw.tween_property(_sprite, "modulate", Color(2.0, 2.0, 2.0), 0.05)
		tw.tween_property(_sprite, "modulate", Color(1, 1, 1, 0.3), 0.05)
	tw.tween_callback(_finish_open)


func _finish_open() -> void:
	_sprite.modulate = Color.WHITE
	_sprite.region_rect = Rect2(DOOR_OPEN_FRAME * 32, 0, 32, 32)
	if _glow:
		_glow.region_rect = _sprite.region_rect
		_glow.modulate.a = 0.0
	burst(Color(0.4, 1.0, 0.55), 22)
