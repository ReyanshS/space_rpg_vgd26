# ---------------------------------------------------------------------------
# ship_map.gd: PIP's map of the deck (press M). It pauses the game and draws
# every room of the level from above, like a dungeon map:
#   amber room   powered          blue room    you've been in, no power yet
#   dark room    not visited yet  grey room    a hall (nothing to solve)
#   white dot    you (it blinks)
#   doors        green = open, red = shut, amber = needs a fuse,
#                big red/green = the main door
#   amber dot    a fuse lying there     purple dot   the cable clamp
#   small number how many batteries are still in that room
# It asks the level for everything (level.gd, map_info()) and draws it with
# draw_rect, so nothing about the map has to be painted by hand.
# The HUD makes one of these (hud.gd, open_map). M, Esc or E closes it.
# ---------------------------------------------------------------------------
class_name ShipMap
extends Control

signal closed

const AMBER := UIStyle.AMBER
const GREEN := UIStyle.GREEN
const DIM := Color(0.2, 0.32, 0.45)           # a room you've seen that has no power yet
const GLASS := UIStyle.GLASS

var _info := {}
var _t := 0.0
var _opened_frame := 0
var closed_frame := -1        # so the Esc that closed the map doesn't also open the pause menu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS      # it works while the game is paused
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open(info: Dictionary) -> void:
	_info = info
	_opened_frame = Engine.get_process_frames()
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	queue_redraw()
	if Engine.get_process_frames() == _opened_frame:
		return                                    # (the M that opened it)
	if Input.is_action_just_pressed("map") or Input.is_action_just_pressed("pause") \
			or Input.is_action_just_pressed("interact"):
		visible = false
		closed_frame = Engine.get_process_frames()
		closed.emit()


func _draw() -> void:
	if _info.is_empty():
		return
	var screen := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, screen), Color(0, 0, 0, 0.55))
	var panel := Rect2(12, 8, screen.x - 24, screen.y - 16)
	UIStyle.draw_box(self, panel, Color(0.03, 0.055, 0.09, 0.96), UIStyle.EDGE, 6)
	UIStyle.text(self, panel.position + Vector2(10, 16), "DECK MAP", UIStyle.TEXT, UIStyle.HEAD)
	UIStyle.text(self, Vector2(panel.end.x - 10, panel.position.y + 15), "M  close", UIStyle.DIM, UIStyle.SMALL + 1, HORIZONTAL_ALIGNMENT_RIGHT)
	# fit the level into the screen: how many pixels per tile
	var rect: Rect2i = _info["rect"]
	var area := Rect2(panel.position + Vector2(10, 24), panel.size - Vector2(20, 46))
	var s := floorf(minf(area.size.x / rect.size.x, area.size.y / rect.size.y))
	s = clampf(s, 2.0, 8.0)
	var origin := area.position + (area.size - Vector2(rect.size) * s) * 0.5 - Vector2(rect.position) * s
	var tile := func(c: Vector2i) -> Rect2: return Rect2((origin + Vector2(c) * s).round(), Vector2(s, s))
	for room in _info["rooms"]:
		var col := Color(0.08, 0.11, 0.16)
		if room["hall"]:
			col = Color(0.3, 0.36, 0.44) if room["visited"] else Color(0.12, 0.15, 0.2)
		elif room["solved"]:
			col = AMBER.darkened(0.25)
		elif room["visited"]:
			col = DIM
		for c in room["cells"]:
			draw_rect(tile.call(c), col)
		if room["here"] and int(_t * 3.0) % 2 == 0:
			for c in room["cells"]:
				var r: Rect2 = tile.call(c)
				draw_rect(r, Color(1, 1, 1, 0.12))
		if room["cells_left"] > 0 and room["visited"]:
			var mid := Vector2.ZERO
			for c in room["cells"]:
				mid += Vector2(c)
			mid /= room["cells"].size()
			UIStyle.text(self, origin + mid * s + Vector2(s * 0.5, s * 0.5 + 3), str(room["cells_left"]),
				AMBER, UIStyle.BODY, HORIZONTAL_ALIGNMENT_CENTER)
	for d in _info["doors"]:
		var col := Color(0.9, 0.25, 0.2)
		match d["kind"]:
			"door": col = GREEN if d["open"] else Color(0.9, 0.25, 0.2)
			"fuse_door": col = GREEN if d["open"] else AMBER
			"main_door": col = GREEN if d["open"] else Color(1.0, 0.2, 0.15)
			"barrier": col = Color(0.2, 0.22, 0.25) if d["open"] else Color(1.0, 0.55, 0.15)
		draw_rect(tile.call(d["cell"]), col)
	for it in _info["items"]:
		var r: Rect2 = tile.call(it["cell"])
		draw_rect(r.grow(-maxf(1.0, s * 0.25)), AMBER if it["kind"] == "fuse" else Color(0.75, 0.47, 1.0))
	if _info["clamp_at"].x >= 0:
		draw_rect(tile.call(_info["clamp_at"]), Color(0.75, 0.47, 1.0))
	if int(_t * 4.0) % 2 == 0:
		var p: Vector2 = origin + _info["player"] * s
		draw_circle(p, 3.0, Color(1, 1, 1, 0.25))
		draw_circle(p, 1.8, Color.WHITE)
	# the key, along the bottom
	var y := panel.end.y - 8
	var x := panel.position.x + 10
	for k in [[AMBER.darkened(0.25), "powered"], [DIM, "no power"], [AMBER, "fuse door"],
			[Color(1.0, 0.2, 0.15), "main door"], [Color.WHITE, "you"]]:
		var dot := StyleBoxFlat.new()
		dot.set_corner_radius_all(2)
		dot.bg_color = k[0]
		draw_style_box(dot, Rect2(x, y - 6, 6, 6))
		UIStyle.text(self, Vector2(x + 9, y), k[1], UIStyle.DIM, UIStyle.SMALL + 1)
		x += 18 + UIStyle.text_width(k[1], UIStyle.SMALL + 1)
