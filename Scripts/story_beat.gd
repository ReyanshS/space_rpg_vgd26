# ---------------------------------------------------------------------------
# story_beat.gd  -  ONE thing PIP (the ship's AI) says, and WHEN.
#
# Like a TutorialStep, a beat is a marker you place in the level (a Marker2D).
# Its position says which ROOM it belongs to (and, for REACH_HERE, the spot you
# have to walk to). story.gd (on the parent "Story" node) plays each beat once,
# when its trigger happens in its room.
#
# To add a line of story: duplicate a beat (Ctrl+D), drag it into the right
# room, then set Trigger and Lines in the Inspector. Each entry in Lines is one
# speech bubble. You can write {cells}, {o2_bonus} or {o2_per_cell} in a line
# and it gets replaced with the real number (see Game.story_values()).
# ---------------------------------------------------------------------------
@tool
class_name StoryBeat
extends Marker2D

enum Trigger {
	LEVEL_START,        ## as soon as the level begins (room doesn't matter)
	ENTER_ROOM,         ## you walk into this beat's room for the first time
	SOLVE_ROOM,         ## you power this beat's room
	REACH_HERE,         ## you walk close to this marker
	GRAB_WIRE,          ## you first pick up the wire in this room
	FAIL_IN_ROOM,       ## you fail in this room for the first time
	AIRLOCK,            ## the airlock in this room starts cycling
	ALL_POWERED,        ## after the lights-on cutscene, when you can move again (room doesn't matter)
	FIRST_DRIFT,        ## you first drift across open space in this room
	TOUCH_EMPTY_CELL,   ## you touch a power cell WITHOUT the wire (room doesn't matter)
	SHIP_LIGHTS_UP,     ## every room has power: plays DURING the lights-on cutscene (room doesn't matter)
}

@export var trigger: Trigger = Trigger.ENTER_ROOM:
	set(value):
		trigger = value
		queue_redraw()
## Who's talking (shown in yellow before the text).
@export var speaker := "PIP"
## One entry = one speech bubble. Keep each under about 90 letters so it fits.
@export var lines: PackedStringArray = ["Hello!"]:
	set(value):
		lines = value
		queue_redraw()
## Freeze the player until every line is read (press E to go on). Only works when
## the player isn't carrying the wire - otherwise the lines just play normally.
@export var pause_game := false
## While these lines play, a blue arrow points at this marker. Put the marker
## on the thing PIP is talking about (it still has to be in the right room).
@export var point_here := false


# Only drawn in the editor: the trigger and the start of the first line.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var first := lines[0] if lines.size() > 0 else ""
	var label := "%s: %s" % [Trigger.keys()[trigger], first.left(24)]
	draw_string(ThemeDB.fallback_font, Vector2(6, 10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.9, 1.0))
