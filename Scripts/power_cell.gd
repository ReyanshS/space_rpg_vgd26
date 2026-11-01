# ---------------------------------------------------------------------------
# power_cell.gd  -  a collectible POWER CELL (a small floating battery).
#
# Cells are painted on the Layout layer like any tile (kind "cell"). They start
# EMPTY: walking over one does nothing. You charge one by touching it while you
# carry the LIVE WIRE - so collecting cells means finding a route that passes
# them and still reaches the next pad before the timer runs out. Like the stars
# in a phone puzzle game: optional, but they reward a clever route.
#
# If you fail the room, the cells you charged on that try come back (uncharged).
# You only KEEP them once the room is powered. The level does all the counting;
# this script only draws the cell and plays its animations.
# ---------------------------------------------------------------------------
class_name PowerCell
extends Node2D

var charged := false
var _t := 0.0
var _float_text := 0.0      # > 0 while the "+1" floats up
var _light: PointLight2D


func _ready() -> void:
	LightFX.glow(self)         # the cell shines in the dark ship
	z_index = 3                # above the pads, still under the player
	_t = randf() * TAU
	_light = LightFX.make(Color(0.5, 0.85, 1.0), 34.0, 0.45)   # a little light on the floor
	add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	if _float_text > 0.0:
		_float_text -= delta
	if not charged or _float_text > 0.0:
		queue_redraw()


func _draw() -> void:
	if not charged:
		var bob := roundf(sin(_t * 3.0) * 1.5)
		var o := Vector2(-4, -8 + bob)
		var pulse := 0.18 + 0.1 * sin(_t * 4.0)
		draw_circle(Vector2(0, bob - 2), 10.0, Color(0.5, 0.85, 1.0, pulse))           # soft halo
		draw_rect(Rect2(o + Vector2(2, -2), Vector2(4, 2)), Color(0.85, 0.88, 0.95))   # the + cap
		draw_rect(Rect2(o, Vector2(8, 13)), Color(0.06, 0.08, 0.14))                    # outline
		draw_rect(Rect2(o + Vector2(1, 1), Vector2(6, 11)), Color(0.4, 0.46, 0.56))    # empty body
		draw_rect(Rect2(o + Vector2(1, 1), Vector2(1, 11)), Color(0.55, 0.62, 0.72))   # shine
		# one flickering bar of charge at the bottom = "almost empty, needs power"
		draw_rect(Rect2(o + Vector2(2, 9), Vector2(4, 2)), Color(0.5, 0.9, 1.0, 0.55 + 0.45 * sin(_t * 6.0)))
	if _float_text > 0.0:
		var a := clampf(_float_text / 0.3, 0.0, 1.0)
		var y := -14.0 - (0.9 - _float_text) * 26.0
		# the project's pixel font (Project Settings > GUI > Theme > Custom)
		var theme := ThemeDB.get_project_theme()
		var font: Font = theme.default_font if theme and theme.default_font else ThemeDB.fallback_font
		draw_string(font, Vector2(-7, y), "+1", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.9, 0.3, a))


## Charged by the live wire: burst of sparks, "+1" floats up, the cell disappears.
func collect() -> void:
	charged = true
	_float_text = 0.9
	var p := Wire.make_sparks(Color(1.0, 0.9, 0.35), 18, 0.5)
	p.one_shot = true
	p.explosiveness = 1.0
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)
	create_tween().tween_property(_light, "energy", 0.0, 0.3)


## You failed the room: the cell comes back, empty.
func restore() -> void:
	charged = false
	_float_text = 0.0
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.4)
	_light.energy = 0.45
	queue_redraw()
