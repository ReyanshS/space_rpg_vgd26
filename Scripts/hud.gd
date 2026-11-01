# ---------------------------------------------------------------------------
# hud.gd  -  everything drawn on top of the game: the tutorial OBJECTIVE box and
# its bouncing ARROW, the small "toast" message (room names, ZAP!, ...), the
# 5-second timer bar, the white flash / black fade, and "Level complete".
#
# It's a CanvasLayer, which means it stays still on screen while the camera
# moves. Its nodes (Toast, TimerBar, ...) live in hud.tscn - open that scene
# to change colours and sizes without code. All text uses the project theme
# (Assets/ui/theme.tres -> the m6x11 pixel font at size 16).
# ---------------------------------------------------------------------------
class_name GameHUD
extends CanvasLayer

@onready var toast: PanelContainer = $Toast
@onready var toast_label: Label = $Toast/Text
@onready var timer_bar: Control = $TimerBar
@onready var flash_rect: ColorRect = $Flash
@onready var fade_rect: ColorRect = $Fade
@onready var complete_panel: Control = $Complete
@onready var objective: PanelContainer = $Objective
@onready var objective_label: Label = $Objective/Text
@onready var marker: Control = $Marker

var _frac := 1.0
var _secs := 0.0
var _paused := false
var _pulse := 0.0
var _toast_token := 0
var _marker_on := false
var _marker_world := Vector2.ZERO   # where the arrow points, in level (world) pixels
var _t := 0.0


func _ready() -> void:
	# The timer bar has no picture: our own function draws it (see _draw_timer).
	timer_bar.draw.connect(_draw_timer)
	marker.draw.connect(_draw_marker)
	objective.visible = false
	timer_bar.visible = false
	complete_panel.visible = false
	toast.visible = false
	flash_rect.color.a = 0.0
	fade_rect.color.a = 0.0


func _process(delta: float) -> void:
	_t += delta
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta * 2.5)
		timer_bar.queue_redraw()
	if _marker_on:
		marker.queue_redraw()      # the arrow bobs, and the camera moves, so redraw every frame


# ------------------------------------------------------------------ tutorial objective

## Shows the current tutorial instruction, and (optionally) an arrow pointing at
## `world_pos`. An empty text hides both.
func set_objective(text: String, world_pos: Vector2, arrow: bool) -> void:
	if text == "":
		objective.visible = false
		_marker_on = false
		marker.queue_redraw()
		return
	objective_label.text = text
	objective.reset_size()
	objective.visible = true
	objective.modulate = Color(1.8, 1.8, 1.8)    # flash bright, then settle
	create_tween().tween_property(objective, "modulate", Color.WHITE, 0.4)
	_marker_world = world_pos
	_marker_on = arrow
	marker.queue_redraw()


## Draws the arrow. The HUD is on its own layer that doesn't move with the camera,
## so we convert the world position into a screen position first.
func _draw_marker() -> void:
	if not _marker_on:
		return
	var screen := get_viewport().get_canvas_transform() * _marker_world
	var view := marker.size
	var margin := 18.0
	var inside := Rect2(Vector2(margin, margin + 30), view - Vector2(margin * 2, margin * 2 + 30))
	var col := Color(1.0, 0.85, 0.3)
	var dark := Color(0.15, 0.08, 0.0)
	if inside.has_point(screen):
		# on screen: a bouncing arrow pointing down at the spot
		var tip := screen + Vector2(0, -20 - roundf(absf(sin(_t * 5.0)) * 6.0))
		var tri := PackedVector2Array([tip, tip + Vector2(-7, -9), tip + Vector2(-3, -9),
			tip + Vector2(-3, -16), tip + Vector2(3, -16), tip + Vector2(3, -9), tip + Vector2(7, -9)])
		marker.draw_colored_polygon(tri, col)
		marker.draw_polyline(tri + PackedVector2Array([tip]), dark, 1.0)
	else:
		# off screen: stick to the screen edge and point towards it
		var p := Vector2(clampf(screen.x, inside.position.x, inside.end.x), clampf(screen.y, inside.position.y, inside.end.y))
		var dir := (screen - p).normalized()
		var side := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([p + dir * 9.0, p - dir * 5.0 + side * 7.0, p - dir * 5.0 - side * 7.0])
		marker.draw_colored_polygon(tri, col)
		marker.draw_polyline(tri + PackedVector2Array([tri[0]]), dark, 1.0)


# ------------------------------------------------------------------ toast

## Shows a short message at the top for `seconds`, then fades it out.
## The "token" trick: every new toast gets a new number. When an old toast's
## wait finishes, it checks the number - if a newer toast arrived meanwhile,
## it leaves that one alone instead of hiding it.
func show_toast(text: String, seconds := 2.0) -> void:
	_toast_token += 1
	var token := _toast_token
	toast_label.text = text
	toast.reset_size()
	toast.visible = true
	toast.modulate.a = 1.0
	await get_tree().create_timer(seconds).timeout
	if token != _toast_token:
		return
	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 0.0, 0.4)
	await tw.finished
	if token == _toast_token:
		toast.visible = false


# ------------------------------------------------------------------ timer

func set_timer(on: bool, frac: float, secs: float, paused := false) -> void:
	if timer_bar.visible != on:
		timer_bar.visible = on
	_frac = frac
	_secs = secs
	_paused = paused
	if on:
		timer_bar.queue_redraw()   # ask Godot to call _draw_timer again


## Flash the timer when a node refills it.
func pulse_timer() -> void:
	_pulse = 1.0


func _draw_timer() -> void:
	var size := timer_bar.size
	var font := timer_bar.get_theme_default_font()
	timer_bar.draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.09, 0.9))
	timer_bar.draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.6, 0.95, 0.9), false, 1.0)
	if _paused:
		# pause icon: two bars
		timer_bar.draw_rect(Rect2(Vector2(5, 5), Vector2(3, 12)), Color(0.5, 0.9, 1.0))
		timer_bar.draw_rect(Rect2(Vector2(10, 5), Vector2(3, 12)), Color(0.5, 0.9, 1.0))
	else:
		var b := Vector2(5, 4)
		var bolt := PackedVector2Array([b + Vector2(5, 0), b + Vector2(1, 7), b + Vector2(4, 7), b + Vector2(2, 13), b + Vector2(8, 5), b + Vector2(5, 5), b + Vector2(7, 0)])
		timer_bar.draw_colored_polygon(bolt, Color(1.0, 0.85, 0.3))
	# colour: yellow -> orange -> blinking red; light blue while paused
	var col := Color(1.0, 0.85, 0.3)
	if _paused:
		col = Color(0.45, 0.9, 1.0)
	elif _frac < 0.25:
		col = Color(1.0, 0.25, 0.2) if int(Time.get_ticks_msec() / 120.0) % 2 == 0 else Color(1.0, 0.6, 0.5)
	elif _frac < 0.5:
		col = Color(1.0, 0.55, 0.15)
	if _pulse > 0.0:
		col = col.lerp(Color.WHITE, _pulse)
	var seg_count := 5
	var x0 := 18.0
	var bar_w := size.x - x0 - 34.0
	var gap := 2.0
	var seg_w := (bar_w - gap * (seg_count - 1)) / seg_count
	var fill := _frac * seg_count
	for i in seg_count:
		var r := Rect2(x0 + i * (seg_w + gap), 5, seg_w, size.y - 10)
		timer_bar.draw_rect(r, Color(0.15, 0.17, 0.25))
		var amt := clampf(fill - i, 0.0, 1.0)
		if amt > 0.0:
			timer_bar.draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * amt), r.size.y)), col)
	timer_bar.draw_string(font, Vector2(size.x - 31, size.y - 6), "%.1f" % _secs, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


# ------------------------------------------------------------------ screen effects

func flash(color: Color, strength := 0.8) -> void:
	flash_rect.color = Color(color, strength)
	create_tween().tween_property(flash_rect, "color:a", 0.0, 0.4)


func fade_out(duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, duration)
	await tw.finished


func fade_in(duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 0.0, duration)
	await tw.finished


func show_complete() -> void:
	toast.visible = false
	complete_panel.visible = true
	complete_panel.pivot_offset = complete_panel.size * 0.5
	complete_panel.scale = Vector2(0.6, 0.6)
	complete_panel.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(complete_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(complete_panel, "modulate:a", 1.0, 0.25)
