# ---------------------------------------------------------------------------
# tutorial_step.gd  -  ONE instruction in the guided tutorial.
#
# A step is a marker you place in the level (it's a Marker2D, so it shows as a
# little cross in the editor). Where you put it is where the on-screen arrow
# points. The step does nothing by itself - tutorial.gd (on the parent
# "Tutorial" node) shows the steps one at a time, in the order they appear in
# the scene tree, and moves on when `advance_when` happens.
#
# To add a step: select an existing step, Duplicate it (Ctrl+D), drag it where
# the arrow should point, change its Text and Advance When. Drag it up/down in
# the scene tree to change the order.
# ---------------------------------------------------------------------------
@tool
class_name TutorialStep
extends Marker2D

## What has to happen before the tutorial moves on to the next step.
enum Trigger {
	GRAB_WIRE,        ## you pick up the wire in this step's room
	TOUCH_NODE,       ## the wire touches an orange node in this room
	TOUCH_BEND,       ## the wire touches a purple bend in this room
	SOLVE_ROOM,       ## you power this room's goal
	ENTER_NEXT_ROOM,  ## you walk into a later room
	REACH_HERE,       ## you walk to where this marker is
}

## The instruction shown at the top of the screen.
@export_multiline var text := "Do something!":
	set(value):
		text = value
		queue_redraw()
@export var advance_when: Trigger = Trigger.REACH_HERE
## Show the bouncing arrow over this marker?
@export var show_arrow := true


# Only drawn in the editor: the step number and the start of its text, so you
# can see the order at a glance.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var number := 1
	for sibling in get_parent().get_children():
		if sibling == self:
			break
		if sibling is TutorialStep:
			number += 1
	var label := "%d. %s" % [number, text.left(28)]
	draw_string(ThemeDB.fallback_font, Vector2(6, -6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.85, 0.3))
