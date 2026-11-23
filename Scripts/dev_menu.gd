# ---------------------------------------------------------------------------
# dev_menu.gd: a menu for the team that jumps straight to any room of any level.
#
# Press ` (the key left of 1) or F1, anywhere: on the title screen, in a level,
# even in the pause menu. Pick a room and that level loads with you on the
# room's START pad and every room before it already powered (the same thing a
# TestStart marker does with F6, see test_start.gd). Room 1 is the normal start,
# with PIP's intro.
#
# Game (game_state.gd) only adds this menu when the game runs from the Godot
# editor (F5 / F6). Exported and web builds never have it.
#
# The list of rooms isn't typed in anywhere: the first time the menu opens it
# loads each level scene, asks it for its rooms (level.gd dev_checkpoints())
# and throws it away again. So a new room shows up here by itself.
#
# While the menu is open the scene behind it is frozen (its nodes stop
# processing), so keys pressed here never reach the level or the HUD.
# ---------------------------------------------------------------------------
extends CanvasLayer

const AMBER := UIStyle.AMBER
const DIM := UIStyle.DIM

var _root: Control             # everything the menu draws (null until it first opens)
var _first_button: Button
var _frozen: Array = []        # [node, its process_mode] pairs we switched off
var _focus_before: Control     # the button that had focus before we opened


func _ready() -> void:
	layer = 120                     # above the HUD, the skill tree and the fades
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).physical_keycode
	var is_open := _root != null and _root.visible
	if key == KEY_QUOTELEFT or key == KEY_F1:
		get_viewport().set_input_as_handled()
		if is_open:
			close()
		else:
			open()
	elif key == KEY_ESCAPE and is_open:
		get_viewport().set_input_as_handled()
		close()


func open() -> void:
	if _root == null:
		_build()
	_focus_before = get_viewport().gui_get_focus_owner()
	_freeze_scene()
	_root.visible = true
	if _first_button:
		_first_button.grab_focus()


func close() -> void:
	_root.visible = false
	# Wake the scene up at the end of this frame, not now: otherwise the HUD
	# would still see the Esc that closed us as just pressed and open the pause menu.
	_thaw_scene.call_deferred()
	if is_instance_valid(_focus_before) and _focus_before.is_visible_in_tree():
		_focus_before.grab_focus()


func _jump(level: int, room: int) -> void:
	_root.visible = false
	_frozen.clear()                 # that scene is about to be thrown away anyway
	Game.dev_jump(level, room)


# ------------------------------------------------------------------ freezing the scene

## Switches off processing for the current scene: its root, plus every node in
## it that would ignore that (like the HUD, which keeps running while paused).
func _freeze_scene() -> void:
	_frozen.clear()
	var scene := get_tree().current_scene
	if scene == null:
		return
	_frozen.append([scene, scene.process_mode])
	var stack: Array[Node] = scene.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.process_mode == Node.PROCESS_MODE_ALWAYS or n.process_mode == Node.PROCESS_MODE_WHEN_PAUSED:
			_frozen.append([n, n.process_mode])
		stack.append_array(n.get_children())
	for pair in _frozen:
		pair[0].process_mode = Node.PROCESS_MODE_DISABLED


func _thaw_scene() -> void:
	for pair in _frozen:
		if is_instance_valid(pair[0]):
			pair[0].process_mode = pair[1]
	_frozen.clear()


# ------------------------------------------------------------------ building the menu

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var shade := ColorRect.new()    # darkens the game behind, and catches stray clicks
	shade.color = Color(0, 0, 0, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.box(UIStyle.GLASS, UIStyle.EDGE, 6, 6, 9.0))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var top := HBoxContainer.new()
	box.add_child(top)
	top.add_child(_label("DEV MENU: JUMP TO A ROOM", AMBER))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.custom_minimum_size.x = 16
	top.add_child(gap)
	top.add_child(KeyHint.make(["`"], "close", DIM))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 8)
	box.add_child(columns)
	for i in Game.LEVELS.size():
		columns.add_child(_level_column(i + 1, Game.LEVELS[i]))

	box.add_child(_label("Earlier rooms start powered. Room 1 = normal start.", DIM))


## One column: the level's name, then a button per room.
func _level_column(number: int, path: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var info := _read_level(path)
	col.add_child(_label("LEVEL %d  %s" % [number, info["name"]], UIStyle.CYAN))
	# Stages of one room share a name (GENERATOR ROOM x3): add A, B, C to tell them apart.
	var count := {}
	for cp in info["rooms"]:
		count[cp[1]] = int(count.get(cp[1], 0)) + 1
	var seen := {}
	for cp in info["rooms"]:
		var title: String = cp[1]
		var text := "%d %s" % [cp[0] + 1, title]
		if count[title] > 1:
			seen[title] = int(seen.get(title, 0)) + 1
			text += " " + "ABCDEFGH"[seen[title] - 1]
		var b := Button.new()
		b.add_theme_font_size_override("font_size", UIStyle.SMALL + 1)
		b.text = text
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_jump.bind(number, cp[0]))
		col.add_child(b)
		if _first_button == null:
			_first_button = b
	return col


## Loads a level scene without starting it and asks it for its name and rooms.
func _read_level(path: String) -> Dictionary:
	var info := {"name": "?", "rooms": []}
	var packed := load(path) as PackedScene
	if packed == null:
		return info
	var level := packed.instantiate()
	if level.has_method("dev_checkpoints"):
		info["name"] = level.get("level_name")
		info["rooms"] = level.dev_checkpoints()
	level.free()
	return info


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	return l
