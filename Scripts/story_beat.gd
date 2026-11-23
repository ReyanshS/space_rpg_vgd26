# ---------------------------------------------------------------------------
# story_beat.gd: one thing PIP (the ship's AI) says, and when.
#
# Like a TutorialStep, a beat is a marker you place in the level (a Marker2D).
# Its position says which room it belongs to (and, for REACH_HERE, the spot you
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
	TOUCH_EMPTY_CELL,   ## you touch a power cell without the wire (room doesn't matter)
	SHIP_LIGHTS_UP,     ## every room has power: plays during the lights-on cutscene (room doesn't matter)
	PUSH_CRATE,         ## you first push a movable crate in this room
	GROUND_CRATE,       ## a crate first shorts out a red tile in this room
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
## the player isn't carrying the wire. Otherwise the lines just play normally.
@export var pause_game := false:
	set(value):
		pause_game = value
		queue_redraw()
## While these lines play, PIP's blue arrow points at this marker. Or, if you
## give the marker a child Marker2D, at that child instead. (Add one with
## right-click > Add Child Node > Marker2D and drag it onto what PIP is talking
## about. The beat itself still has to sit in the right ROOM.)
@export var point_here := false:
	set(value):
		point_here = value
		queue_redraw()


const CONSOLE_SIZE := 9           # the console's text size (hud.tscn, Dialogue/Row/Text)
const CONSOLE_WIDTH := 254.0      # pixels of text per row in PIP's console (hud.tscn)


## Editor only: how many rows `line` takes in PIP's console at font size `size`
## (wrapping word by word, like the console does).
func _rows(line: String, size: int) -> int:
	var font := ThemeDB.fallback_font       # the game's font (see ui_style.gd)
	var rows := 1
	var row := speaker + ": "
	for word in line.split(" ", false):
		var trial := row + word
		if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > CONSOLE_WIDTH:
			rows += 1
			row = word + " "
		else:
			row = trial + " "
	return rows


## Where the blue arrow points: the first Node2D child if there is one, else here.
func arrow_position() -> Vector2:
	for child in get_children():
		if child is Node2D:
			return child.global_position
	return global_position


# In the editor, keep redrawing so the line to a dragged arrow target follows it.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


# Only drawn in the editor: a speech bubble, the trigger, the first line, and
# (with point_here) a dotted line to where the arrow will point.
# Red = said by the malfunctioning PIP ("P!P"), blue = anyone else.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var col := Color(1.0, 0.45, 0.4) if speaker == "P!P" else Color(0.55, 0.9, 1.0)
	draw_rect(Rect2(-6, -6, 12, 8), col)                                   # speech bubble
	draw_colored_polygon(PackedVector2Array([Vector2(-3, 2), Vector2(1, 2), Vector2(-4, 6)]), col)
	var first := lines[0] if lines.size() > 0 else "(no lines yet)"
	var head: String = str(Trigger.keys()[trigger]) + ("  [pauses]" if pause_game else "")
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(9, -2), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
	draw_string(font, Vector2(9, 10), "%s: %s" % [speaker, first.left(34)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col.lightened(0.4))
	var y := 21.0
	if lines.size() > 1:
		draw_string(font, Vector2(9, y), "+%d more line%s" % [lines.size() - 1, "s" if lines.size() > 2 else ""],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col.darkened(0.2))
		y += 11.0
	# Will every line fit in the two rows of PIP's console? Too long = it gets
	# split in two in the game, and people miss half of it.
	for i in lines.size():
		if _rows(lines[i], CONSOLE_SIZE) > 2:
			draw_string(font, Vector2(9, y), "line %d TOO LONG: shorten it" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.3, 0.25))
			y += 11.0
	if point_here:
		var target := to_local(arrow_position())
		var d := target.length()
		if d > 8.0:
			var dir := target / d
			var t := 6.0
			while t < d:
				draw_rect(Rect2(dir * t - Vector2.ONE, Vector2(2, 2)), Color(0.5, 0.9, 1.0))
				t += 6.0
		# a small arrow pointing down at the target, like the one in the game
		var tip := target + Vector2(0, -6)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-5, -7), tip + Vector2(5, -7)]), Color(0.5, 0.9, 1.0))
