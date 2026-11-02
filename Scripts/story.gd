# ---------------------------------------------------------------------------
# story.gd  -  plays the StoryBeat children: what PIP says, and when.
#
# HOW IT FITS TOGETHER (same idea as tutorial.gd)
#   - The level ANNOUNCES events with signals: room_entered, room_solved,
#     wire_grabbed, room_restarted, airlock_cycling, drift_started... This
#     script LISTENS and plays the beats whose trigger matches.
#   - Each beat plays once. Its room comes from where the marker is placed.
#   - The HUD draws the speech box (hud.say). If a beat has "pause_game" on,
#     the player has to press E through the lines before moving again.
# ---------------------------------------------------------------------------
class_name Story
extends Node2D

const REACH_DISTANCE := 28.0

var _beats: Array[StoryBeat] = []
var _rooms: Array[int] = []       # room number of each beat (same order as _beats)
var _played := {}                 # beat -> true once it has played
var _level: WireLevel
var _player: Astronaut


func _ready() -> void:
	# Children run _ready before their parents, so the level isn't set up yet.
	_start.call_deferred()


func _start() -> void:
	_level = get_tree().get_first_node_in_group("level") as WireLevel
	_player = get_tree().get_first_node_in_group("player") as Astronaut
	if _level == null:
		return
	for child in get_children():
		if child is StoryBeat:
			_beats.append(child)
			_rooms.append(_level.room_index_at(_level.to_local(child.global_position)))
	_level.room_entered.connect(func(i: int) -> void: _fire(StoryBeat.Trigger.ENTER_ROOM, i))
	_level.room_solved.connect(func(i: int) -> void: _fire(StoryBeat.Trigger.SOLVE_ROOM, i))
	_level.wire_grabbed.connect(func(i: int) -> void: _fire(StoryBeat.Trigger.GRAB_WIRE, i))
	_level.room_restarted.connect(func(i: int) -> void: _fire(StoryBeat.Trigger.FAIL_IN_ROOM, i))
	_level.airlock_cycling.connect(func(i: int) -> void: _fire(StoryBeat.Trigger.AIRLOCK, i))
	_level.drift_started.connect(func(i: int) -> void: _fire(StoryBeat.Trigger.FIRST_DRIFT, i))
	_level.all_rooms_powered.connect(func() -> void: _fire(StoryBeat.Trigger.ALL_POWERED, -1))
	_level.ship_lighting_up.connect(func() -> void: _fire(StoryBeat.Trigger.SHIP_LIGHTS_UP, -1))
	_level.empty_cell_touched.connect(func() -> void: _fire(StoryBeat.Trigger.TOUCH_EMPTY_CELL, -1))
	_fire(StoryBeat.Trigger.LEVEL_START, -1)
	_fire(StoryBeat.Trigger.ENTER_ROOM, _level.current_room_index())   # you start inside a room


## Plays every beat (not played yet) with this trigger in this room.
## room = -1 means "any room" (LEVEL_START, ALL_POWERED, TOUCH_EMPTY_CELL).
func _fire(trigger: StoryBeat.Trigger, room: int) -> void:
	for i in _beats.size():
		var b := _beats[i]
		if b.trigger != trigger or _played.has(b):
			continue
		if room >= 0 and _rooms[i] != room:
			continue
		_play(b)


func _play(b: StoryBeat) -> void:
	_played[b] = true
	var values := Game.story_values()
	var lines := PackedStringArray()
	for line in b.lines:
		lines.append(line.format(values))
	var point := b.global_position if b.point_here else Vector2.INF   # INF = no arrow
	_level.hud.say(lines, b.speaker, b.pause_game and _level.can_pause_for_dialogue(), point)


func _process(_delta: float) -> void:
	if _player == null:
		return
	for b in _beats:
		if b.trigger == StoryBeat.Trigger.REACH_HERE and not _played.has(b):
			if _player.global_position.distance_to(b.global_position) < REACH_DISTANCE:
				_play(b)
