# ---------------------------------------------------------------------------
# wire.gd  -  draws a cable: either the live wire you carry (CABLE) or the
# floor cable that runs from a goal to its door (CONDUIT).
#
# A wire is a list of points ("anchors": the pads it is wrapped around) plus,
# while you carry it, a "live end" that follows your hands. It is drawn with
# two Line2D nodes: a thick dark one underneath (the outline) and a thinner
# coloured one on top (the core). The core uses a small SHADER
# (Shaders/wire_current.gdshader) that makes bright pulses run along it.
# Every line and spark is on the GLOW light channel (LightFX.glow), so wires
# stay bright even though the ship is dark.
# ---------------------------------------------------------------------------
class_name Wire
extends Node2D

enum Style { CABLE, CONDUIT }

const SHADER_PATH := "res://Shaders/wire_current.gdshader"
const CABLE_COLOR := Color(1.0, 0.82, 0.25)
const CABLE_HOT := Color(1.0, 0.35, 0.12)
const CONDUIT_OFF := Color(0.17, 0.21, 0.29)
const CONDUIT_ON := Color(0.25, 0.85, 1.0)
const FLOW_COLOR := Color(0.85, 1.0, 1.0)

static var _white_tex: ImageTexture
static var _spark_tex: ImageTexture

var style: Style = Style.CABLE
var anchors := PackedVector2Array()
var live_end := Vector2.ZERO
var live := false
var powered := false

var _outline: Line2D
var _core: Line2D
var _flow: Line2D
var _mat: ShaderMaterial
var _sparks: CPUParticles2D
var _width := 3.0
var _base_color := CABLE_COLOR


# _init runs when you write Wire.new(...). Its arguments come from new().
func _init(p_style: Style = Style.CABLE) -> void:
	style = p_style
	_width = 3.0 if style == Style.CABLE else 2.0
	_outline = _make_line(_width + 2.0, Color(0.07, 0.05, 0.02) if style == Style.CABLE else Color(0.06, 0.07, 0.1))
	_core = _make_line(_width, Color.WHITE)
	_flow = _make_line(_width + 2.0, FLOW_COLOR)
	_flow.visible = false
	add_child(_outline)
	add_child(_core)
	add_child(_flow)
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	_core.material = _mat
	# The shader needs UV coordinates that grow along the line; Line2D only
	# makes those when it has a texture in TILE mode, so we give it a tiny white one.
	_core.texture = white_texture()
	_core.texture_mode = Line2D.LINE_TEXTURE_TILE
	_core.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_mat.set_shader_parameter("line_width", _width)
	if style == Style.CABLE:
		_set_look(CABLE_COLOR, Color(1.0, 1.0, 0.85), 3.0, 0.9)
	else:
		_set_look(CONDUIT_OFF, CONDUIT_OFF, 0.0, 0.0)
	_sparks = make_sparks(Color(1.0, 0.9, 0.4), 8, 0.35)
	_sparks.emitting = false
	add_child(_sparks)


static func white_texture() -> ImageTexture:
	if _white_tex == null:
		var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex


static func spark_texture() -> ImageTexture:
	if _spark_tex == null:
		var img := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_spark_tex = ImageTexture.create_from_image(img)
	return _spark_tex


## Small square spark particles, used by wires and tiles.
## A "static func" can be called without a Wire: Wire.make_sparks(...).
static func make_sparks(color: Color, amount: int, lifetime: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = spark_texture()
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 160)
	p.initial_velocity_min = 25.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = color
	var ramp := Gradient.new()          # fade each spark out over its life
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	LightFX.glow(p)                     # sparks shine in the dark
	return p


func _make_line(width: float, color: Color) -> Line2D:
	var l := Line2D.new()
	l.width = width
	l.default_color = color
	l.joint_mode = Line2D.LINE_JOINT_SHARP
	l.begin_cap_mode = Line2D.LINE_CAP_NONE
	l.end_cap_mode = Line2D.LINE_CAP_NONE
	l.antialiased = false
	LightFX.glow(l)                     # wires shine in the dark
	return l


func _set_look(base: Color, pulse: Color, speed: float, intensity: float) -> void:
	_base_color = base
	_mat.set_shader_parameter("base_color", base)
	_mat.set_shader_parameter("pulse_color", pulse)
	_mat.set_shader_parameter("speed", speed)
	_mat.set_shader_parameter("intensity", intensity)


# ------------------------------------------------------------------ building the line

func begin(p: Vector2) -> void:
	anchors = PackedVector2Array([p])
	live = true
	live_end = p
	_sparks.emitting = true
	_refresh()


func add_anchor(p: Vector2) -> void:
	anchors.append(p)
	_refresh()


func set_live_end(p: Vector2) -> void:
	live_end = p
	_sparks.position = p
	_refresh()


## The wire stops following the player (it ends at the last anchor).
func finish() -> void:
	live = false
	_sparks.emitting = false
	_refresh()


func set_points(pts: PackedVector2Array) -> void:
	anchors = pts
	live = false
	_refresh()


func get_points() -> PackedVector2Array:
	var pts := anchors.duplicate()
	if live:
		pts.append(live_end)
	return pts


func _refresh() -> void:
	var pts := get_points()
	_outline.points = pts
	_core.points = pts


## 0 = plenty of time, 1 = out of time. The cable heats up and flickers.
func set_urgency(u: float) -> void:
	if style != Style.CABLE or powered:
		return
	_base_color = CABLE_COLOR.lerp(CABLE_HOT, clampf((u - 0.4) / 0.6, 0.0, 1.0))
	_mat.set_shader_parameter("base_color", _base_color)
	_mat.set_shader_parameter("flicker", clampf((u - 0.7) / 0.3, 0.0, 1.0))
	_mat.set_shader_parameter("speed", 3.0 + u * 5.0)


## The wire is pulled tight against something: flash red and spark where it catches.
func strain(at: Vector2) -> void:
	var burst := make_sparks(Color(1.0, 0.4, 0.3), 8, 0.3)
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.position = at
	add_child(burst)
	burst.emitting = true
	get_tree().create_timer(0.8).timeout.connect(burst.queue_free)
	_outline.default_color = Color(0.8, 0.15, 0.1)
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(func() -> void: _outline.default_color = Color(0.07, 0.05, 0.02))


# ------------------------------------------------------------------ animations

## Bright energy races from the first point to the last.
func power_flow(duration: float) -> void:
	_flow.visible = true
	_flow.modulate.a = 1.0
	_sparks.emitting = true
	var tw := create_tween()
	tw.tween_method(_set_flow_progress, 0.0, 1.0, duration)
	await tw.finished
	_sparks.emitting = false
	set_powered()
	var fade := create_tween()
	fade.tween_property(_flow, "modulate:a", 0.0, 0.35)
	fade.tween_callback(func() -> void: _flow.visible = false)


func set_powered() -> void:
	powered = true
	_mat.set_shader_parameter("flicker", 0.0)
	if style == Style.CABLE:
		_set_look(Color(1.0, 0.9, 0.45), Color(1, 1, 1), 4.0, 1.0)
	else:
		_set_look(CONDUIT_ON, Color(0.9, 1.0, 1.0), 4.0, 1.0)


## Draws the bright "flow" line only part of the way: t=0 nothing, t=1 everything.
func _set_flow_progress(t: float) -> void:
	var pts := get_points()
	if pts.size() < 2:
		return
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	var want := total * t
	var out := PackedVector2Array([pts[0]])
	var acc := 0.0
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if acc + seg >= want:
			var head := pts[i - 1].lerp(pts[i], (want - acc) / maxf(seg, 0.001))
			out.append(head)
			_sparks.position = head
			break
		out.append(pts[i])
		acc += seg
	_flow.points = out


## The wire overloads: flickers red, then fades away.
func snap() -> void:
	_sparks.emitting = false
	var burst := make_sparks(Color(1.0, 0.55, 0.2), 18, 0.5)
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.position = live_end if live else (anchors[anchors.size() - 1] if anchors.size() > 0 else Vector2.ZERO)
	add_child(burst)
	burst.emitting = true
	live = false
	_refresh()
	_mat.set_shader_parameter("base_color", Color(1.0, 0.3, 0.15))
	var tw := create_tween()
	for i in 4:
		tw.tween_property(self, "modulate:a", 0.2, 0.06)
		tw.tween_property(self, "modulate:a", 1.0, 0.06)
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	await tw.finished
