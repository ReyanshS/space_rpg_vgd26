# ---------------------------------------------------------------------------
# key_hint.gd: a little "press this key" sign. One or more keyboard keys drawn
# as keycaps (the same look as the E key that bobs over the astronaut), then a
# word or two saying what they do:   [E] grab the wire
#
# Used on the title screen, the pause menu and the console. Put one in a scene
# (add a Control, attach this script) and fill in Keys and Text in the
# Inspector, or make them in code:  KeyHint.make(["E"], "next")
# It works out its own size, so containers (HBox, VBox...) can line them up and
# centre them.
# ---------------------------------------------------------------------------
@tool
class_name KeyHint
extends Control

const FONT_SIZE := UIStyle.BODY      # the words after the keys (the keys' own look is in ui_style.gd)

## The keys, e.g. ["E"] or ["W", "A", "S", "D"]. Each one is its own keycap.
@export var keys: PackedStringArray = ["E"]:
	set(v):
		keys = v
		_refresh()
## What the keys do. Empty = just the keys.
@export var text := "":
	set(v):
		text = v
		_refresh()
## The colour of the text after the keys.
@export var text_color := UIStyle.DIM


static func make(p_keys: PackedStringArray, p_text: String, color := UIStyle.DIM) -> KeyHint:
	var k := KeyHint.new()
	k.keys = p_keys
	k.text = p_text
	k.text_color = color
	return k


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh()


func _refresh() -> void:
	update_minimum_size()
	queue_redraw()


func _get_minimum_size() -> Vector2:
	var w := 0.0
	for k in keys:
		w += UIStyle.key_width(k) + 2.0
	if text != "":
		w += 3.0 + UIStyle.text_width(text, FONT_SIZE)
	return Vector2(ceilf(w), 13.0)


func _draw() -> void:
	var y := floorf((size.y - UIStyle.KEY_H) * 0.5)
	var x := 0.0
	for k in keys:
		x += UIStyle.draw_key(self, Vector2(x, y), k) + 2.0
	if text != "":
		UIStyle.text(self, Vector2(x + 3.0, y + UIStyle.KEY_H - 2.5), text, text_color, FONT_SIZE)
