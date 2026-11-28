# ---------------------------------------------------------------------------
# wire.gd: draws a cable. Either the live wire you carry (Style.CABLE) or the
# floor cable that runs from a goal to its door (Style.CONDUIT).
#
# A wire is a list of points ("anchors": the pads it is wrapped around) plus,
# while you carry it, a "live end" that follows your hands. It is drawn with
# two Line2D nodes: a thick dark one underneath (the outline) and a thinner
# coloured one on top (the core). The core uses a small shader
# (Shaders/wire_current.gdshader) that makes bright pulses run along it.
# Every line and spark is on the glow light channel (LightFX.glow), so wires
# stay bright even though the ship is dark.
#
# Poles: the rules treat a pole as a corner at its centre (level.gd, and the
# solver). Drawn like that, the wire looked like it snapped to the middle of
# the pillar. So when the wire goes round a pole it's DRAWN like a rope round a
# post: straight to where it just touches the pillar's base, round the outside
# of the base, and off again on the far side (_display_points). The base is an
# ellipse (the game is seen from above at a slant). The front half of each loop
# is drawn again on top of the pillar (_fronts), the back half stays behind it.
# Walk round a pole more than once and the wire coils round it: every extra full
# turn is one more loop, a little wider than the last (COIL_GAP), so you can
# count them. Nothing is ever cut off or simplified.
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
## For each anchor: Vector4(side, radius x, radius y, turn) if the wire wraps
## round a post there (side = which way it turns: +1 / -1; turn = how far round
## it has gone so far, in radians, from level.gd), or Vector4.ZERO for a pad.
var wraps: Array[Vector4] = []
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
var _fronts: Array = []        # [outline, core] Line2D pairs: the front of each loop round a post
## Every post in the room (level.gd fills it): Vector4(centre x, centre y, radius x,
## radius y). A straight stretch of wire that would cut through one of their
## bases is drawn bending round its edge instead (_around_posts): the wire only
## wraps for the rules once it crosses the centre, but it never looks like it
## goes through the post on the way.
var posts: Array[Vector4] = []
const ARC_STEP := PI / 10.0    # how finely a loop is drawn (radians per point)
const COIL_GAP := 2.5          # each extra full turn round a post sits this many px further out


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
	# makes those when it has a texture in tile mode, so we give it a tiny white one.
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
	wraps = [Vector4.ZERO]
	live = true
	live_end = p
	_sparks.emitting = true
	_refresh()


## `wrap`: Vector4(side, radius x, radius y, turn) when the wire goes round a
## post here (a pole or the clamp), drawn as a loop round its base; zero for a pad.
func add_anchor(p: Vector2, wrap := Vector4.ZERO) -> void:
	anchors.append(p)
	wraps.append(wrap)
	_refresh()


## The wire came off a pole again (level.gd _update_wraps): drop its last corner.
func remove_last_anchor() -> void:
	if anchors.size() > 1:
		anchors.remove_at(anchors.size() - 1)
		wraps.remove_at(wraps.size() - 1)
		_refresh()


## How far the wire has turned round the post at anchor i (level.gd keeps count).
func set_turn(i: int, turn: float) -> void:
	if i >= 0 and i < wraps.size() and wraps[i] != Vector4.ZERO:
		wraps[i].w = turn
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
	wraps.clear()
	for i in pts.size():
		wraps.append(Vector4.ZERO)
	live = false
	_refresh()


func get_points() -> PackedVector2Array:
	var pts := anchors.duplicate()
	if live:
		pts.append(live_end)
	return pts


func _refresh() -> void:
	var fronts: Array = []
	var pts := _display_points(fronts)
	_outline.points = pts
	_core.points = pts
	# the front half of each loop, drawn again over the pillar
	while _fronts.size() < fronts.size():
		var o := _make_line(_width + 2.0, _outline.default_color)
		var c := _make_line(_width, Color.WHITE)
		c.material = _mat
		c.texture = white_texture()
		c.texture_mode = Line2D.LINE_TEXTURE_TILE
		c.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		for l in [o, c]:
			l.z_index = 4        # wires are at -5: this is -1, the pillar's own depth (drawn after it)
			add_child(l)
		_fronts.append([o, c])
	for i in _fronts.size():
		var seg: PackedVector2Array = fronts[i] if i < fronts.size() else PackedVector2Array()
		_fronts[i][0].points = seg
		_fronts[i][1].points = seg
		_fronts[i][0].default_color = _outline.default_color


## The points the wire is drawn through: the anchors and the live end, with a
## loop round every post it's wrapped round. `fronts` gets the front part of
## each loop (the side facing the camera), to be drawn again over the post.
func _display_points(fronts: Array) -> PackedVector2Array:
	var pts := get_points()
	if pts.size() < 3:
		return _around_posts(pts, fronts)       # no corners yet: still bend round posts
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var w: Vector4 = wraps[i] if i < wraps.size() else Vector4.ZERO
		if w == Vector4.ZERO:
			out.append(pts[i])
			continue
		var loop := _loop(out[out.size() - 1], pts[i], pts[i + 1], w)
		out.append_array(loop)
		# the front of the loop: every stretch below the post's centre (nearer the
		# camera); a coiled wire has one per turn
		var front := PackedVector2Array()
		for q in loop:
			if q.y >= pts[i].y - 0.5:
				front.append(q)
			else:
				if front.size() >= 2:
					fronts.append(front)
				front = PackedVector2Array()
		if front.size() >= 2:
			fronts.append(front)
	out.append(pts[pts.size() - 1])
	return _around_posts(out, fronts)


## Bends every straight stretch of `path` that would cut through a post's base
## round the edge it's touching (the side its middle passes on). Bends below a
## post's centre go into `fronts` too (drawn over the pillar).
func _around_posts(path: PackedVector2Array, fronts: Array) -> PackedVector2Array:
	if posts.is_empty() or path.size() < 2:
		return path
	var out := PackedVector2Array([path[0]])
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		for post in posts:
			var bend := _bend_round(a, b, post)
			if bend.is_empty():
				continue
			out.append_array(bend)
			var front := PackedVector2Array()       # the part in front of the post's centre
			for q in bend:
				if q.y >= post.y - 0.5:
					front.append(q)
			if front.size() >= 2:
				fronts.append(front)
			break
		out.append(b)
	return out


## If the straight wire a -> b cuts through the base of `post`, the points of
## the wire going round its edge instead (tangent in, arc, tangent out);
## otherwise nothing. Done in "circle space" (the base squashed to a circle).
func _bend_round(a: Vector2, b: Vector2, post: Vector4) -> PackedVector2Array:
	var c := Vector2(post.x, post.y)
	var r := post.z
	var k := post.z / maxf(post.w, 0.01)
	var a2 := Vector2(a.x, c.y + (a.y - c.y) * k)
	var b2 := Vector2(b.x, c.y + (b.y - c.y) * k)
	var ab := b2 - a2
	var len2 := ab.length_squared()
	if len2 < 1.0 or a2.distance_to(c) <= r + 0.5 or b2.distance_to(c) <= r + 0.5:
		return PackedVector2Array()
	var t := clampf((c - a2).dot(ab) / len2, 0.0, 1.0)
	var near := a2 + ab * t                   # the point of the wire closest to the post
	if t <= 0.0 or t >= 1.0 or near.distance_to(c) >= r - 0.5:
		return PackedVector2Array()           # it doesn't cut through the base
	# go round the edge on the side the wire passes (where its closest point is):
	# try both ways round and keep the short one that goes past that side
	var toward := (near - c).normalized() if near.distance_to(c) > 0.01 else ab.orthogonal().normalized()
	var dir := 0.0
	var t1 := 0.0
	var arc := 0.0
	for d in [1.0, -1.0]:
		var s1: float = (a2 - c).angle() + d * acos(clampf(r / a2.distance_to(c), -1.0, 1.0))
		var s2: float = (b2 - c).angle() - d * acos(clampf(r / b2.distance_to(c), -1.0, 1.0))
		var arc_d := fposmod(d * (s2 - s1), TAU)
		if arc_d <= PI and Vector2.from_angle(s1 + d * arc_d * 0.5).dot(toward) >= 0.0:
			dir = d
			t1 = s1
			arc = arc_d
			break
	if dir == 0.0:
		return PackedVector2Array()
	var steps := maxi(2, ceili(arc / ARC_STEP))
	var bend := PackedVector2Array()
	for s in steps + 1:
		var q := c + Vector2.from_angle(t1 + dir * arc * s / steps) * r
		bend.append(Vector2(q.x, c.y + (q.y - c.y) / k))
	return bend


## The wire coming from `a`, going round the post at `c`, leaving towards `b`.
## The post's base is an ellipse (radii w.y across, w.z deep). Squashing the
## picture by w.y / w.z makes it a circle, where tangents are easy: from a
## point at distance d from a circle of radius r, the tangent touches it at
## an angle acos(r / d) either side of the line to the centre.
## w.w = how far round the wire has gone in all: each full turn beyond the
## first loop adds a coil, a spiral getting COIL_GAP wider per turn.
func _loop(a: Vector2, c: Vector2, b: Vector2, w: Vector4) -> PackedVector2Array:
	var r := w.y
	var k := w.y / maxf(w.z, 0.01)
	var to_circle := func(p: Vector2) -> Vector2: return Vector2(p.x, c.y + (p.y - c.y) * k)
	var from_circle := func(p: Vector2) -> Vector2: return Vector2(p.x, c.y + (p.y - c.y) / k)
	var a2: Vector2 = to_circle.call(a)
	var b2: Vector2 = to_circle.call(b)
	if a2.distance_to(c) <= r + 0.5 or b2.distance_to(c) <= r + 0.5:
		return PackedVector2Array([c])          # too close to wrap round: just the corner
	# Which way round the post the wire goes: the way it turns (level.gd counts
	# the turn: w.w, with its sign; w.x is the side it first swung). Going that
	# way round, the wire arrives where a line from `a` just grazes the post and
	# leaves where a line to `b` just grazes it. In angles round the centre:
	#   arrives at  (direction of a) + dir * acos(r / distance to a)
	#   leaves at   (direction of b) - dir * acos(r / distance to b)
	# This works however far round it has gone (it used to pick "the outside of
	# the bend", which picks the wrong side once you're more than half way round).
	var dir := signf(w.w) if w.w != 0.0 else w.x
	if dir == 0.0:
		dir = 1.0
	var t1 := (a2 - c).angle() + dir * acos(clampf(r / a2.distance_to(c), -1.0, 1.0))
	var turn := absf(w.w)
	# how far round between arriving and leaving (first without the extra coils)
	var t2 := (b2 - c).angle() - dir * acos(clampf(r / b2.distance_to(c), -1.0, 1.0))
	var arc := fposmod(dir * (t2 - t1), TAU)
	if arc - turn > PI:
		arc = 0.0                               # only just touching: no loop at all (not a full one)
	var coils := maxi(0, roundi((turn - arc) / TAU))
	if coils > 0:
		# every full turn adds a coil, each a little wider: it leaves from the outermost
		var r_end := r + COIL_GAP * coils
		if b2.distance_to(c) > r_end + 0.5:
			t2 = (b2 - c).angle() - dir * acos(clampf(r_end / b2.distance_to(c), -1.0, 1.0))
			arc = fposmod(dir * (t2 - t1), TAU)
			if arc - (turn - TAU * coils) > PI:
				arc = 0.0
	var delta := dir * (arc + TAU * coils)
	var steps := maxi(2, ceili(absf(delta) / ARC_STEP))
	var out := PackedVector2Array()
	for s in steps + 1:
		var u := float(s) / steps
		var radius := r + COIL_GAP * coils * u            # a spiral: each turn a little wider
		var q := c + Vector2.from_angle(t1 + delta * u) * radius
		out.append(from_circle.call(q))
	return out


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
	tw.tween_callback(func() -> void:
		_outline.default_color = Color(0.07, 0.05, 0.02)
		_refresh())


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


## The power was cut (level.gd _cut_room): the floor conduit goes dark again.
func set_unpowered() -> void:
	powered = false
	if style == Style.CONDUIT:
		_set_look(CONDUIT_OFF, CONDUIT_OFF, 0.0, 0.0)


func set_powered() -> void:
	powered = true
	_mat.set_shader_parameter("flicker", 0.0)
	if style == Style.CABLE:
		_set_look(Color(1.0, 0.9, 0.45), Color(1, 1, 1), 4.0, 1.0)
	else:
		_set_look(CONDUIT_ON, Color(0.9, 1.0, 1.0), 4.0, 1.0)


## Draws the bright "flow" line only part of the way: t=0 nothing, t=1 everything.
func _set_flow_progress(t: float) -> void:
	var pts := _display_points([])
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
