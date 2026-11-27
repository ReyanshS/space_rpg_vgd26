# ---------------------------------------------------------------------------
# upgrade_panel.gd: the WIRE UPGRADE screen, the game's only upgrade.
#
# Batteries are the money (Game.batteries): every power cell you keep is one.
# Each upgrade makes the wire timer 1 s bigger (Game.UPGRADE_STEP), and they
# cost 3, then 5, then 7 batteries (Game.UPGRADE_COSTS). The panel shows what
# you have, what the wire is now and what it would be, and three lamps for the
# three upgrades.
#
# It comes up by itself after every room you power (level.gd _solve ->
# hud.offer_upgrade), and any time from the UPGRADE button in the corner, the
# pause menu, the results screen, or the U key. While it's open the game is
# paused (the HUD does that).
#
# Keys: arrows pick a button, E / Space / Enter press it, U or Esc close it.
# The panel is built in code here (no scene), like the dev menu, so all of
# its look comes from ui_style.gd.
# ---------------------------------------------------------------------------
class_name UpgradePanel
extends Control

## The player closed the panel.
signal closed

## The frame (process) number when the panel last closed. The HUD checks it so
## the Esc that closes it doesn't also open the pause menu.
var closed_frame := -1

var _base_time := 3.0          # the level's wire_time (what the timer starts at with no upgrade)
var _gained := 0               # batteries the room you just powered paid out (0 = opened by hand)
var _opened_frame := -1
var _t := 0.0
var _flash := 0.0              # the moment you buy: the new lamp flashes
var _board: Control
var _buy: Button
var _done: Button
var _sfx := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS      # it works while the game is paused
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP     # clicks don't fall through to the game
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_board = Control.new()                       # everything that's drawn, not a button
	_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.draw.connect(_draw_board)
	add_child(_board)
	var row := HBoxContainer.new()
	row.position = Vector2(150, 192)
	row.size = Vector2(180, 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_buy = Button.new()
	_buy.pressed.connect(_on_buy)
	row.add_child(_buy)
	_done = Button.new()
	_done.text = "CONTINUE"
	_done.pressed.connect(close)
	row.add_child(_done)
	for n in ["powerup", "warn"]:
		var p := AudioStreamPlayer.new()
		var path := "res://Assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			p.stream = load(path)
		add_child(p)
		_sfx[n] = p


## Opens the panel. base_time = the level's wire_time; gained = batteries the
## room you just powered paid out (shown at the top), 0 when opened by hand.
func open(base_time: float, gained := 0) -> void:
	_base_time = base_time
	_gained = gained
	_opened_frame = Engine.get_process_frames()
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	_refresh()
	# the useful button has the focus, so E does the right thing straight away
	if Game.can_upgrade():
		_buy.grab_focus()
	else:
		_done.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_flash = maxf(0.0, _flash - delta * 2.0)
	_board.queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if Engine.get_process_frames() == _opened_frame:
		return                                    # the key that opened it doesn't count
	var key := (event as InputEventKey).physical_keycode
	if key == KEY_U or key == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func _on_buy() -> void:
	if Game.buy_upgrade():
		_flash = 1.0
		_sfx["powerup"].play()
	else:
		_sfx["warn"].play()
	_refresh()
	if not Game.can_upgrade():
		_done.grab_focus()


func _refresh() -> void:
	var cost := Game.upgrade_cost()
	if cost < 0:
		_buy.text = "ALL UPGRADES BOUGHT"
		_buy.disabled = true
	else:
		_buy.text = "UPGRADE  (%d)" % cost
		_buy.disabled = not Game.can_upgrade()
	_board.queue_redraw()


func _draw_board() -> void:
	var panel := Rect2(110, 48, 260, 170)
	UIStyle.draw_box(_board, panel, UIStyle.GLASS, UIStyle.EDGE, 6)
	var mid := panel.get_center().x
	UIStyle.text(_board, Vector2(mid, panel.position.y + 22), "WIRE UPGRADE", UIStyle.TEXT, UIStyle.HEAD, HORIZONTAL_ALIGNMENT_CENTER)
	# batteries you have, in an amber badge (and how many the last room gave you)
	var have := "%d BATTER%s" % [Game.batteries, "Y" if Game.batteries == 1 else "IES"]
	var w := UIStyle.text_width(have, UIStyle.BODY) + 26.0
	var badge := Rect2(mid - w * 0.5, panel.position.y + 30, w, 15)
	UIStyle.draw_box(_board, badge, Color(UIStyle.AMBER, 0.14), Color(UIStyle.AMBER, 0.8), 7)
	PowerCell.draw_battery(_board, badge.position + Vector2(5, 1.5), UIStyle.AMBER, Color(0.4, 0.25, 0.02))
	UIStyle.text(_board, Vector2(badge.position.x + 17, badge.position.y + 11), have, UIStyle.AMBER, UIStyle.BODY)
	if _gained > 0:
		UIStyle.text(_board, Vector2(mid, panel.position.y + 57), "+%d from that room" % _gained, UIStyle.GREEN,
			UIStyle.SMALL + 1, HORIZONTAL_ALIGNMENT_CENTER)
	# the wire now -> the wire after the next upgrade
	var now := _base_time + Game.wire_bonus()
	var y := panel.position.y + 84
	UIStyle.text(_board, Vector2(mid, y - 12), "WIRE TIMER", UIStyle.DIM, UIStyle.SMALL + 1, HORIZONTAL_ALIGNMENT_CENTER)
	if Game.upgrade_cost() > 0:
		UIStyle.text(_board, Vector2(mid - 30, y + 6), "%.1f s" % now, UIStyle.TEXT, UIStyle.HEAD, HORIZONTAL_ALIGNMENT_CENTER)
		UIStyle.text(_board, Vector2(mid, y + 5), ">", UIStyle.DIM, UIStyle.BODY, HORIZONTAL_ALIGNMENT_CENTER)
		UIStyle.text(_board, Vector2(mid + 30, y + 6), "%.1f s" % (now + Game.UPGRADE_STEP), UIStyle.GREEN, UIStyle.HEAD, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		UIStyle.text(_board, Vector2(mid, y + 6), "%.1f s" % now, UIStyle.GREEN, UIStyle.HEAD, HORIZONTAL_ALIGNMENT_CENTER)
	# one lamp per upgrade: lit = bought (the one you just bought flashes white)
	var n := Game.UPGRADE_COSTS.size()
	var lamp_w := 34.0
	var x0 := mid - (n * lamp_w + (n - 1) * 6.0) * 0.5
	for i in n:
		var r := Rect2(x0 + i * (lamp_w + 6.0), y + 16, lamp_w, 7)
		var lit := i < Game.wire_upgrades
		var col := UIStyle.GREEN
		if lit and i == Game.wire_upgrades - 1:
			col = col.lerp(Color.WHITE, _flash)
		UIStyle.draw_led(_board, r, lit, col)
		UIStyle.text(_board, Vector2(r.get_center().x, r.end.y + 9), str(Game.UPGRADE_COSTS[i]), UIStyle.AMBER if not lit else UIStyle.FAINT,
			UIStyle.SMALL, HORIZONTAL_ALIGNMENT_CENTER)
	# what to do
	var cost := Game.upgrade_cost()
	var tip := ""
	if cost < 0:
		tip = "Your wire is as long as it gets."
	elif Game.batteries >= cost:
		tip = "+%.1f s on the wire for %d batteries." % [Game.UPGRADE_STEP, cost]
	else:
		tip = "%d more batter%s for the next one." % [cost - Game.batteries, "y" if cost - Game.batteries == 1 else "ies"]
	UIStyle.text(_board, Vector2(mid, y + 46), tip, UIStyle.DIM, UIStyle.SMALL + 1, HORIZONTAL_ALIGNMENT_CENTER)
	UIStyle.text(_board, Vector2(panel.end.x - 8, panel.end.y - 6), "U  close", UIStyle.FAINT, UIStyle.SMALL, HORIZONTAL_ALIGNMENT_RIGHT)
