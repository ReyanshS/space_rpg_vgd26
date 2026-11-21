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

const KEY_H := 13.0                        # a keycap is 13 px tall (like hud.gd _draw_key)
const FONT_SIZE := 16

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
@export var text_color := Color(0.66, 0.94, 0.63)


static func make(p_keys: PackedStringArray, p_text: String, color := Color(0.66, 0.94, 0.63)) -> KeyHint:
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


func _font() -> Font:
	return get_theme_default_font()


func _key_w(k: String) -> float:
	return maxf(KEY_H, _font().get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 6.0)


func _get_minimum_size() -> Vector2:
	if not is_inside_tree():
		return Vector2.ZERO
	var w := 0.0
	for k in keys:
		w += _key_w(k) + 2.0
	if text != "":
		w += 3.0 + _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	return Vector2(ceilf(w), 16.0)


func _draw() -> void:
	var font := _font()
	var y := floorf((size.y - KEY_H) * 0.5)
	var x := 0.0
	for k in keys:
		var w := _key_w(k)
		draw_rect(Rect2(x, y + 1, w, KEY_H), Color(0.05, 0.05, 0.1, 0.9))       # shadow
		draw_rect(Rect2(x, y, w, KEY_H), Color(0.95, 0.95, 1.0))                # the key's rim
		draw_rect(Rect2(x + 1, y + 1, w - 2, KEY_H - 3), Color(0.82, 0.84, 0.92))   # its face
		var tw := font.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(font, Vector2(x + roundf((w - tw) * 0.5), y + 11), k, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.12, 0.12, 0.2))
		x += w + 2.0
	if text != "":
		draw_string(font, Vector2(x + 3.0, y + 11), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, text_color)
