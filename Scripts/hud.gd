# ---------------------------------------------------------------------------
# hud.gd: everything drawn on top of the game.
#
# The console: a metal dashboard along the bottom of the screen (like the status
# bar in old console games). The game is shown above it (level.gd moves the
# camera up by CONSOLE_H/2), so nothing in the console ever covers the room.
#   left:   PIP's little CRT face and his speech. When he's quiet, the current
#           tutorial instruction (the "objective") is shown there instead.
#   right:  the ship power meter (one LED per goal), the power cell counter, and
#           the oxygen meter on spacewalks (or key reminders inside the ship).
# Also: the wire timer (a small LED bar floating above the astronaut's head, so
# you don't have to look away), the tutorial arrow, short "toast" messages at
# the top (room names, "ZAP"...), the white flash / black fade, the results
# screen with stars, the pause menu, the wire upgrade panel (upgrade_panel.gd), and
# the black film bar of the cutscenes.
#
# Buttons: the menus use real Buttons (their look comes from the project theme,
# Assets/ui/theme.tres). Two of them sit in the top right corner the whole
# time: UPGRADE opens the wire upgrade and MENU pauses. U also opens the
# tree at any moment. You can click a button, or pick it with the arrow keys
# and press E, Space or Enter.
#
# It's a CanvasLayer, which means it stays still on screen while the camera
# moves. Its nodes live in hud.tscn, so open that scene to change colours and
# sizes without code. The look (dark glass panels, white text, amber accents)
# comes from the project theme (Assets/ui/theme.tres) and ui_style.gd, which
# also has the colours the code-drawn parts below use.
#
# Pausing: hud.tscn sets this node's Process Mode to "Always", so the HUD keeps
# running when the game is paused (get_tree().paused = true). That's how the
# pause menu can still react to keys while everything else is frozen.
# ---------------------------------------------------------------------------
class_name GameHUD
extends CanvasLayer

## Emitted when a speech that freezes the player starts (true) / ends (false).
signal dialogue_blocking(on: bool)
## The results screen's buttons (the level listens and loads the next scene).
signal results_next
signal results_again

## Height of the console at the bottom. level.gd keeps the room above it.
const CONSOLE_H := 48
const TYPE_SPEED := 48.0          # letters per second in the speech box
# The look: see ui_style.gd. These are the same colours as text for bbcode.
const NAME_COLOR := "#ffc24d"     # amber: who's talking
const TEXT_COLOR := "#e6f2ff"     # white: what they say
const DIM_COLOR := "#8fa8c7"      # dim blue grey: the standing objective
const GOAL_COLOR := "#66d9ff"     # cyan: the word GOAL in front of it
const AMBER := UIStyle.AMBER
const PHOSPHOR := Color(0.55, 0.95, 0.6)   # PIP's face is still a little green screen
# Level 3: when PIP malfunctions he talks as "P!P" in red, with an angry face.
const ROGUE_SPEAKER := "P!P"
const ROGUE_NAME_COLOR := "#ff5a4a"
const ROGUE_TEXT_COLOR := "#ffb09c"
const ROGUE_RED := Color(1.0, 0.33, 0.27)
const LED_OFF := UIStyle.LED_OFF        # a segment of a meter that isn't lit

@onready var toast: PanelContainer = $Toast
@onready var toast_label: Label = $Toast/Text
@onready var timer_bar: Control = $TimerBar
@onready var flash_rect: ColorRect = $Flash
@onready var fade_rect: ColorRect = $Fade
@onready var complete_panel: Control = $Complete
@onready var marker: Control = $Marker
@onready var status_box: Control = $Status
## The key reminders on the right of the console, drawn as keycaps (KeyHint).
@onready var keys_box: HBoxContainer = $Keys
@onready var dialogue: PanelContainer = $Dialogue
@onready var portrait: Control = $Dialogue/Row/Portrait
@onready var dialogue_text: RichTextLabel = $Dialogue/Row/Text
@onready var stars_box: Control = $Complete/VBox/Stars
@onready var pause_panel: Control = $Pause
@onready var pause_level: Label = $Pause/VBox/Level
@onready var bar_top: ColorRect = $BarTop
@onready var corner_upgrade: Button = $Corner/Upgrade
@onready var corner_menu: Button = $Corner/Menu
## The E key that bobs just under PIP's little screen when you have to press E
## to go on (never on top of the text). It's its own node in hud.tscn: move it
## there to put it somewhere else.
@onready var next_key: Control = $NextKey

## The level sets this to false on the results screen.
var allow_pause := true
## The level sets this: asked right before a speech freezes the player
## ("is that OK right now?", and it isn't while he's carrying the wire).
var can_block: Callable

var _battery_chip: Control           # the battery counter, top right (_draw_battery_chip)
var _shown_batteries := 0
var _chip_bump := 0.0                # it hops when the count changes
var _frac := 1.0
var _secs := 0.0
var _cap := 0.0                     # the most the wire timer holds (sets the bar's length)
const TIMER_PX := 8.0               # game pixels of wire bar per second
const TIMER_GAP := 1.5              # the gap between two of its lamps
var _paused := false
var _pulse := 0.0
var _toast_token := 0
var _marker_on := false
var _marker_world := Vector2.ZERO   # where the arrow points, in level (world) pixels
var _objective := ""                # the tutorial instruction, shown when PIP is quiet
var _cinematic := false             # a cutscene is playing (film bar on)
var _reel_prompt := false           # show the [E] "reel back" key above the astronaut
var _node_prompt := Vector2.INF     # a node waiting for E: the key bobs over it (world position)
var _cut_prompt := Vector2.INF      # a lit goal you can cut by holding E (world position)
var _cut_progress := 0.0            # 0..1 while E is held there
var _restart_prompt := false        # show the [R] key: no safe way back to the START
var _hint_on := false               # this room has an H hint
var _t := 0.0

# console meters
var _power_on := 0
var _power_total := 0
var _power_flash := 0.0
var _o2_on := false
var _o2_frac := 1.0
var _cells := 0
var _cells_total := 0
var _cell_bump := 0.0
var _fuses := 0                     # fuses you carry (dungeon levels)
var _clamp := false                 # you carry the cable clamp
var _map_ok := false                # this level has a map worth looking at (M)
var _judge := false                 # judge mode: R makes PIP walk the room

# the ship map (ship_map.gd, made in _ready)
var ship_map: ShipMap
var _map_paused_before := false

# speech
var _queue: Array = []            # waiting speeches: [lines, speaker, blocking, point_at]
var _talking := false
var _blocking := false
var _typing := false
var _waiting_key := false
var _skip_line := false           # cut the current (non-blocking) line short...
var _cut_speech := false          # ...and skip the rest of that speech
var _line_bbcode := ""
var _speech_point := Vector2.INF  # PIP's blue arrow points here while he talks (INF = no arrow)
var _rogue := false               # PIP has malfunctioned: his face is red when he's quiet
var _line_rogue := false          # the line on screen is said by the malfunctioning PIP

# results screen
var _stars_earned := 0
var _stars_shown := 0

# the wire upgrade panel (upgrade_panel.gd, made in _ready)
var upgrade_panel: UpgradePanel
var _upgrade_badge: Control           # the dot on UPGRADE when you can afford one (_draw_upgrade_badge)
var _badge_ping := 0.0              # seconds left of the dot's "look at me" ping
var _upgrade_from_pause := false    # opened from the pause menu (go back to it on close)
var _upgrade_from_results := false  # opened from the results screen (show it again on close)
var _paused_before := false         # was the game paused before the panel opened?
var _base_wire := 3.0               # the level's wire_time (the upgrade panel shows what it becomes)

var _keys_shown := []              # the key reminders on screen now (so we only rebuild them when they change)
var _sfx := {}


func _ready() -> void:
	# The timer, status, portrait and stars have no picture: our own functions
	# draw them (see the _draw_... functions below).
	timer_bar.draw.connect(_draw_timer)
	marker.draw.connect(_draw_marker)
	status_box.draw.connect(_draw_status)
	portrait.draw.connect(_draw_portrait)
	stars_box.draw.connect(_draw_stars)
	next_key.draw.connect(_draw_next_key)
	# PIP's text size depends on the font (OpenDyslexic is wider, see Game.console_font_size)
	_fit_console_font()
	Game.font_changed.connect(_fit_console_font)
	Game.font_changed.connect(func() -> void:     # code-drawn text changes size with the font
		_update_corner()
		_keys_shown = []
		_update_keys())
	timer_bar.visible = false
	complete_panel.visible = false
	toast.visible = false
	pause_panel.visible = false
	flash_rect.color.a = 0.0
	fade_rect.color.a = 0.0
	bar_top.visible = false
	bar_top.position.y = -bar_top.size.y        # the film bar waits just above the screen
	upgrade_panel = UpgradePanel.new()
	add_child(upgrade_panel)
	upgrade_panel.closed.connect(_on_upgrade_closed)
	ship_map = ShipMap.new()
	add_child(ship_map)
	ship_map.closed.connect(_on_map_closed)
	# what each button does
	$Pause/VBox/Buttons/Resume.pressed.connect(_set_paused.bind(false))
	$Pause/VBox/Buttons/Upgrade.pressed.connect(open_upgrade)
	$Pause/VBox/Buttons/Quit.pressed.connect(Game.go_to_title)
	# the DYSLEXIA FONT switch (Game.set_dyslexic_font), at the bottom of the pause menu
	var font_switch := Button.new()
	font_switch.add_theme_font_size_override("font_size", UIStyle.SMALL + 1)
	font_switch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	font_switch.text = Game.font_switch_text()
	font_switch.pressed.connect(func() -> void:
		Game.set_dyslexic_font(not Game.dyslexic_font)
		font_switch.text = Game.font_switch_text())
	$Pause/VBox.add_child(font_switch)
	$Complete/VBox/Buttons/Next.pressed.connect(results_next.emit)
	$Complete/VBox/Buttons/Again.pressed.connect(results_again.emit)
	$Complete/VBox/Buttons/Upgrade.pressed.connect(open_upgrade)
	corner_upgrade.pressed.connect(open_upgrade)
	corner_menu.pressed.connect(func() -> void: _set_paused(not pause_panel.visible))
	Game.batteries_changed.connect(_update_corner)
	# Your batteries, top right next to UPGRADE: an amber pill with the battery icon
	_battery_chip = Control.new()
	_battery_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_battery_chip.draw.connect(_draw_battery_chip)
	corner_upgrade.get_parent().add_child(_battery_chip)
	corner_upgrade.get_parent().move_child(_battery_chip, 0)
	_shown_batteries = Game.batteries
	_update_corner()
	# The notification dot on UPGRADE: it shows while you have enough batteries
	# for the next upgrade. It pings for a while (when a level starts), and stops
	# pinging once you open the panel.
	_upgrade_badge = Control.new()
	_upgrade_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_upgrade_badge.size = Vector2(12, 12)
	corner_upgrade.add_child(_upgrade_badge)
	_upgrade_badge.draw.connect(_draw_upgrade_badge)
	if _can_upgrade():
		_badge_ping = 6.0
	_show_idle()
	_update_keys()
	for n in ["blip", "star"]:
		var p := AudioStreamPlayer.new()
		var path := "res://Assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			p.stream = load(path)
		add_child(p)
		_sfx[n] = p
	_sfx["blip"].volume_db = -10.0


func _process(delta: float) -> void:
	_t += delta
	_badge_ping = maxf(0.0, _badge_ping - delta)
	_upgrade_badge.visible = _can_upgrade()
	if _upgrade_badge.visible:
		_upgrade_badge.position = Vector2(-6.0, -5.0)   # its top left corner (the right one is at the screen's edge)
		_upgrade_badge.queue_redraw()
	_pulse = maxf(0.0, _pulse - delta * 2.5)
	if _chip_bump > 0.0:
		_chip_bump = maxf(0.0, _chip_bump - delta * 3.0)
		_battery_chip.queue_redraw()
	_power_flash = maxf(0.0, _power_flash - delta)
	_cell_bump = maxf(0.0, _cell_bump - delta * 3.0)
	marker.queue_redraw()          # the arrows bob, and the camera moves, so redraw every frame
	status_box.queue_redraw()
	portrait.queue_redraw()
	if timer_bar.visible:
		# the timer floats above the astronaut's head
		timer_bar.position = (_player_on_screen() + Vector2(-timer_bar.size.x * 0.5, -54)).round()
		timer_bar.queue_redraw()
	if complete_panel.visible:
		stars_box.queue_redraw()
	next_key.visible = _waiting_key
	if _waiting_key:
		next_key.queue_redraw()        # it bobs
	# MENU only shows when pausing is allowed (not in cutscenes or on the results)
	corner_menu.visible = allow_pause
	# While a menu is open (pause, upgrade, map, results) the corner buttons and
	# the popup at the top step aside, so nothing overlaps the menu.
	var menu_open := pause_panel.visible or upgrade_panel.visible or ship_map.visible or complete_panel.visible
	corner_menu.get_parent().visible = not menu_open
	if menu_open and toast.visible:
		toast.visible = false
	# (not while the upgrade panel is open, or on the frame its Esc closed it)
	var tree_busy := upgrade_panel.visible or upgrade_panel.closed_frame == Engine.get_process_frames()
	var map_busy := ship_map.visible or ship_map.closed_frame == Engine.get_process_frames()
	if Input.is_action_just_pressed("pause") and allow_pause and not tree_busy and not map_busy:
		_set_paused(not get_tree().paused)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).physical_keycode
	if key == KEY_U:
		open_upgrade()               # any time at all
	elif key == KEY_M and _map_ok:
		open_map()
	elif key == KEY_Q and pause_panel.visible:
		Game.go_to_title()


func _set_paused(on: bool) -> void:
	pause_panel.visible = on
	if on:
		pause_panel.modulate.a = 0.0
		create_tween().tween_property(pause_panel, "modulate:a", 1.0, 0.15)
		get_tree().paused = true
		_update_pause_upgrade()
		$Pause/VBox/Buttons/Resume.grab_focus()     # so the keys can pick a button straight away
	else:
		# Unpause at the end of this frame, not right now: if E pressed RESUME,
		# the level would otherwise see that same E and grab the wire too.
		get_tree().set_deferred("paused", false)


## The line on the pause menu about the wire upgrade and your batteries.
func _update_pause_upgrade() -> void:
	$Pause/VBox/Suit.text = "WIRE UPGRADES %d/%d   |   %d BATTER%s" % [Game.wire_upgrades,
		Game.UPGRADE_COSTS.size(), Game.batteries, "Y" if Game.batteries == 1 else "IES"]


# ------------------------------------------------------------------ the wire upgrade

## The level tells the HUD its wire_time, so the upgrade panel can show what
## the timer is now and what it would be.
func set_base_wire(secs: float) -> void:
	_base_wire = secs


## Opens the wire upgrade panel (upgrade_panel.gd) and pauses the game until
## it closes. Works at any moment, except while the screen is fading out.
func open_upgrade(gained := 0) -> void:
	if upgrade_panel.visible or fade_rect.color.a > 0.5:
		return
	_upgrade_from_pause = pause_panel.visible
	_upgrade_from_results = complete_panel.visible
	_paused_before = get_tree().paused
	pause_panel.visible = false
	complete_panel.visible = false      # one menu at a time: it takes the results' place
	get_tree().paused = true
	_badge_ping = 0.0                   # you've seen it: the dot stops pinging
	upgrade_panel.open(_base_wire, gained)


## The end of a room: the level waits here while the panel is open.
## gained = batteries that room paid out.
func offer_upgrade(gained: int, base_wire: float) -> void:
	_base_wire = base_wire
	open_upgrade(gained)
	if upgrade_panel.visible:
		await upgrade_panel.closed


func is_upgrade_open() -> bool:
	return upgrade_panel.visible


# ------------------------------------------------------------------ ship map

## The level has a map worth opening (halls, fuse doors...): M works, and the
## console's key reminders show it.
func set_map_available(on: bool) -> void:
	_map_ok = on
	_update_keys()


## Opens PIP's deck map (ship_map.gd) and pauses the game until it closes.
func open_map() -> void:
	if ship_map.visible or upgrade_panel.visible or pause_panel.visible or fade_rect.color.a > 0.5 or _cinematic:
		return
	var lv := get_tree().get_first_node_in_group("level")
	if lv == null or not lv.has_method("map_info"):
		return
	_map_paused_before = get_tree().paused
	get_tree().paused = true
	ship_map.open(lv.map_info())


func _on_map_closed() -> void:
	if not _map_paused_before:
		get_tree().set_deferred("paused", false)    # (deferred: see _set_paused)


## Judge mode on: the console shows R as "PIP does it" (autopilot.gd).
func set_judge(on: bool) -> void:
	_judge = on
	_update_keys()


func set_fuses(n: int) -> void:
	_fuses = n


func set_clamp(on: bool) -> void:
	_clamp = on


func _on_upgrade_closed() -> void:
	if _upgrade_from_pause:
		pause_panel.visible = true        # back to the pause menu, still paused
		_update_pause_upgrade()
		$Pause/VBox/Buttons/Upgrade.grab_focus()
	elif _upgrade_from_results:
		complete_panel.visible = true     # back to the results screen
		$Complete/VBox/Buttons/Upgrade.grab_focus()
		if not _paused_before:
			get_tree().set_deferred("paused", false)
	elif not _paused_before:
		get_tree().set_deferred("paused", false)   # back to the game (see _set_paused)
	_update_points_line()


## You have enough batteries for the next wire upgrade.
func _can_upgrade() -> bool:
	return Game.can_upgrade()


## The notification dot: an amber dot with a "!", and while it's pinging, a
## ring that grows out of it and fades, over and over (like a radar ping).
func _draw_upgrade_badge() -> void:
	var c := Vector2(6, 6)
	if _badge_ping > 0.0:
		var k := fmod(_t * 1.4, 1.0)
		_upgrade_badge.draw_arc(c, 5.0 + k * 7.0, 0.0, TAU, 24, Color(AMBER, 0.9 * (1.0 - k)), 1.0)
	_upgrade_badge.draw_circle(c, 5.0, AMBER)
	UIStyle.text(_upgrade_badge, c + Vector2(0, 2.5), "!", Color(0.05, 0.07, 0.1), 7, HORIZONTAL_ALIGNMENT_CENTER)


## The UPGRADE button in the corner: your batteries, and amber when you can buy.
func _update_corner() -> void:
	corner_upgrade.text = "UPGRADE"
	if Game.batteries != _shown_batteries:
		_shown_batteries = Game.batteries
		_chip_bump = 1.0                # the count changed: the pill hops
	_battery_chip.custom_minimum_size = Vector2(UIStyle.text_width(str(Game.batteries), UIStyle.SMALL + 1) + 26.0, 0.0)
	_battery_chip.queue_redraw()
	if Game.can_upgrade():
		corner_upgrade.add_theme_color_override("font_color", AMBER)
	else:
		corner_upgrade.remove_theme_color_override("font_color")


## The battery counter in the top right corner: how many batteries you have
## to spend (Game.batteries), on an amber pill with the battery icon.
func _draw_battery_chip() -> void:
	var r := Rect2(Vector2(0, -roundf(_chip_bump * 2.0)), _battery_chip.size)
	var edge := AMBER.lerp(Color.WHITE, _chip_bump)
	UIStyle.draw_box(_battery_chip, r, Color(0.03, 0.055, 0.09, 0.9), Color(edge, 0.75), 7)
	PowerCell.draw_battery(_battery_chip, r.position + Vector2(6, (r.size.y - 15.0) * 0.5), AMBER, Color(0.4, 0.25, 0.02))
	UIStyle.text(_battery_chip, r.position + Vector2(18, r.size.y * 0.5 + 3.0), str(Game.batteries), edge, UIStyle.SMALL + 1)


## The pause menu shows which level you're on.
func set_level_info(text: String) -> void:
	pause_level.text = text


## Where the player is on the screen (the HUD doesn't move with the camera).
func _player_on_screen() -> Vector2:
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p == null:
		return Vector2(-1000, -1000)
	return get_viewport().get_canvas_transform() * p.global_position


# ------------------------------------------------------------------ tutorial objective

## The current tutorial instruction, shown in the console whenever PIP isn't
## talking, and (optionally) an arrow pointing at `world_pos`. "" clears both.
func set_objective(text: String, world_pos: Vector2, arrow: bool) -> void:
	_objective = text
	_marker_world = world_pos
	_marker_on = arrow and text != ""
	if not _talking:
		_show_idle()
		if text != "":
			dialogue.modulate = Color(1.8, 1.8, 1.8)    # flash bright, then settle
			create_tween().tween_property(dialogue, "modulate", Color.WHITE, 0.4)


## The console's text when PIP is quiet: the objective, dimmed.
func _show_idle() -> void:
	_line_bbcode = ""
	dialogue_text.visible_characters = -1
	dialogue_text.text = ("[color=%s]GOAL[/color]  [color=%s]%s[/color]" % [GOAL_COLOR, DIM_COLOR, _objective]) if _objective != "" else ""


## Draws the arrows: the yellow tutorial arrow, PIP's blue one while he points
## at something, and the [E] key above the astronaut when he can reel back.
## The HUD is on its own layer that doesn't move with the camera, so each world
## position is converted into a screen position first.
func _draw_marker() -> void:
	if _marker_on:
		_draw_arrow(_marker_world, Color(1.0, 0.85, 0.3), Color(0.15, 0.08, 0.0))
	if _speech_point.is_finite():
		_draw_arrow(_speech_point, Color(0.5, 0.9, 1.0), Color(0.0, 0.1, 0.18))
	if _reel_prompt and not _cinematic:
		_draw_key(_player_on_screen() + Vector2(16, -58 + roundf(sin(_t * 5.0))), "E")
	if _node_prompt.is_finite() and not _cinematic:
		# over the node you're standing on: press E to wrap the wire round it
		var at: Vector2 = get_viewport().get_canvas_transform() * _node_prompt
		_draw_key(at + Vector2(18, -26 + roundf(sin(_t * 6.0) * 1.5)), "E")
	if _restart_prompt and not _cinematic:
		_draw_key(_player_on_screen() + Vector2(0, -48 + roundf(sin(_t * 5.0))), "R")
	if _cut_prompt.is_finite() and not _cinematic:
		# over a lit goal: hold E to cut its power. A red ring fills while you hold.
		var at: Vector2 = get_viewport().get_canvas_transform() * _cut_prompt + Vector2(0, -28)
		marker.draw_arc(at, 10.0, 0.0, TAU, 32, Color(UIStyle.RED, 0.3), 2.0)
		if _cut_progress > 0.0:
			marker.draw_arc(at, 10.0, -PI / 2.0, -PI / 2.0 + TAU * _cut_progress, 32, UIStyle.RED, 2.0)
		_draw_key(at, "E")


func _draw_arrow(world: Vector2, col: Color, dark: Color) -> void:
	var screen := get_viewport().get_canvas_transform() * world
	var view := marker.size - Vector2(0, CONSOLE_H)            # the room is above the console
	var margin := 14.0
	var inside := Rect2(Vector2(margin, margin + 24), view - Vector2(margin * 2, margin * 2 + 24))
	if inside.has_point(screen):
		# on screen: a bouncing arrow pointing down at the spot
		var tip := screen + Vector2(0, -20 - roundf(absf(sin(_t * 5.0)) * 6.0))
		var tri := PackedVector2Array([tip, tip + Vector2(-7, -9), tip + Vector2(-3, -9),
			tip + Vector2(-3, -16), tip + Vector2(3, -16), tip + Vector2(3, -9), tip + Vector2(7, -9)])
		marker.draw_colored_polygon(tri, col)
		marker.draw_polyline(tri + PackedVector2Array([tip]), dark, 1.0, true)
	else:
		# off screen: stick to the screen edge and point towards it
		var p := Vector2(clampf(screen.x, inside.position.x, inside.end.x), clampf(screen.y, inside.position.y, inside.end.y))
		var dir := (screen - p).normalized()
		var side := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([p + dir * 9.0, p - dir * 5.0 + side * 7.0, p - dir * 5.0 - side * 7.0])
		marker.draw_colored_polygon(tri, col)
		marker.draw_polyline(tri + PackedVector2Array([tri[0]]), dark, 1.0)


## The E key under PIP's screen: "press E to go on". It bobs up and down a
## little so the eye notices it.
func _draw_next_key() -> void:
	var bob := absf(sin(_t * 4.0)) * -2.0
	_draw_key(Vector2(6, 6 + bob), "E", next_key)


## A little keyboard key with a letter on it (centre at `at`), drawn on `ci`
## (the arrow layer unless you say otherwise). The look is in ui_style.gd.
func _draw_key(at: Vector2, letter: String, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = marker
	var w := UIStyle.key_width(letter)
	UIStyle.draw_key(ci, at - Vector2(w, UIStyle.KEY_H) * 0.5, letter)


## While he holds the wire and stands still away from the last pad: show the
## [E] key ("you can reel back"), and say so in the console's key reminders.
func set_reel_prompt(on: bool) -> void:
	if on == _reel_prompt:
		return
	_reel_prompt = on
	_update_keys()


## You're on a node with the wire: E (or a click) wraps the wire round it. An E
## key bobs next to the node, and the console says so. INF = no node.
func set_node_prompt(world: Vector2) -> void:
	if world == _node_prompt:
		return
	_node_prompt = world
	_update_keys()


## Standing on a lit goal: hold E to cut its power (and redo that room). The E
## key sits over the goal with a ring that fills as you hold. INF = none.
func set_cut_prompt(world: Vector2, progress: float) -> void:
	_cut_progress = clampf(progress, 0.0, 1.0)
	if world == _cut_prompt:
		return
	_cut_prompt = world
	_update_keys()


## PIP says the wire needs an upgrade: the corner UPGRADE button hops.
func flash_upgrade() -> void:
	corner_upgrade.pivot_offset = corner_upgrade.size * 0.5     # grow from its middle
	var tw := create_tween()
	tw.tween_property(corner_upgrade, "scale", Vector2(1.25, 1.25), 0.08)
	tw.tween_property(corner_upgrade, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK)


## Stranded after a fail (no safe way back to the START): an [R] key floats
## over the astronaut, and the console's key reminder says what it does.
func set_restart_prompt(on: bool) -> void:
	if on == _restart_prompt:
		return
	_restart_prompt = on
	_update_keys()


# ------------------------------------------------------------------ PIP's speech

## Queue up some lines for `speaker` to say. Each line is one speech bubble.
## blocking = true: the player is frozen and presses E to go through the lines
## (the level listens to dialogue_blocking). Otherwise lines go by on their own.
## point_at: a spot in the level for PIP's blue arrow while these lines play.
## Keep each line under about 80 letters: the console shows two lines of text.
func say(lines: PackedStringArray, speaker := "PIP", blocking := false, point_at := Vector2.INF) -> void:
	if lines.is_empty():
		return
	if blocking:
		# Something the player has to read (e.g. a new room's warning) jumps the queue:
		# casual chatter waiting in line is dropped, and the line on screen ends now.
		_queue = _queue.filter(func(item: Array) -> bool: return item[2])
		if _talking and not _blocking:
			_skip_line = true
			_cut_speech = true
	_queue.append([lines, speaker, blocking, point_at])
	if not _talking:
		_run_dialogue()


func is_blocking() -> bool:
	return _blocking


## Level 3: PIP has malfunctioned (on) or been rebooted (off). His face in the
## console turns red and angry. Lines said by speaker ROGUE_SPEAKER ("P!P") are
## red too; lines by "PIP" stay green (the real PIP getting a word in).
func set_rogue(on: bool) -> void:
	_rogue = on


## Is PIP saying anything right now (or about to)?
func is_talking() -> bool:
	return _talking


## Cutscene mode: a black film bar slides in at the top (the console is the
## bottom one), the arrows hide, and E skips to PIP's next line. Pausing is off
## until the cutscene ends.
func set_cinematic(on: bool) -> void:
	_cinematic = on
	allow_pause = not on
	bar_top.visible = true
	create_tween().tween_property(bar_top, "position:y", 0.0 if on else -bar_top.size.y, 0.35)
	marker.visible = not on
	if on:
		timer_bar.visible = false


## Plays everything in the queue, one line at a time. This function uses `await`
## a lot: it pauses at each await (typing, waiting for E...) and carries on later,
## while the rest of the game keeps running.
func _run_dialogue() -> void:
	_talking = true
	while not _queue.is_empty():
		var item: Array = _queue.pop_front()
		var blocking: bool = item[2] and (not can_block.is_valid() or can_block.call())
		if blocking != _blocking:
			_blocking = blocking
			dialogue_blocking.emit(blocking)
		_cut_speech = false
		_speech_point = item[3]
		for line in item[0]:
			for page in _pages(item[1], line):
				if _cut_speech:
					break
				await _show_line(item[1], page, blocking)
				if not is_inside_tree():
					return
		_speech_point = Vector2.INF
	if _blocking:
		_blocking = false
		dialogue_blocking.emit(false)
	_talking = false
	_line_rogue = false
	_show_idle()                      # back to showing the objective


## The console has room for two rows of text, and every line should fit in them,
## so the whole line is on screen at once. (The E key sits under PIP's screen,
## not in the text, so it never adds a row.) If a line is still too long,
## it's split into "pages" here so nothing runs off the screen. But split lines
## get missed, so the editor marks those lines in red: shorten them.
func _pages(speaker: String, line: String) -> PackedStringArray:
	var font := dialogue_text.get_theme_font("normal_font")
	var fsize := dialogue_text.get_theme_font_size("normal_font_size")
	var width := maxf(dialogue_text.size.x, dialogue_text.custom_minimum_size.x) - 2.0
	var prefix := speaker + ": "
	var pages := PackedStringArray()
	var page := ""            # the words on the page we're filling
	var row := 0              # which of the two rows we're on
	var row_text := prefix    # what's on that row so far
	for word in line.split(" ", false):
		if _text_width(font, fsize, row_text + word) <= width:
			row_text += word + " "
			page = word if page == "" else page + " " + word
		elif row == 0:
			row = 1                                    # carry on in the second row
			row_text = word + " "
			page = word if page == "" else page + " " + word
		else:
			pages.append(page)                         # page full: start a new one
			row = 0
			row_text = prefix + word + " "
			page = word
	if page != "":
		pages.append(page)
	return pages


func _fit_console_font() -> void:
	dialogue_text.add_theme_font_size_override("normal_font_size", Game.console_font_size())


func _text_width(font: Font, fsize: int, text: String) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x


## Waits one frame. Returns false if the HUD left the scene meanwhile (level changed).
func _frame() -> bool:
	await get_tree().process_frame
	return is_inside_tree()


func _show_line(speaker: String, line: String, blocking: bool) -> void:
	_line_rogue = speaker == ROGUE_SPEAKER
	var name_col := ROGUE_NAME_COLOR if _line_rogue else NAME_COLOR
	var text_col := ROGUE_TEXT_COLOR if _line_rogue else TEXT_COLOR
	_line_bbcode = "[color=%s]%s:[/color] [color=%s]%s[/color]" % [name_col, speaker, text_col, line]
	dialogue_text.text = _line_bbcode
	var total := float(dialogue_text.get_total_character_count())
	var shown := float(speaker.length() + 2)
	var blips := 0
	_typing = true
	_skip_line = false
	# typewriter: reveal a few more letters every frame
	while shown < total and not _skip_line:
		if not await _frame():
			return                            # the level changed while PIP was talking
		if get_tree().paused:
			continue
		if (blocking or _cinematic) and Input.is_action_just_pressed("interact"):
			shown = total                     # E skips the typing
		else:
			shown += TYPE_SPEED * get_process_delta_time()
		dialogue_text.visible_characters = int(shown)
		if int(shown) / 3 > blips:
			blips = int(shown) / 3
			_sfx["blip"].play()
	dialogue_text.visible_characters = -1
	_typing = false
	if blocking:
		_waiting_key = true                   # an E key blinks on PIP's screen (_draw_portrait)
		_update_keys()
		if not await _frame():                # the press that finished typing doesn't count
			return
		while (not Input.is_action_just_pressed("interact") or get_tree().paused) and not _skip_line:
			if not await _frame():
				return
		_waiting_key = false
		_update_keys()
	else:
		# reading time grows with the length of the line (and stops while paused).
		# In a cutscene the pictures move on by themselves, so lines go a bit
		# quicker, and E skips to the next one.
		var wait := 1.6 + line.length() * 0.04
		if _cinematic:
			wait = 1.0 + line.length() * 0.03
		while wait > 0.0 and not _skip_line:
			if not await _frame():
				return
			if _cinematic and Input.is_action_just_pressed("interact"):
				break
			if not get_tree().paused:
				wait -= get_process_delta_time()
	_skip_line = false


## PIP's face: a little green CRT monitor in a metal case. Two eyes that blink,
## a mouth that moves while talking, and dark scanlines across the glass.
## When he's quiet the screen is dimmer.
## Malfunctioning (Level 3): a red screen, slanted angry eyes, and now and then
## a "glitch" that shifts the face sideways and draws a bright bar across it.
func _draw_portrait() -> void:
	var s := portrait.size
	var angry := _line_rogue if _talking else _rogue
	var base := ROGUE_RED if angry else PHOSPHOR
	var ink := base if _talking else base.darkened(0.4)
	# the case: a rounded dark frame with a thin edge in his colour
	UIStyle.draw_box(portrait, Rect2(Vector2.ZERO, s), Color(0.07, 0.11, 0.17), Color(base, 0.55), 4)
	var glass := StyleBoxFlat.new()
	glass.set_corner_radius_all(3)
	glass.bg_color = Color(0.12, 0.03, 0.03) if angry else Color(0.02, 0.09, 0.06)
	portrait.draw_style_box(glass, Rect2(Vector2(2, 2), s - Vector2(4, 4)))
	var glitch := angry and fmod(_t * 7.0, 5.0) < 0.6       # a short burst every so often
	var o := Vector2(signf(sin(_t * 40.0)) if glitch else 0.0, 0.0)
	var blink := fmod(_t, 3.2) < 0.12 and not angry
	for x in [8.0, 16.0]:
		if blink:
			portrait.draw_rect(Rect2(o + Vector2(x, 12), Vector2(4, 1)), ink)
		elif angry:
			# slanted eyes: high at the outside edge, low by the nose = a frown
			var inner := 3.0 if x < 12.0 else 0.0
			for k in 4:
				var drop := absf(k - inner)
				portrait.draw_rect(Rect2(o + Vector2(x + k, 9 + drop * 0.5), Vector2(1, 4)), ink)
		else:
			var eye := StyleBoxFlat.new()
			eye.set_corner_radius_all(2)
			eye.bg_color = ink
			portrait.draw_style_box(eye, Rect2(o + Vector2(x, 8.5), Vector2(4, 5.5)))
			portrait.draw_rect(Rect2(o + Vector2(x + 2.3, 9.5), Vector2(1, 1.5)), ink.lightened(0.7))
	var mouth := 1.0
	if _typing:
		mouth = 1.0 + float(int(_t * 14.0) % 3)
	portrait.draw_rect(Rect2(o + Vector2(10, 18), Vector2(8, mouth)), ink)
	if glitch:
		var y := 4.0 + float(int(_t * 23.0) % int(s.y - 8.0))
		portrait.draw_rect(Rect2(2, y, s.x - 4, 1), ink.lightened(0.5))
	# a soft shine across the top of the glass
	portrait.draw_rect(Rect2(4, 3, s.x - 8, 1), Color(1, 1, 1, 0.08))
	var tip := AMBER if fmod(_t, 1.0) < 0.5 else Color(0.5, 0.3, 0.1)
	portrait.draw_circle(Vector2(s.x - 4.5, 4.5), 1.0, tip)                              # status light


# ------------------------------------------------------------------ toast

## Shows a short message at the top for `seconds`, then fades it out.
## The "token" trick: every new toast gets a new number. When an old toast's
## wait finishes, it checks the number. If a newer toast arrived meanwhile,
## it leaves that one alone instead of hiding it.
func show_toast(text: String, seconds := 2.0) -> void:
	if not is_inside_tree():
		return                        # the level was closed (a coroutine woke up late)
	_toast_token += 1
	var token := _toast_token
	toast_label.text = text
	toast.reset_size()
	toast.position.x = (get_viewport().get_visible_rect().size.x - toast.size.x) * 0.5
	toast.visible = true
	# it slides down into place as it fades in
	toast.modulate.a = 0.0
	toast.position.y = 0.0
	var tin := create_tween().set_parallel(true)
	tin.tween_property(toast, "modulate:a", 1.0, 0.18)
	tin.tween_property(toast, "position:y", 6.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(seconds).timeout
	if token != _toast_token or not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 0.0, 0.4)
	await tw.finished
	if token == _toast_token:
		toast.visible = false


# ------------------------------------------------------------------ the wire timer (above his head)

## The wire timer over his head. cap = the most it can hold (the START time):
## the bar gets one segment per second of it (see _draw_timer).
func set_timer(on: bool, frac: float, secs: float, paused := false, cap := 3.0) -> void:
	timer_bar.visible = on and not _cinematic
	_frac = frac
	_secs = secs
	_paused = paused
	if on and not is_equal_approx(cap, _cap):
		_cap = cap
		var n := _timer_segments()
		timer_bar.size = Vector2(n * _timer_step() * TIMER_PX + (n - 1) * TIMER_GAP + 5.0, 10.0)


## Seconds each segment of the wire bar stands for: 1, or 2 once the cap is
## over 5 s (so a big wire doesn't turn into a row of tiny lamps).
func _timer_step() -> float:
	return 1.0 if _cap <= 5.5 else 2.0


func _timer_segments() -> int:
	return maxi(1, ceili(_cap / _timer_step() - 0.001))


## Flash the timer when a node or a power cell refills it.
func pulse_timer() -> void:
	_pulse = 1.0


## One segment of an LED meter: lit = its colour with a brighter top row (like a
## little glowing bulb), unlit = dark.
func _led(ci: CanvasItem, r: Rect2, lit: bool, col: Color) -> void:
	UIStyle.draw_led(ci, r, lit, col)


## The ship's lightning bolt icon, 8 x 13 pixels, top-left corner at `b`.
func _bolt(ci: CanvasItem, b: Vector2, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([b + Vector2(5, 0), b + Vector2(1, 7), b + Vector2(4, 7),
		b + Vector2(2, 13), b + Vector2(8, 5), b + Vector2(5, 5), b + Vector2(7, 0)]), col)


## The wire bar: a tiny dark case floating above the astronaut with one lamp
## per second the wire can hold (3 s = 3 lamps; over 5 s, one lamp per 2 s), so
## a longer wire is a longer bar. The lamp you're using up drains smoothly.
## Amber, then orange, then blinking red when time is short; blue while paused.
func _draw_timer() -> void:
	var size := timer_bar.size
	UIStyle.draw_box(timer_bar, Rect2(Vector2.ZERO, size), Color(0.03, 0.055, 0.09, 0.88), Color(0.4, 0.82, 1.0, 0.35), 3)
	var col := AMBER
	if _paused:
		col = Color(0.45, 0.9, 1.0)
	elif _frac < 0.25:
		col = Color(1.0, 0.25, 0.2) if int(_t * 8.0) % 2 == 0 else Color(1.0, 0.6, 0.5)
	elif _frac < 0.5:
		col = Color(1.0, 0.55, 0.15)
	if _pulse > 0.0:
		col = col.lerp(Color.WHITE, _pulse)
	var step := _timer_step()
	for i in _timer_segments():
		var seg := minf(step, _cap - i * step)       # (the last one is shorter if the cap isn't a whole number)
		var r := Rect2(2.5 + i * (step * TIMER_PX + TIMER_GAP), 2.5, seg * TIMER_PX, size.y - 5)
		var fill := clampf((_secs - i * step) / seg, 0.0, 1.0)
		_led(timer_bar, r, false, col)
		if fill > 0.0:
			_led(timer_bar, Rect2(r.position, Vector2(maxf(1.0, r.size.x * fill), r.size.y)), true, col)


# ------------------------------------------------------------------ console meters

## How many machines have power, out of how many. One LED each.
func set_power(on: int, total: int) -> void:
	if on > _power_on:
		_power_flash = 0.8
	_power_on = on
	_power_total = total


## The oxygen gauge (only shown outside the ship). frac: 1 = full, 0 = empty.
func set_o2(visible_now: bool, frac: float) -> void:
	_o2_on = visible_now
	_o2_frac = clampf(frac, 0.0, 1.0)
	_update_keys()


func set_cells(count: int, total: int, bump := false) -> void:
	_cells = count
	_cells_total = total
	if bump:
		_cell_bump = 1.0


## Key reminder in the console: [H] when this room has a hint.
func set_hint_available(on: bool) -> void:
	_hint_on = on
	_update_keys()


func _update_keys() -> void:
	var want: Array
	if _waiting_key:
		want = [["E", "next"]]
	elif _restart_prompt:
		want = [["R", "back to start"]]
	elif _node_prompt.is_finite():
		want = [["E", "connect node"]]
	elif _cut_prompt.is_finite():
		want = [["E", "hold to cut power"]]
	elif _reel_prompt:
		want = [["E", "reel back"]]
	elif _judge:
		want = [["P", "PIP does it"], ["R", "restart"]]
	elif _hint_on:
		want = [["H", "hint"], ["M", "map"] if _map_ok else ["Esc", "menu"]]
	else:
		want = [["R", "restart"], ["M", "map"] if _map_ok else ["Esc", "menu"]]
	keys_box.visible = not _o2_on or _reel_prompt or _restart_prompt or _waiting_key or _node_prompt.is_finite() \
			or _cut_prompt.is_finite()
	if want == _keys_shown:
		return
	_keys_shown = want
	for c in keys_box.get_children():
		c.queue_free()
	for k in want:
		keys_box.add_child(KeyHint.make(PackedStringArray([k[0]]), k[1], UIStyle.DIM))


## The right side of the console: ship power LEDs and the cell counter on top,
## the oxygen meter underneath while you're outside.
func _draw_status() -> void:
	# a thin divider between PIP's side and this side
	status_box.draw_rect(Rect2(-4, 2, 1, status_box.size.y - 4), Color(UIStyle.EDGE, 0.25))
	if _power_total > 0:
		var flash := _power_flash > 0.0 and int(_t * 10.0) % 2 == 0
		var ink := Color.WHITE if flash else AMBER
		_bolt(status_box, Vector2(4, 3), ink)
		var seg_w := floorf((52.0 - 2.0 * (_power_total - 1)) / _power_total)
		for i in _power_total:
			_led(status_box, Rect2(16 + i * (seg_w + 2.0), 5, seg_w, 8), i < _power_on, ink)
	if _cells_total > 0:
		var o := Vector2(74, 2 - roundf(_cell_bump * 3.0))
		PowerCell.draw_battery(status_box, o, AMBER.lerp(Color.WHITE, _cell_bump), Color(0.4, 0.25, 0.02))
		var ink2 := UIStyle.TEXT if _cells < _cells_total else AMBER
		UIStyle.text(status_box, Vector2(87, 13), "%d/%d" % [_cells, _cells_total], ink2, UIStyle.BODY)
	# dungeon things you carry: fuses (with a count) and the cable clamp
	if _fuses > 0:
		var f := Vector2(126, 3)
		status_box.draw_rect(Rect2(f, Vector2(5, 11)), Color(0.02, 0.035, 0.13))
		status_box.draw_rect(Rect2(f + Vector2(1, 1), Vector2(3, 2)), Color(0.77, 0.8, 0.86))
		status_box.draw_rect(Rect2(f + Vector2(1, 8), Vector2(3, 2)), Color(0.77, 0.8, 0.86))
		status_box.draw_rect(Rect2(f + Vector2(2, 3), Vector2(1, 5)), AMBER)
		UIStyle.text(status_box, Vector2(133, 13), str(_fuses), AMBER, UIStyle.BODY)
	if _clamp:
		var k := Vector2(148, 3)
		status_box.draw_rect(Rect2(k, Vector2(7, 11)), Color(0.02, 0.035, 0.13))
		status_box.draw_rect(Rect2(k + Vector2(1, 2), Vector2(5, 8)), Color(0.75, 0.47, 1.0))
		status_box.draw_rect(Rect2(k + Vector2(-1, 0), Vector2(9, 2)), Color(0.92, 0.85, 1.0))
	if _o2_on and not _reel_prompt and not _restart_prompt and not _waiting_key and not _node_prompt.is_finite():
		var col := UIStyle.CYAN
		if _o2_frac < 0.3:
			col = UIStyle.RED if int(_t * 6.0) % 2 == 0 else Color(1.0, 0.7, 0.6)
		UIStyle.text(status_box, Vector2(3, 35), "O2", col, UIStyle.BODY)
		var bar := Rect2(22, 28, 136, 7)
		var back := StyleBoxFlat.new()
		back.set_corner_radius_all(3)
		back.bg_color = LED_OFF
		status_box.draw_style_box(back, bar)
		if _o2_frac > 0.0:
			back.bg_color = col
			status_box.draw_style_box(back, Rect2(bar.position, Vector2(maxf(6.0, bar.size.x * _o2_frac), bar.size.y)))
			status_box.draw_rect(Rect2(bar.position + Vector2(2, 1), Vector2(maxf(2.0, bar.size.x * _o2_frac - 4.0), 1)), col.lightened(0.45))


# ------------------------------------------------------------------ screen effects

func flash(color: Color, strength := 0.8) -> void:
	flash_rect.color = Color(color, strength)
	create_tween().tween_property(flash_rect, "color:a", 0.0, 0.4)


func fade_out(duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, duration)
	await tw.finished


func fade_in(duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 0.0, duration)
	await tw.finished


# ------------------------------------------------------------------ results screen

## The level is finished: show time, cells, retries and pop in the stars one by one.
func show_summary(number: int, message: String, stats: Dictionary, has_next: bool) -> void:
	allow_pause = false
	toast.visible = false
	_queue.clear()                    # PIP stops talking: the results get the screen
	_skip_line = true
	_cut_speech = true
	_speech_point = Vector2.INF
	set_objective("", Vector2.ZERO, false)
	_show_idle()
	$Complete/VBox/Title.text = "LEVEL %d COMPLETE" % number
	$Complete/VBox/Sub.text = message
	var secs := int(stats.get("time", 0.0))
	$Complete/VBox/Stats/Time/VBox/Value.text = "%d:%02d" % [secs / 60, secs % 60]
	$Complete/VBox/Stats/Cells/VBox/Value.text = "%d/%d" % [stats.get("cells", 0), stats.get("cells_total", 0)]
	$Complete/VBox/Stats/Retries/VBox/Value.text = str(stats.get("retries", 0))
	# cells you keep also make your suit's air last longer on spacewalks
	var bonus := int(stats.get("cells", 0)) * int(Game.o2_per_cell())
	$Complete/VBox/Bonus.visible = bonus > 0 and has_next     # no spacewalks after the last level
	$Complete/VBox/Bonus.text = "Kept batteries: +%d s of oxygen" % bonus
	_update_points_line()
	$Complete/VBox/StarHelp.text = "Stars for finishing, every cell, and %d retries or fewer" % stats.get("retry_goal", 0)
	$Complete/VBox/Buttons/Next.text = "NEXT LEVEL" if has_next else "TITLE SCREEN"
	_stars_earned = int(stats.get("stars", 1))
	_stars_shown = 0
	complete_panel.visible = true
	complete_panel.pivot_offset = complete_panel.size * 0.5
	complete_panel.scale = Vector2(0.6, 0.6)
	complete_panel.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(complete_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(complete_panel, "modulate:a", 1.0, 0.25)
	await get_tree().create_timer(0.6).timeout
	if not is_inside_tree():
		return
	if not upgrade_panel.visible:
		$Complete/VBox/Buttons/Next.grab_focus()   # E / Space / Enter = next level
	for i in _stars_earned:
		_stars_shown += 1
		_sfx["star"].pitch_scale = 1.0 + i * 0.12
		_sfx["star"].play()
		await get_tree().create_timer(0.35).timeout
		if not is_inside_tree():
			return


## The results line about batteries, e.g. "7 BATTERIES TO SPEND".
func _update_points_line() -> void:
	var label: Label = $Complete/VBox/Points
	var b := Game.batteries
	label.text = "%d BATTER%s TO SPEND" % [b, "Y" if b == 1 else "IES"] if b > 0 else ""
	label.visible = label.text != ""


func _draw_stars() -> void:
	var s := stars_box.size
	for i in 3:
		var c := Vector2(s.x * 0.5 + (i - 1) * 30.0, s.y * 0.5)
		var pts := PackedVector2Array()
		for k in 10:
			var r := 12.0 if k % 2 == 0 else 5.0
			var a := -PI / 2.0 + k * PI / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		if i < _stars_shown:
			stars_box.draw_circle(c, 14.0, Color(AMBER, 0.12))                         # a soft glow behind it
			stars_box.draw_colored_polygon(pts, AMBER)
			stars_box.draw_polyline(pts + PackedVector2Array([pts[0]]), AMBER.lightened(0.4), 1.0, true)
		else:
			stars_box.draw_colored_polygon(pts, Color(0.07, 0.11, 0.17))               # an empty star
			stars_box.draw_polyline(pts + PackedVector2Array([pts[0]]), UIStyle.FAINT, 1.0, true)
