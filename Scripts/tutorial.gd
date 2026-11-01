# ---------------------------------------------------------------------------
# tutorial.gd  -  runs the guided tutorial: shows ONE instruction at a time,
# points an arrow at where you need to go, and moves on when you do it.
#
# HOW IT FITS TOGETHER
#   - The steps are the TutorialStep children of this node, in tree order.
#   - The level ANNOUNCES things with signals (wire_grabbed, pad_touched,
#     room_solved, room_entered, room_restarted, drift_started). This script
#     LISTENS to them. The level doesn't know the tutorial exists - that's the
#     point of signals: the level just says "this happened", and anyone
#     interested can react.
#   - Each step remembers which room it's in. A trigger only counts if it
#     happens in that room. A step stays hidden until you walk into its room
#     (so a Level 2 step about the airlock doesn't show up on the bridge).
#   - If you fail and the room restarts, we jump back to that room's first step.
#   - The HUD draws the text and the arrow (so the dark lighting doesn't hide them).
# ---------------------------------------------------------------------------
class_name Tutorial
extends Node2D

var _steps: Array[TutorialStep] = []
var _rooms: Array[int] = []     # room number of each step (same order as _steps)
var _current := -1
var _level: WireLevel
var _player: Astronaut


func _ready() -> void:
	# Children run _ready before their parents, so the level isn't set up yet.
	# Wait until the end of this frame, when everything is ready.
	_start.call_deferred()


func _start() -> void:
	_level = get_tree().get_first_node_in_group("level") as WireLevel
	_player = get_tree().get_first_node_in_group("player") as Astronaut
	if _level == null:
		return
	for child in get_children():
		if child is TutorialStep:
			_steps.append(child)
			_rooms.append(_level.room_index_at(_level.to_local(child.global_position)))
	# Listen to the level's announcements. Each signal calls one of our functions.
	_level.wire_grabbed.connect(_on_wire_grabbed)
	_level.pad_touched.connect(_on_pad_touched)
	_level.room_solved.connect(_on_room_solved)
	_level.room_entered.connect(_on_room_entered)
	_level.room_restarted.connect(_on_room_restarted)
	_level.drift_started.connect(_on_drift_started)
	_go_to(0)


func _go_to(i: int) -> void:
	_current = i
	_show_current()


## Shows the current step - but only once the player is in that step's room.
func _show_current() -> void:
	if _current >= _steps.size():
		_level.hud.set_objective("", Vector2.ZERO, false)   # tutorial finished
		return
	if _rooms[_current] != _level.current_room_index():
		_level.hud.set_objective("", Vector2.ZERO, false)   # not there yet
		return
	var s := _steps[_current]
	_level.hud.set_objective(s.text, s.global_position, s.show_arrow)


## Move on if the current step was waiting for `trigger` in room `room`.
func _check(trigger: TutorialStep.Trigger, room: int) -> void:
	if _current < 0 or _current >= _steps.size():
		return
	var s := _steps[_current]
	if s.advance_when == trigger and room == _rooms[_current]:
		_go_to(_current + 1)


func _process(_delta: float) -> void:
	# REACH_HERE steps: has the player walked to the marker?
	if _current < 0 or _current >= _steps.size() or _player == null:
		return
	var s := _steps[_current]
	if s.advance_when == TutorialStep.Trigger.REACH_HERE:
		if _player.global_position.distance_to(s.global_position) < 24.0:
			_go_to(_current + 1)


# --- signal handlers: the level calls these when things happen ----------------

func _on_wire_grabbed(room: int) -> void:
	_check(TutorialStep.Trigger.GRAB_WIRE, room)


func _on_pad_touched(kind: String, room: int) -> void:
	if kind == "node":
		_check(TutorialStep.Trigger.TOUCH_NODE, room)
	elif kind == "bend":
		_check(TutorialStep.Trigger.TOUCH_BEND, room)


func _on_room_solved(room: int) -> void:
	_check(TutorialStep.Trigger.SOLVE_ROOM, room)


func _on_drift_started(room: int) -> void:
	_check(TutorialStep.Trigger.DRIFT, room)


func _on_room_entered(room: int) -> void:
	if _current < 0 or _current >= _steps.size():
		return
	var s := _steps[_current]
	if s.advance_when == TutorialStep.Trigger.ENTER_NEXT_ROOM and room > _rooms[_current]:
		_go_to(_current + 1)
	else:
		_show_current()      # maybe we just walked into this step's room


func _on_room_restarted(room: int) -> void:
	if _current < 0 or _current >= _steps.size() or _rooms[_current] != room:
		return
	# rewind to the first step that belongs to this room
	_go_to(_rooms.find(room))
