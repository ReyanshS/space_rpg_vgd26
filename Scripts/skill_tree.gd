# ---------------------------------------------------------------------------
# skill_tree.gd  -  the SKILL TREE screen (Scenes/skill_tree.tscn, inside hud.tscn).
#
# Three columns (Wire, Suit, Life Support). Every skill is a little box, and a
# line joins it to the skill you need first (its parent). Each box shows its
# state:
#   LOCKED     dark grey: unlock the skill above it first
#   AVAILABLE  amber outline with its cost inside: you can buy it
#   UNLOCKED   lit green: it's yours
# Arrows move between boxes, E unlocks the selected one, T or Esc closes.
# You can also click a box to select it, and click it again to unlock it.
#
# Nothing here is typed in by hand: the boxes come from SkillManager, which
# loads the skill files in Data/skills/. A new skill file shows up here on its
# own, placed under its parent (_layout).
#
# The HUD opens it (hud.gd open_skill_tree) and pauses the game while it's
# open. This node's Process Mode is "Always" (set in skill_tree.tscn) so it
# still reads keys while the game is paused.
# ---------------------------------------------------------------------------
class_name SkillTreeScreen
extends Control

## The player closed the screen.
signal closed

const AMBER := Color(1.0, 0.76, 0.3)
const PHOSPHOR := Color(0.66, 0.94, 0.63)
const DIM := Color(0.42, 0.62, 0.45)
const LOCKED_INK := Color(0.36, 0.4, 0.42)
const LED_OFF := Color(0.12, 0.15, 0.14)
const BOX := 18.0                  # size of a skill's box, in pixels
const COLUMN_X: Array[float] = [96.0, 240.0, 384.0]   # middle of each branch's column
const COLUMN_W := 144.0
const ROW_TOP := 70.0              # middle of the first row of boxes
const ROWS_HEIGHT := 84.0          # from the first row to the last one
const LABEL_H := 16.0              # room under a box for its name

## The frame (process) number when the screen last closed. The HUD checks it so
## the Esc that closes this screen doesn't also open or close the pause menu.
var closed_frame := -1

@onready var board: Control = $Board

var _pos := {}           # skill id -> where its box is (middle), in screen pixels
var _sel := ""           # the selected skill's id
var _t := 0.0
var _opened_frame := -1  # the frame it opened on
var _flash := {}         # skill id -> time it was unlocked (it flashes white)
var _sfx := {}


func _ready() -> void:
	visible = false
	board.draw.connect(_draw_board)
	for n in ["blip", "powerup", "warn"]:
		var p := AudioStreamPlayer.new()
		var path := "res://Assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			p.stream = load(path)
		add_child(p)
		_sfx[n] = p
	_sfx["blip"].volume_db = -10.0


func open() -> void:
	_layout()
	if _sel == "" or not _pos.has(_sel):
		_sel = _first_choice()
	visible = true
	_opened_frame = Engine.get_process_frames()


func close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


func _process(delta: float) -> void:
	_t += delta
	if visible:
		board.queue_redraw()       # the selection blinks


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if not visible:
		return
	get_viewport().set_input_as_handled()    # nothing behind this screen gets the keys
	if Engine.get_process_frames() == _opened_frame:
		return                                # the key that opened it doesn't count
	if event.is_action_pressed("ui_left"):
		_move(Vector2.LEFT)
	elif event.is_action_pressed("ui_right"):
		_move(Vector2.RIGHT)
	elif event.is_action_pressed("ui_up"):
		_move(Vector2.UP)
	elif event.is_action_pressed("ui_down"):
		_move(Vector2.DOWN)
	elif event.is_action_pressed("interact"):
		_try_unlock(_sel)
	elif event.is_action_pressed("pause") or _is_key(event, KEY_T):
		close()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := _skill_at(get_global_mouse_position())
		if id == "":
			return
		if id == _sel:
			_try_unlock(id)
		else:
			_sel = id
			_sfx["blip"].play()


func _is_key(event: InputEvent, key: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and (event as InputEventKey).physical_keycode == key


## Moves the selection to the nearest box in that direction. "Nearest" counts
## sideways distance extra, so Left / Right stay on the same row if they can
## and Down prefers a box below this one.
func _move(dir: Vector2) -> void:
	if not _pos.has(_sel):
		return
	var from: Vector2 = _pos[_sel]
	var best := ""
	var best_score := INF
	for id in _pos:
		var d: Vector2 = _pos[id] - from
		var along := d.dot(dir)
		if along < 4.0:
			continue                       # not in that direction
		var sideways := 4.0 if dir.y == 0.0 else 1.5
		var score := along + absf(d.dot(Vector2(-dir.y, dir.x))) * sideways
		if score < best_score:
			best_score = score
			best = id
	if best != "":
		_sel = best
		_sfx["blip"].play()


func _try_unlock(id: String) -> void:
	if SkillManager.unlock(id):
		_flash[id] = _t
		_sfx["powerup"].play()
	else:
		_sfx["warn"].play()


func _skill_at(p: Vector2) -> String:
	for id in _pos:
		if Rect2(_pos[id] - Vector2(BOX, BOX) * 0.5, Vector2(BOX, BOX)).grow(4.0).has_point(p):
			return id
	return ""


## Select something useful when the screen opens: the first skill you can buy.
func _first_choice() -> String:
	for s in SkillManager.all_skills():
		if SkillManager.can_unlock(s.id):
			return s.id
	for s in SkillManager.all_skills():
		if SkillManager.state(s.id) == SkillManager.State.AVAILABLE:
			return s.id
	var all := SkillManager.all_skills()
	return all[0].id if not all.is_empty() else ""


# ------------------------------------------------------------------ layout
# Each branch is drawn as a tree, top to bottom. A skill with no children is a
# LEAF: leaves get the next free slot from left to right. A skill with
# children sits in the middle above them. So any shape of tree fits.

func _layout() -> void:
	_pos.clear()
	for b in SkillDef.BRANCH_NAMES.size():
		var mine: Array[SkillDef] = []
		for s in SkillManager.all_skills():
			if s.branch == b:
				mine.append(s)
		var children := {}               # parent id -> its skills in this branch
		var roots: Array[SkillDef] = []
		for s in mine:
			var p := SkillManager.get_skill(s.parent_id)
			if p == null or p.branch != b:
				roots.append(s)              # no parent (or it's in another branch)
			else:
				if not children.has(p.id):
					children[p.id] = []
				children[p.id].append(s)
		var slot := {}                   # skill id -> column slot (can be x.5)
		var depth := {}                  # skill id -> row
		var leaves := [0]                # in an Array so _place can count up
		for r in roots:
			_place(r, 0, children, slot, depth, leaves)
		var n := maxi(leaves[0], 1)
		var spacing := minf(72.0, COLUMN_W / n)
		var rows := 1
		for id in depth:
			rows = maxi(rows, depth[id] + 1)
		var step := minf(42.0, ROWS_HEIGHT / maxf(rows - 1, 1))
		for id in slot:
			var x: float = COLUMN_X[b] + (slot[id] - (n - 1) * 0.5) * spacing
			_pos[id] = Vector2(roundf(x), ROW_TOP + depth[id] * roundf(step))


func _place(s: SkillDef, d: int, children: Dictionary, slot: Dictionary, depth: Dictionary, leaves: Array) -> float:
	depth[s.id] = d
	var kids: Array = children.get(s.id, [])
	if kids.is_empty() or d > 20:        # (d > 20: a parent loop in the data, stop)
		slot[s.id] = float(leaves[0])
		leaves[0] += 1
	else:
		var total := 0.0
		for k in kids:
			total += _place(k, d + 1, children, slot, depth, leaves)
		slot[s.id] = total / kids.size()
	return slot[s.id]


# ------------------------------------------------------------------ drawing

func _draw_board() -> void:
	var font := board.get_theme_default_font()
	_text(font, Vector2(30, 34), "SKILL TREE", AMBER, 32)
	var pts := SkillManager.points
	_text(font, Vector2(450, 30), "SKILL POINTS: %d" % pts, AMBER if pts > 0 else DIM, 16, HORIZONTAL_ALIGNMENT_RIGHT)
	for b in SkillDef.BRANCH_NAMES.size():
		_text(font, Vector2(COLUMN_X[b], 52), SkillDef.BRANCH_NAMES[b], PHOSPHOR, 16, HORIZONTAL_ALIGNMENT_CENTER)
	# the lines first, so the boxes sit on top of them
	for id in _pos:
		var s := SkillManager.get_skill(id)
		if _pos.has(s.parent_id):
			_draw_link(_pos[s.parent_id], _pos[id], _ink(id))
	for id in _pos:
		_draw_skill(font, id)
	_draw_info(font)


## A line from under a parent's name down to its child's box: down, across, down.
func _draw_link(a: Vector2, b: Vector2, col: Color) -> void:
	var top := a.y + BOX * 0.5 + LABEL_H
	var mid := roundf((top + b.y - BOX * 0.5) * 0.5)
	var pts := PackedVector2Array([Vector2(a.x, top), Vector2(a.x, mid), Vector2(b.x, mid), b - Vector2(0, BOX * 0.5)])
	board.draw_polyline(pts, col, 2.0)


## The colour a skill (and the line into it) is drawn in.
func _ink(id: String) -> Color:
	match SkillManager.state(id):
		SkillManager.State.UNLOCKED:
			return PHOSPHOR
		SkillManager.State.AVAILABLE:
			return AMBER if SkillManager.can_unlock(id) else AMBER.darkened(0.45)
	return LOCKED_INK


func _draw_skill(font: Font, id: String) -> void:
	var s := SkillManager.get_skill(id)
	var c: Vector2 = _pos[id]
	var r := Rect2(c - Vector2(BOX, BOX) * 0.5, Vector2(BOX, BOX))
	var ink := _ink(id)
	var st := SkillManager.state(id)
	if st == SkillManager.State.UNLOCKED:
		# lit like one of the console's LEDs, with a dark tick on it
		var lit := PHOSPHOR.lerp(Color.WHITE, clampf(1.0 - (_t - _flash.get(id, -9.0)) * 2.0, 0.0, 1.0))
		board.draw_rect(r, lit)
		board.draw_rect(Rect2(r.position, Vector2(BOX, 1)), lit.lightened(0.45))
		board.draw_polyline(PackedVector2Array([c + Vector2(-5, 0), c + Vector2(-1, 4), c + Vector2(5, -4)]), Color(0.05, 0.2, 0.08), 2.0)
	else:
		board.draw_rect(r, LED_OFF if st == SkillManager.State.LOCKED else Color(0.07, 0.1, 0.07))
		board.draw_rect(r, ink, false, 1.0 if st == SkillManager.State.LOCKED else 2.0)
		_text(font, c + Vector2(0, 5), str(s.cost), ink, 16, HORIZONTAL_ALIGNMENT_CENTER)
	if id == _sel and fmod(_t, 0.8) < 0.55:
		_draw_corners(r.grow(4.0), Color.WHITE)
	_text(font, c + Vector2(0, BOX * 0.5 + 12), s.label(), ink if st != SkillManager.State.LOCKED else LOCKED_INK, 16, HORIZONTAL_ALIGNMENT_CENTER)


## Four little corner brackets round the selected box.
func _draw_corners(r: Rect2, col: Color) -> void:
	var k := 4.0
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if corner.x == r.position.x else -1.0
		var sy := 1.0 if corner.y == r.position.y else -1.0
		board.draw_polyline(PackedVector2Array([corner + Vector2(0, sy * k), corner, corner + Vector2(sx * k, 0)]), col, 1.0)


## The bottom part: the selected skill's name, what it does, and whether you
## can buy it. Then the keys and a small key to the three colours.
func _draw_info(font: Font) -> void:
	board.draw_rect(Rect2(28, 182, 424, 1), DIM.darkened(0.4))
	var s := SkillManager.get_skill(_sel)
	if s:
		_text(font, Vector2(30, 198), s.display_name, AMBER)
		var status := ""
		var col := PHOSPHOR
		match SkillManager.state(s.id):
			SkillManager.State.UNLOCKED:
				status = "UNLOCKED"
			SkillManager.State.AVAILABLE:
				var pts := "%d POINT%s" % [s.cost, "" if s.cost == 1 else "S"]
				if SkillManager.can_unlock(s.id):
					status = "[E] UNLOCK FOR " + pts
					col = AMBER
				else:
					status = "NEEDS " + pts
					col = AMBER.darkened(0.45)
			_:
				var p := SkillManager.get_skill(s.parent_id)
				status = "NEEDS %s FIRST" % (p.display_name if p else s.parent_id)
				col = LOCKED_INK
		_text(font, Vector2(450, 198), status, col, 16, HORIZONTAL_ALIGNMENT_RIGHT)
		board.draw_multiline_string(font, Vector2(30, 214), s.description, HORIZONTAL_ALIGNMENT_LEFT, 420, 16, 2, PHOSPHOR)
	_text(font, Vector2(30, 251), "[E] UNLOCK   [T] BACK", DIM)
	var x := 236.0
	for item in [["LOCKED", LOCKED_INK, false], ["AVAILABLE", AMBER, false], ["UNLOCKED", PHOSPHOR, true]]:
		var r := Rect2(x, 242, 8, 8)
		if item[2]:
			board.draw_rect(r, item[1])
		else:
			board.draw_rect(r, item[1], false, 1.0)
		_text(font, Vector2(x + 11, 251), item[0], item[1])
		x += 16.0 + font.get_string_size(item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x


## Text at `at` (the baseline). CENTER / RIGHT align it around / up to at.x.
func _text(font: Font, at: Vector2, text: String, col: Color, size := 16, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := at.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= roundf(w * 0.5)
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	board.draw_string(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
