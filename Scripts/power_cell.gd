# ---------------------------------------------------------------------------
# power_cell.gd: a power cell, a spare battery lying around the ship (a small
# floating battery with a lightning bolt, the same picture as the cell counter).
#
# Cells are painted on the Layout layer like any tile (kind "cell"). Walking
# over one does nothing. Touch one while you carry the live wire and its charge
# jumps into the wire: your timer gets cell_bonus more seconds (level.gd).
# So a cell is a choice in the middle of a puzzle: is it worth the detour?
# Every cell you keep also counts for a star, and your suit stores the extra
# power as oxygen for spacewalks later (Game.o2_bonus()).
#
# If you fail, the cells you used on that try come back. You only keep them once
# you reach the goal. The level does all the counting; this script only draws
# the cell and plays its animations.
# ---------------------------------------------------------------------------
class_name PowerCell
extends Node2D

var collected := false
var _t := 0.0
var _float_text := 0.0      # > 0 while the "+2s" floats up
var _label := "+1"
var _light: PointLight2D


func _ready() -> void:
	LightFX.glow(self)         # the cell shines in the dark ship
	z_index = 3                # above the pads, still under the player
	_t = randf() * TAU
	_light = LightFX.make(Color(1.0, 0.8, 0.35), 34.0, 0.5)   # a warm glow on the floor
	add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	if _float_text > 0.0:
		# (stops at exactly 0, and the redraw at 0 wipes the last faint label)
		_float_text = maxf(0.0, _float_text - delta)
		queue_redraw()
	elif not collected:
		queue_redraw()


## The battery picture: 10 x 15 pixels, top-left corner at `o`. A static func,
## so the HUD's cell counter can draw the very same picture:
##     PowerCell.draw_battery(some_control, Vector2(4, 1), body_colour, bolt_colour)
static func draw_battery(ci: CanvasItem, o: Vector2, body: Color, bolt: Color) -> void:
	ci.draw_rect(Rect2(o + Vector2(3, 0), Vector2(4, 2)), Color(0.85, 0.88, 0.95))   # the + terminal
	ci.draw_rect(Rect2(o + Vector2(0, 2), Vector2(10, 13)), Color(0.06, 0.08, 0.14)) # outline
	ci.draw_rect(Rect2(o + Vector2(1, 3), Vector2(8, 11)), body)                     # body
	ci.draw_rect(Rect2(o + Vector2(1, 3), Vector2(1, 11)), body.lightened(0.3))      # shine
	# a lightning bolt, one row of pixels at a time: [x, width] for each row
	var rows := [[2, 3], [1, 3], [0, 3], [0, 5], [2, 2], [1, 2], [1, 1], [0, 1]]
	for y in rows.size():
		ci.draw_rect(Rect2(o + Vector2(3 + rows[y][0], 5 + y), Vector2(rows[y][1], 1)), bolt)


func _draw() -> void:
	if not collected:
		var bob := roundf(sin(_t * 3.0) * 1.5)
		var pulse := 0.2 + 0.1 * sin(_t * 4.0)
		draw_circle(Vector2(0, bob - 1), 11.0, Color(1.0, 0.8, 0.35, pulse))   # warm halo
		# full: an amber battery whose bolt glows white-hot now and then
		var bolt := Color(1.0, 0.95, 0.75).lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 5.0))
		draw_battery(self, Vector2(-5, -9 + bob), Color(0.95, 0.62, 0.15), bolt)
	if _float_text > 0.0:
		var a := clampf(_float_text / 0.3, 0.0, 1.0)
		var y := -14.0 - (0.9 - _float_text) * 26.0
		# the project's pixel font (Project Settings > GUI > Theme > Custom)
		var theme := ThemeDB.get_project_theme()
		var font: Font = theme.default_font if theme and theme.default_font else ThemeDB.fallback_font
		draw_string(font, Vector2(-9, y), _label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.9, 0.3, a))


## Plugged into the live wire: burst of sparks, the label (e.g. "+2s") floats
## up, the cell disappears.
func collect(label := "+1") -> void:
	collected = true
	_label = label
	_float_text = 0.9
	var p := Wire.make_sparks(Color(1.0, 0.9, 0.35), 18, 0.5)
	p.one_shot = true
	p.explosiveness = 1.0
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)
	create_tween().tween_property(_light, "energy", 0.0, 0.3)


## You failed: the cell comes back, full again.
func restore() -> void:
	collected = false
	_float_text = 0.0
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.4)
	_light.energy = 0.5
	queue_redraw()
