# ---------------------------------------------------------------------------
# test_start.gd: a marker that says "start the playtest here".
#
# Every level scene has a TestStart node. To try out the room you're working on:
#   1. Select TestStart in the scene tree and drag it into that room.
#   2. Tick "Active" in the Inspector.
#   3. Press F6 (Run Current Scene). You start on the marker, and every room
#      before it already has power: doors open, cargo sunk, and in Level 3
#      PIP has already turned (and flown to the right socket).
#
# Quicker: paint the "test start" tile (the green flag in the Layout palette)
# where you want to start and press F6. A painted tile wins over this node.
#
# It only works when you run that one level scene from the Godot editor (F6).
# Playing the whole game (F5, title -> Level 1 -> ...) or an exported / web build
# ignores it completely, so you can't ship a game that starts in the wrong room.
# level.gd does the work (_apply_test_start); this script just holds the settings
# and draws a flag in the editor so you can see where it is.
# ---------------------------------------------------------------------------
@tool
class_name TestStart
extends Marker2D

## Use this marker when you press F6? (Untick it to start at the normal spawn.)
@export var active := false:
	set(value):
		active = value
		queue_redraw()
## Count every room before this one as already powered.
@export var skip_earlier_rooms := true
## Still play PIP's LEVEL_START lines (the level intro)? Usually you don't want
## to click through them every time you test.
@export var play_intro := false


# Only drawn in the editor: a little flag, green when active, grey when not.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var col := Color(0.3, 1.0, 0.45) if active else Color(0.55, 0.55, 0.6)
	draw_rect(Rect2(-1, -22, 2, 22), col)                                  # the pole
	draw_colored_polygon(PackedVector2Array([Vector2(1, -22), Vector2(13, -18), Vector2(1, -14)]), col)
	var label := "TEST START (F6)" if active else "test start: off"
	draw_string(ThemeDB.fallback_font, Vector2(6, 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
