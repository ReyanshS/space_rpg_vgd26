# ---------------------------------------------------------------------------
# push_crate.gd: a cargo crate on wheels that you can push (map char `c`, tile
# kind "box" in the Layout palette).
#
# Walk into one and lean on it for a moment: it rolls one tile the way you're
# pushing, if there's floor there. Like the fixed wooden crates it blocks your
# feet and the wire. Push it onto a live red tile and it shorts the tile out:
# the crate sinks into the floor and leaves a steel plate you (and the wire)
# can cross. R puts the crates of the room you're in back where they started.
#
# The level (level.gd, "movable crates") decides when a crate may move and
# keeps track of where every crate is. This script only draws the crate and
# plays its animations: slide_to(), ground() and go_home().
# ---------------------------------------------------------------------------
@tool
class_name PushCrate
extends Node2D

const OUTLINE := Color(0.02, 0.035, 0.13)
const STEEL_TOP := Color(0.74, 0.8, 0.88)
const STEEL := Color(0.52, 0.6, 0.71)
const STEEL_DARK := Color(0.33, 0.39, 0.5)
const STRIPE := Color(1.0, 0.76, 0.2)
const STRIPE_DARK := Color(0.16, 0.14, 0.12)
const SLIDE_TIME := 0.16       # seconds to roll one tile

## The tile it started on (R sends it back here), and the tile it stands on now.
var home := Vector2i.ZERO
var cell := Vector2i.ZERO
## The room it belongs to (level.gd's Room), set by the level.
var room = null
## Sunk into a red tile: now it's a flat plate in the floor.
var grounded := false
## A picture painted on the map for this crate (the team's art). Not drawn: a
## crate you can push always looks like the striped steel crate (draw_crate), so
## players can tell it from the fixed wooden ones at a glance (Nov 26 2026).
var art: Texture2D
var _bump := 0.0               # a little squash when it gets pushed or is stuck


func _ready() -> void:
	z_index = 2                    # over the floor and pads, under the player


func _process(delta: float) -> void:
	if _bump > 0.0:
		_bump = maxf(0.0, _bump - delta * 6.0)
		queue_redraw()


func _draw() -> void:
	if grounded:
		draw_plate(self, Vector2.ZERO)
	else:
		var squash := roundf(_bump * 2.0)
		draw_crate(self, Vector2(0, squash), squash)


## Rolls to `pos` (a tile centre). The level has already moved it in its map.
func slide_to(pos: Vector2) -> void:
	_bump = 1.0
	var tw := create_tween()
	tw.tween_property(self, "position", pos, SLIDE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Leaned on, but there's no room behind it: a small shudder.
func refuse() -> void:
	_bump = 0.6
	queue_redraw()


## Pushed onto a live red tile: it sparks, sinks and becomes a plate.
func ground() -> void:
	var tw := create_tween()
	tw.tween_interval(SLIDE_TIME)
	tw.tween_property(self, "scale", Vector2(1.08, 0.7), 0.12)
	tw.tween_callback(func() -> void:
		grounded = true
		scale = Vector2.ONE
		queue_redraw())


## Back to where it started (R). A quick fade so it doesn't fly across the room.
func go_home(pos: Vector2) -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.12)
	tw.tween_callback(func() -> void:
		position = pos
		grounded = false
		scale = Vector2.ONE
		queue_redraw())
	tw.tween_property(self, "modulate:a", 1.0, 0.18)


## The crate, centred on `o` (a tile centre). Static so the level can draw the
## same picture in the editor (see level.gd _draw_crate_preview).
static func draw_crate(ci: CanvasItem, o: Vector2, squash := 0.0) -> void:
	var top := -13.0 + squash
	ci.draw_rect(Rect2(o + Vector2(-14, 11), Vector2(28, 4)), Color(0, 0, 0, 0.35))          # shadow
	ci.draw_rect(Rect2(o + Vector2(-14, top - 1), Vector2(28, 26 - squash)), OUTLINE)
	ci.draw_rect(Rect2(o + Vector2(-13, top), Vector2(26, 8)), STEEL_TOP)                     # the lid
	ci.draw_rect(Rect2(o + Vector2(-13, top + 8), Vector2(26, 16 - squash)), STEEL)           # the front
	ci.draw_rect(Rect2(o + Vector2(-13, top + 8), Vector2(26, 1)), STEEL_DARK)
	ci.draw_rect(Rect2(o + Vector2(-11, top + 2), Vector2(22, 1)), Color(1, 1, 1, 0.35))      # shine on the lid
	# hazard stripes along the front: yellow and black slants
	var sy := top + 11.0
	ci.draw_rect(Rect2(o + Vector2(-12, sy), Vector2(24, 5)), STRIPE)
	for i in 6:
		var x := -12.0 + i * 4.0
		ci.draw_colored_polygon(PackedVector2Array([o + Vector2(x, sy + 5), o + Vector2(x + 2, sy + 5),
			o + Vector2(x + 4, sy), o + Vector2(x + 2, sy)]), STRIPE_DARK)
	# corner bolts and two little wheels
	for x in [-11.0, 10.0]:
		ci.draw_rect(Rect2(o + Vector2(x, top + 1), Vector2(1, 1)), STEEL_DARK)
		ci.draw_rect(Rect2(o + Vector2(x, top + 18 - squash), Vector2(1, 1)), STEEL_DARK)
	for x in [-10.0, 6.0]:
		ci.draw_rect(Rect2(o + Vector2(x, 10), Vector2(4, 3)), OUTLINE)


## A crate that shorted out a red tile: a flat steel plate with a yellow rim.
static func draw_plate(ci: CanvasItem, o: Vector2) -> void:
	ci.draw_rect(Rect2(o + Vector2(-14, -14), Vector2(28, 28)), OUTLINE)
	ci.draw_rect(Rect2(o + Vector2(-13, -13), Vector2(26, 26)), STRIPE.darkened(0.25))
	ci.draw_rect(Rect2(o + Vector2(-11, -11), Vector2(22, 22)), STEEL_DARK)
	ci.draw_rect(Rect2(o + Vector2(-11, -11), Vector2(22, 1)), STEEL)
	for x in [-9.0, 8.0]:
		for y in [-9.0, 8.0]:
			ci.draw_rect(Rect2(o + Vector2(x, y), Vector2(1, 1)), STEEL_TOP)
	ci.draw_rect(Rect2(o + Vector2(-6, -1), Vector2(12, 2)), STEEL)                           # a seam
