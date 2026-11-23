# ---------------------------------------------------------------------------
# ui_style.gd: the look of every menu and of the HUD, in one place.
#
# "Clean sci-fi": dark glass panels with rounded corners and a thin cyan edge,
# white text, amber for things you can press or buy, green for done, red for
# danger. The theme (Assets/ui/theme.tres) gives Buttons, Labels and panels
# this look by itself; the screens that draw themselves in code (the console,
# the skill tree, the map, keycaps...) use the colours and helpers below, so a
# colour changed here changes everywhere.
#
# Sizes are in game pixels. The game is 480 x 270 game pixels, shown 3x as big
# in a 1440 x 810 window. The project's stretch mode is "canvas_items", so text
# and panels are drawn at the window's real resolution (sharp), while the
# pixel art world keeps its chunky pixels.
#
# The font is the one built into Godot (Open Sans), so there's no font file to
# credit. The pixel font (m6x11) is still in Assets/fonts if you want it for
# something retro.
# ---------------------------------------------------------------------------
@tool
class_name UIStyle
extends RefCounted

# --- colours
const GLASS := Color(0.03, 0.055, 0.09, 0.9)      # panel background
const GLASS_HI := Color(0.07, 0.12, 0.19, 0.94)   # a raised tile on a panel
const EDGE := Color(0.4, 0.82, 1.0, 0.45)         # the thin cyan edge of a panel
const CYAN := Color(0.4, 0.85, 1.0)               # accents, headings
const TEXT := Color(0.9, 0.95, 1.0)               # normal text
const DIM := Color(0.56, 0.66, 0.78)              # less important text
const FAINT := Color(0.3, 0.38, 0.48)             # locked, switched off
const AMBER := Color(1.0, 0.76, 0.3)              # keys, things to buy, highlights
const GREEN := Color(0.45, 0.95, 0.65)            # done, powered, unlocked
const RED := Color(1.0, 0.36, 0.32)               # danger
const SHADOW := Color(0, 0, 0, 0.45)
const LED_OFF := Color(0.1, 0.14, 0.2)            # a meter segment that isn't lit

# --- font sizes (game pixels: 8 here is 24 pixels on screen)
const SMALL := 6
const BODY := 8
const HEAD := 11
const TITLE := 18


static func font() -> Font:
	return ThemeDB.fallback_font


## A glass panel style: use it for a Panel / PanelContainer, or draw it with draw_box.
static func box(bg := GLASS, edge := EDGE, radius := 4, shadow := 3, margin := 6.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.shadow_color = SHADOW
	s.shadow_size = shadow
	s.set_content_margin_all(margin)
	return s


## Draws a glass panel on `ci` (a Control or Node2D, inside its _draw).
static func draw_box(ci: CanvasItem, r: Rect2, bg := GLASS, edge := EDGE, radius := 4) -> void:
	ci.draw_style_box(box(bg, edge, radius, 0), r)


## Text with its baseline at `at`. CENTER / RIGHT align it round / up to at.x.
static func text(ci: CanvasItem, at: Vector2, s: String, col: Color, size := BODY,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f := font()
	var x := at.x
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		x -= w * (0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else 1.0)
	ci.draw_string(f, Vector2(x, at.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func text_width(s: String, size := BODY) -> float:
	return font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## How wide a keycap for `key` is (KEY_H tall).
const KEY_H := 11.0
static func key_width(key: String) -> float:
	return maxf(KEY_H, text_width(key, SMALL + 1) + 6.0)


## A keyboard key with `key` on it, its top left corner at `o`. Returns its width.
static func draw_key(ci: CanvasItem, o: Vector2, key: String) -> float:
	var w := key_width(key)
	var r := Rect2(o, Vector2(w, KEY_H))
	var base := StyleBoxFlat.new()
	base.set_corner_radius_all(2)
	base.bg_color = Color(0.55, 0.62, 0.72)                 # the key's darker side
	ci.draw_style_box(base, Rect2(r.position + Vector2(0, 1), r.size))
	base.bg_color = Color(0.92, 0.95, 1.0)                  # its top
	ci.draw_style_box(base, Rect2(r.position, r.size - Vector2(0, 1)))
	text(ci, o + Vector2(w * 0.5, KEY_H - 3.0), key, Color(0.08, 0.12, 0.2), SMALL + 1, HORIZONTAL_ALIGNMENT_CENTER)
	return w


## One segment of a meter: lit = its colour (brighter in the middle), off = dark.
static func draw_led(ci: CanvasItem, r: Rect2, lit: bool, col: Color) -> void:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(1)
	s.bg_color = col if lit else LED_OFF
	ci.draw_style_box(s, r)
	if lit:
		ci.draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2, maxf(1.0, r.size.y * 0.3))), col.lightened(0.4))
