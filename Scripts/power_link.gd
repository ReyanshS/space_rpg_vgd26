# ---------------------------------------------------------------------------
# power_link.gd: "when this room gets power, change something over there".
# The dungeon switch of the game.
#
# How to use it (all in the editor, no code):
#   1. Add a PowerLink to the level (any parent, e.g. a "Links" node) and drag
#      it onto the goal (or core) of the room that should trigger it.
#   2. Give it one or more Marker2D children and drag each onto a tile it
#      should change: a door, a barrier, a red floor or a main door.
#   3. Pick the Action in the Inspector:
#        OPEN     the door / barrier at each marker opens (a barrier sinks)
#        CLOSE    it closes (a barrier rises back up)
#        RED_OFF  the red floor at each marker switches off (the whole patch of
#                 red tiles touching it), so you can walk and run the wire there
#        RED_ON   it switches back on
#        UNLOCK   lights one lamp of the main door at the marker. The main door
#                 opens when every link pointing at it has lit its lamp.
#   Message: a popup when it happens. Show Camera: the camera glides over to
#   show the change (do this when the change is out of sight).
#
# The level (level.gd, _apply_links) does the work when the room is solved.
# In the editor this draws a dotted line from the marker to each target, in the
# colour of its action, so you can see what is wired to what.
# ---------------------------------------------------------------------------
@tool
class_name PowerLink
extends Marker2D

enum Action { OPEN, CLOSE, RED_OFF, RED_ON, UNLOCK }

const COLORS := {
	Action.OPEN: Color(0.4, 1.0, 0.55),
	Action.CLOSE: Color(1.0, 0.6, 0.2),
	Action.RED_OFF: Color(0.5, 0.85, 1.0),
	Action.RED_ON: Color(1.0, 0.3, 0.25),
	Action.UNLOCK: Color(1.0, 0.85, 0.3),
}

@export var action: Action = Action.OPEN:
	set(value):
		action = value
		queue_redraw()
## A short popup when it happens (empty = none). Capitals, like the others.
@export var message := ""
## The camera glides over to show what changed, then comes back.
@export var show_camera := true


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group("power_link")      # the level finds every link through this group


## The tiles this link changes: one under each child marker.
func target_cells(level: WireLevel) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for child in get_children():
		if child is Node2D:
			out.append(level.cell_of(level.to_local(child.global_position)))
	return out


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()               # follow the children while you drag them


# Only in the editor: a plug icon, the action's name, and a dotted line to each target.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var col: Color = COLORS[action]
	draw_rect(Rect2(-5, -5, 10, 10), col, false, 2.0)
	draw_rect(Rect2(-2, -2, 4, 4), col)
	draw_string(ThemeDB.fallback_font, Vector2(8, -4), "LINK: " + Action.keys()[action],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
	for child in get_children():
		if not (child is Node2D):
			continue
		var to: Vector2 = to_local(child.global_position)
		var d := to.length()
		if d < 4.0:
			continue
		var dir := to / d
		var t := 8.0
		while t < d - 6.0:
			draw_rect(Rect2(dir * t - Vector2.ONE, Vector2(2, 2)), col)
			t += 7.0
		draw_arc(to, 8.0, 0.0, TAU, 16, col, 2.0)
