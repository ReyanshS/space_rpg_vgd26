# ---------------------------------------------------------------------------
# floor_guide.gd  -  yellow chevrons painted on the floor ("follow the yellow
# line") that show the route in tutorial rooms - or, as a HINT, the route
# through a harder room once the player presses H.
#
# It IS a Line2D (extends Line2D), so in the editor you edit it like any line:
# select it, and click in the 2D view to add / drag points. The chevrons come
# from a small repeating texture, and a tiny shader (guide_scroll.gdshader)
# makes them slide along the line.
#
# THE SHIP IS DARK, so how does the guide stay bright?
#   It goes on the GLOW light channel (LightFX.glow - read light_fx.gd for how
#   light channels work). The darkness can't dim it, and because it stays on
#   the floor (z_index -8), the astronaut walks ON TOP of it.
#
# When its room gets powered, it fades away - it finds out by LISTENING to the
# level's room_solved signal. Hint guides also listen to hint_shown.
# ---------------------------------------------------------------------------
class_name FloorGuide
extends Line2D

## Fade the guide out once its room is solved.
@export var fade_when_room_solved := true
## Hidden until the player asks for a hint (H) in this room.
@export var hint_only := false

var _room := -1
var _alpha := 1.0


func _ready() -> void:
	LightFX.glow(self)
	_alpha = modulate.a
	if hint_only:
		visible = false
		add_to_group("hint_guide")      # the level looks for these to know which rooms have hints
	# Our parent nodes run _ready AFTER us, so the level isn't set up yet.
	# call_deferred = "do this at the end of the frame", when everything is ready.
	_connect_to_level.call_deferred()


func _connect_to_level() -> void:
	var level := get_tree().get_first_node_in_group("level") as WireLevel
	if level == null or points.is_empty():
		return
	# Which room is the guide in? Use its first point (converted to level space).
	_room = level.room_index_at(level.to_local(to_global(points[0])))
	level.room_solved.connect(_on_room_solved)
	level.hint_shown.connect(_on_hint_shown)


## Which room this guide belongs to (-1 until the level is ready).
func room_index() -> int:
	return _room


# Signal handler: the level calls this when ANY room is solved, with its number.
func _on_room_solved(index: int) -> void:
	if index == _room and fade_when_room_solved:
		create_tween().tween_property(self, "modulate:a", 0.0, 0.6)


func _on_hint_shown(index: int) -> void:
	if index != _room or not hint_only or visible:
		return
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", _alpha, 0.5)
