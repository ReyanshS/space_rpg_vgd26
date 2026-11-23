# ---------------------------------------------------------------------------
# pickup.gd: something lying on the floor that you pick up by walking over it,
# or the cable clamp standing in a socket.
#   "fuse"   a glass fuse with a glowing wire. Fuse doors take one each.
#   "clamp"  the cable clamp (the level's tool). Lying on the floor it's a
#            pickup; `standing` = it's been set down in a socket, where it
#            stands upright and the wire wraps round it like a pillar.
# The level (level.gd, _check_dungeon / _try_clamp) decides when you get it; this
# script only draws it and plays its little pick up animation (collect()).
# ---------------------------------------------------------------------------
class_name Pickup
extends Node2D

const OUTLINE := Color(0.02, 0.035, 0.13)
const AMBER := Color(1.0, 0.75, 0.28)
const PURPLE := Color(0.75, 0.47, 1.0)
const STEEL := Color(0.77, 0.8, 0.86)

var kind := "fuse"
var standing := false
var _t := 0.0
var _gone := false


func _ready() -> void:
	z_index = 6                   # relative to the tile layer: just under the player
	LightFX.glow(self)            # it shines in the dark so you can spot it
	_t = randf() * TAU
	var light := LightFX.make(AMBER if kind == "fuse" else PURPLE, 40.0, 0.6)
	add_child(light)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if _gone:
		return
	if kind == "clamp" and standing:
		_draw_clamp_post()
		return
	var bob := roundf(sin(_t * 3.0) * 1.5)
	draw_rect(Rect2(-5, 6, 10, 2), Color(0, 0, 0, 0.35))      # its shadow on the floor
	if kind == "fuse":
		var o := Vector2(-3, -9 + bob)
		draw_rect(Rect2(o, Vector2(7, 14)), OUTLINE)
		draw_rect(Rect2(o + Vector2(1, 1), Vector2(5, 3)), STEEL)            # metal caps
		draw_rect(Rect2(o + Vector2(1, 10), Vector2(5, 3)), STEEL)
		draw_rect(Rect2(o + Vector2(1, 4), Vector2(5, 6)), Color(0.24, 0.16, 0.08))
		var glow := AMBER.lerp(Color(1, 1, 0.8), 0.3 + 0.3 * sin(_t * 6.0))
		draw_rect(Rect2(o + Vector2(3, 4), Vector2(1, 6)), glow)             # the glowing wire
	else:
		var o := Vector2(-4, -10 + bob)
		draw_rect(Rect2(o, Vector2(9, 14)), OUTLINE)
		draw_rect(Rect2(o + Vector2(1, 2), Vector2(4, 11)), PURPLE)
		draw_rect(Rect2(o + Vector2(5, 2), Vector2(3, 11)), PURPLE.darkened(0.4))
		draw_rect(Rect2(o + Vector2(-2, 0), Vector2(13, 2)), OUTLINE)       # the jaws
		draw_rect(Rect2(o + Vector2(-1, 0), Vector2(11, 1)), Color(0.92, 0.85, 1.0))


## Set down in a socket: a short purple post with the jaws on top, like a mini pillar.
func _draw_clamp_post() -> void:
	draw_rect(Rect2(-7, 2, 14, 4), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(-6, -20, 12, 24), OUTLINE)
	draw_rect(Rect2(-5, -18, 5, 21), PURPLE)
	draw_rect(Rect2(0, -18, 5, 21), PURPLE.darkened(0.4))
	draw_rect(Rect2(-4, -18, 1, 21), PURPLE.lightened(0.5))
	draw_rect(Rect2(-8, -22, 16, 3), OUTLINE)
	var pulse := 0.6 + 0.4 * sin(_t * 4.0)
	draw_rect(Rect2(-7, -21, 14, 1), Color(0.95, 0.85, 1.0, pulse))


## Picked up: it jumps up, fades and is gone.
func collect() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position:y", position.y - 18.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.set_parallel(false)
	tw.tween_callback(queue_free)
