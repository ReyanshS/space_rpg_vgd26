# ---------------------------------------------------------------------------
# hud.gd  -  everything drawn on top of the game: the tutorial OBJECTIVE box and
# its bouncing ARROW, the small "toast" message (room names, ZAP!, ...), the
# 5-second timer bar, the white flash / black fade, PIP's SPEECH box, the ship
# POWER meter, the POWER CELL counter, the OXYGEN gauge (spacewalks only), the
# RESULTS screen with stars, the PAUSE menu, and the black film bars that slide
# in during a cutscene (set_cinematic).
#
# It's a CanvasLayer, which means it stays still on screen while the camera
# moves. Its nodes (Toast, TimerBar, Dialogue...) live in hud.tscn - open that
# scene to change colours and sizes without code. All text uses the project theme
# (Assets/ui/theme.tres -> the m6x11 pixel font at size 16).
#
# PAUSING: hud.tscn sets this node's Process Mode to "Always", so the HUD keeps
# running when the game is paused (get_tree().paused = true) - that's how the
# pause menu can still react to keys while everything else is frozen.
# ---------------------------------------------------------------------------
class_name GameHUD
extends CanvasLayer

## Emitted when a speech box that freezes the player starts (true) / ends (false).
signal dialogue_blocking(on: bool)

const TYPE_SPEED := 48.0          # letters per second in the speech box
# The look: SHIP HARDWARE outside (riveted metal frames, Assets/ui/frame_*.png,
# drawn by tools/art_ui.py) and an old GREEN COMPUTER SCREEN inside.
const NAME_COLOR := "#ffc24d"     # amber: names, keys, headings
const TEXT_COLOR := "#a8f0a0"     # phosphor green: what PIP says
const KEY_COLOR := "#ffc24d"
const AMBER := Color(1.0, 0.76, 0.3)
const PHOSPHOR := Color(0.66, 0.94, 0.63)
const LED_OFF := Color(0.12, 0.15, 0.14)  # a segment of a meter that isn't lit

@onready var toast: PanelContainer = $Toast
@onready var toast_label: Label = $Toast/Text
@onready var timer_bar: Control = $TimerBar
@onready var flash_rect: ColorRect = $Flash
@onready var fade_rect: ColorRect = $Fade
@onready var complete_panel: Control = $Complete
@onready var objective: PanelContainer = $Objective
@onready var objective_label: Label = $Objective/Text
@onready var marker: Control = $Marker
@onready var status_box: Control = $Status
@onready var cells_box: Control = $Cells
@onready var keys_label: Label = $Keys
@onready var dialogue: PanelContainer = $Dialogue
@onready var portrait: Control = $Dialogue/Row/Portrait
@onready var dialogue_text: RichTextLabel = $Dialogue/Row/Text
@onready var stars_box: Control = $Complete/VBox/Stars
@onready var pause_panel: Control = $Pause
@onready var pause_level: Label = $Pause/VBox/Level
@onready var controls_label: Label = $Controls
@onready var bar_top: ColorRect = $BarTop
@onready var bar_bottom: ColorRect = $BarBottom

## The level sets this to false on the results screen.
var allow_pause := true
## The level sets this: asked right before a speech freezes the player
## ("is that OK right now?" - not while he's carrying the wire).
var can_block: Callable

var _frac := 1.0
var _secs := 0.0
var _paused := false
var _pulse := 0.0
var _toast_token := 0
var _marker_on := false
var _marker_world := Vector2.ZERO   # where the arrow points, in level (world) pixels
var _objective_on := false          # a tutorial instruction is showing
var _cinematic := false             # a cutscene is playing (film bars on)
var _t := 0.0

# status (top-left) and cells (top-right)
var _power_on := 0
var _power_total := 0
var _power_flash := 0.0
var _o2_on := false
var _o2_frac := 1.0
var _cells := 0
var _cells_total := 0
var _cell_bump := 0.0

# speech box
var _queue: Array = []            # waiting speeches: [lines, speaker, blocking]
var _talking := false
var _blocking := false
var _typing := false
var _waiting_key := false
var _skip_line := false           # cut the current (non-blocking) line short...
var _cut_speech := false          # ...and skip the rest of that speech
var _line_bbcode := ""
var _box_top := false             # the box sits at the top (chosen ONCE, when it appears)
var _box_alpha := 0.0             # fades the box in and out
var _see_through := 0.0           # 0..1: the player is behind the box, so it turns see-through
var _speech_point := Vector2.INF  # PIP's blue arrow points here while he talks (INF = no arrow)

# results screen
var _stars_earned := 0
var _stars_shown := 0

var _sfx := {}
var _plate: StyleBoxTexture       # riveted metal plate, for the meters drawn in code


func _ready() -> void:
	_plate = StyleBoxTexture.new()
	_plate.texture = load("res://Assets/ui/frame_plate.png")
	_plate.set_texture_margin_all(6.0)     # 9-slice: keep the 6 px riveted border as it is
	_plate.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	_plate.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	# The timer bar, status, cells, portrait and stars have no picture: our own
	# functions draw them (see the _draw_... functions below).
	timer_bar.draw.connect(_draw_timer)
	marker.draw.connect(_draw_marker)
	status_box.draw.connect(_draw_status)
	cells_box.draw.connect(_draw_cells)
	portrait.draw.connect(_draw_portrait)
	stars_box.draw.connect(_draw_stars)
	objective.visible = false
	timer_bar.visible = false
	complete_panel.visible = false
	toast.visible = false
	dialogue.visible = false
	pause_panel.visible = false
	flash_rect.color.a = 0.0
	fade_rect.color.a = 0.0
	# the film bars wait just off screen (above the top / below the bottom)
	bar_top.visible = false
	bar_bottom.visible = false
	bar_top.position.y = -bar_top.size.y
	bar_bottom.position.y = get_viewport().get_visible_rect().size.y
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
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta * 2.5)
		timer_bar.queue_redraw()
	marker.queue_redraw()          # the arrows bob, and the camera moves, so redraw every frame
	_power_flash = maxf(0.0, _power_flash - delta)
	_cell_bump = maxf(0.0, _cell_bump - delta * 3.0)
	status_box.queue_redraw()
	cells_box.queue_redraw()
	if dialogue.visible:
		portrait.queue_redraw()
		_place_dialogue(delta)
		if _waiting_key:
			var blink := int(_t * 3.0) % 2 == 0
			dialogue_text.text = _line_bbcode + ("  [color=%s][E][/color]" % KEY_COLOR if blink else "")
	if complete_panel.visible:
		stars_box.queue_redraw()
	if Input.is_action_just_pressed("pause") and allow_pause:
		_set_paused(not get_tree().paused)


func _unhandled_input(event: InputEvent) -> void:
	# Q on the pause menu = back to the title screen
	if pause_panel.visible and event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).physical_keycode == KEY_Q:
			_set_paused(false)
			Game.go_to_title()


func _set_paused(on: bool) -> void:
	get_tree().paused = on
	pause_panel.visible = on


## The pause menu shows which level you're on.
func set_level_info(text: String) -> void:
	pause_level.text = text


# ------------------------------------------------------------------ tutorial objective

## Shows the current tutorial instruction, and (optionally) an arrow pointing at
## `world_pos`. An empty text hides both.
func set_objective(text: String, world_pos: Vector2, arrow: bool) -> void:
	if text == "":
		_objective_on = false
		objective.visible = false
		_marker_on = false
		marker.queue_redraw()
		return
	_objective_on = true
	objective_label.text = "> " + text          # like a line typed on a terminal
	objective.reset_size()
	objective.visible = not _cinematic
	objective.modulate = Color(1.8, 1.8, 1.8)    # flash bright, then settle
	create_tween().tween_property(objective, "modulate", Color.WHITE, 0.4)
	_marker_world = world_pos
	_marker_on = arrow
	marker.queue_redraw()


## Draws the arrows: the yellow tutorial arrow, and PIP's blue one while he
## points at something. The HUD is on its own layer that doesn't move with the
## camera, so each world position is converted into a screen position first.
func _draw_marker() -> void:
	if _marker_on:
		_draw_arrow(_marker_world, Color(1.0, 0.85, 0.3), Color(0.15, 0.08, 0.0))
	if _speech_point.is_finite():
		_draw_arrow(_speech_point, Color(0.5, 0.9, 1.0), Color(0.0, 0.1, 0.18))


func _draw_arrow(world: Vector2, col: Color, dark: Color) -> void:
	var screen := get_viewport().get_canvas_transform() * world
	var view := marker.size
	var margin := 18.0
	var inside := Rect2(Vector2(margin, margin + 30), view - Vector2(margin * 2, margin * 2 + 30))
	if inside.has_point(screen):
		# on screen: a bouncing arrow pointing down at the spot
		var tip := screen + Vector2(0, -20 - roundf(absf(sin(_t * 5.0)) * 6.0))
		var tri := PackedVector2Array([tip, tip + Vector2(-7, -9), tip + Vector2(-3, -9),
			tip + Vector2(-3, -16), tip + Vector2(3, -16), tip + Vector2(3, -9), tip + Vector2(7, -9)])
		marker.draw_colored_polygon(tri, col)
		marker.draw_polyline(tri + PackedVector2Array([tip]), dark, 1.0)
	else:
		# off screen: stick to the screen edge and point towards it
		var p := Vector2(clampf(screen.x, inside.position.x, inside.end.x), clampf(screen.y, inside.position.y, inside.end.y))
		var dir := (screen - p).normalized()
		var side := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([p + dir * 9.0, p - dir * 5.0 + side * 7.0, p - dir * 5.0 - side * 7.0])
		marker.draw_colored_polygon(tri, col)
		marker.draw_polyline(tri + PackedVector2Array([tri[0]]), dark, 1.0)


# ------------------------------------------------------------------ PIP's speech box

## Queue up some lines for `speaker` to say. Each line is one speech bubble.
## blocking = true: the player is frozen and presses E to go through the lines
## (the level listens to dialogue_blocking). Otherwise lines go by on their own.
## point_at: a spot in the level for PIP's blue arrow while these lines play.
func say(lines: PackedStringArray, speaker := "PIP", blocking := false, point_at := Vector2.INF) -> void:
	if lines.is_empty():
		return
	if blocking:
		# Something the player MUST read (e.g. a new room's warning) jumps the queue:
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


## Is PIP saying anything right now (or about to)?
func is_talking() -> bool:
	return _talking


## Cutscene mode: black film bars slide in at the top and bottom, the objective
## box, arrows and key reminders hide, and PIP's lines appear in the bottom bar
## (E skips to his next line). Pausing is off until the cutscene ends.
func set_cinematic(on: bool) -> void:
	_cinematic = on
	allow_pause = not on
	var view := get_viewport().get_visible_rect().size
	bar_top.visible = true
	bar_bottom.visible = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(bar_top, "position:y", 0.0 if on else -bar_top.size.y, 0.35)
	tw.tween_property(bar_bottom, "position:y", view.y - bar_bottom.size.y if on else view.y, 0.35)
	objective.visible = _objective_on and not on
	marker.visible = not on
	keys_label.visible = not on
	controls_label.visible = not on
	if on:
		timer_bar.visible = false


## Where the player is on the SCREEN (the HUD doesn't move with the camera).
func _player_on_screen() -> Vector2:
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p == null:
		return Vector2(-1000, -1000)
	return get_viewport().get_canvas_transform() * p.global_position


## Called when the box appears. It picks its side NOW - the bottom, or the top
## if the player is low on the screen - and stays there until it closes.
## (It used to follow the player and jump up and down mid-sentence: hard to read.)
func _open_box() -> void:
	_box_top = not _cinematic and _player_on_screen().y > 150.0
	_see_through = 0.0
	dialogue.visible = true
	create_tween().tween_property(self, "_box_alpha", 1.0, 0.15)


## Every frame while the box is open: keep it on its side, and if the player
## walks behind it, fade it see-through so he never disappears.
func _place_dialogue(delta: float) -> void:
	var h := dialogue.size.y
	if _cinematic:
		dialogue.position.y = get_viewport().get_visible_rect().size.y - 4.0 - h   # in the bottom film bar
	elif _box_top:
		dialogue.position.y = 78.0                    # just under the toast
	else:
		dialogue.position.y = 238.0 - h               # just above the key reminders
	var body := Rect2(_player_on_screen() + Vector2(-10, -40), Vector2(20, 44))
	var behind := not _cinematic and Rect2(dialogue.position, dialogue.size).grow(2.0).intersects(body)
	_see_through = move_toward(_see_through, 1.0 if behind else 0.0, delta * 4.0)
	dialogue.modulate.a = _box_alpha * lerpf(1.0, 0.3, _see_through)


## Plays everything in the queue, one line at a time. This function uses `await`
## a lot: it pauses at each await (typing, waiting for E...) and carries on later,
## while the rest of the game keeps running.
func _run_dialogue() -> void:
	_talking = true
	while not _queue.is_empty():
		_open_box()
		while not _queue.is_empty():
			var item: Array = _queue.pop_front()
			var blocking: bool = item[2] and (not can_block.is_valid() or can_block.call())
			if blocking != _blocking:
				_blocking = blocking
				dialogue_blocking.emit(blocking)
			_cut_speech = false
			_speech_point = item[3]
			for line in item[0]:
				if _cut_speech:
					break
				await _show_line(item[1], line, blocking)
				if not is_inside_tree():
					return
			_speech_point = Vector2.INF
		if _blocking:
			_blocking = false
			dialogue_blocking.emit(false)
		if not dialogue.visible:
			break                         # hidden by the results screen
		var tw := create_tween()
		tw.tween_property(self, "_box_alpha", 0.0, 0.3)
		await tw.finished
		if not is_inside_tree():
			return
	dialogue.visible = false
	_talking = false


## Waits one frame. Returns false if the HUD left the scene meanwhile (level changed).
func _frame() -> bool:
	await get_tree().process_frame
	return is_inside_tree()


func _show_line(speaker: String, line: String, blocking: bool) -> void:
	_line_bbcode = "[color=%s]%s>[/color] [color=%s]%s[/color]" % [NAME_COLOR, speaker, TEXT_COLOR, line]
	dialogue_text.text = _line_bbcode
	dialogue.reset_size()
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
		_waiting_key = true
		if not await _frame():                # the press that finished typing doesn't count
			return
		while (not Input.is_action_just_pressed("interact") or get_tree().paused) and not _skip_line:
			if not await _frame():
				return
		_waiting_key = false
		dialogue_text.text = _line_bbcode
	else:
		# reading time grows with the length of the line (and stops while paused).
		# In a cutscene the pictures move on by themselves, so lines go a bit
		# quicker - and E skips to the next one.
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
func _draw_portrait() -> void:
	var s := portrait.size
	portrait.draw_rect(Rect2(Vector2.ZERO, s), Color(0.29, 0.32, 0.38))                  # metal case
	portrait.draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, 1)), Color(0.54, 0.58, 0.65))    # its top edge catches the light
	portrait.draw_rect(Rect2(Vector2(2, 2), s - Vector2(4, 4)), Color(0.03, 0.09, 0.05)) # the glass
	var blink := fmod(_t, 3.2) < 0.12
	for x in [8.0, 16.0]:
		if blink:
			portrait.draw_rect(Rect2(Vector2(x, 12), Vector2(4, 1)), PHOSPHOR)
		else:
			portrait.draw_rect(Rect2(Vector2(x, 9), Vector2(4, 5)), PHOSPHOR)
			portrait.draw_rect(Rect2(Vector2(x + 2, 10), Vector2(1, 2)), Color(0.9, 1.0, 0.9))
	var mouth := 1.0
	if _typing:
		mouth = 1.0 + float(int(_t * 14.0) % 3)
	portrait.draw_rect(Rect2(Vector2(10, 18), Vector2(8, mouth)), PHOSPHOR)
	for y in range(3, int(s.y) - 2, 2):
		portrait.draw_rect(Rect2(2, y, s.x - 4, 1), Color(0, 0, 0, 0.35))                # scanlines
	var tip := AMBER if fmod(_t, 1.0) < 0.5 else Color(0.5, 0.3, 0.1)
	portrait.draw_rect(Rect2(Vector2(s.x - 4, 1), Vector2(2, 1)), tip)                   # status light


# ------------------------------------------------------------------ toast

## Shows a short message at the top for `seconds`, then fades it out.
## The "token" trick: every new toast gets a new number. When an old toast's
## wait finishes, it checks the number - if a newer toast arrived meanwhile,
## it leaves that one alone instead of hiding it.
func show_toast(text: String, seconds := 2.0) -> void:
	_toast_token += 1
	var token := _toast_token
	toast_label.text = text
	toast.reset_size()
	toast.position.x = (get_viewport().get_visible_rect().size.x - toast.size.x) * 0.5
	toast.visible = true
	toast.modulate.a = 1.0
	await get_tree().create_timer(seconds).timeout
	if token != _toast_token:
		return
	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 0.0, 0.4)
	await tw.finished
	if token == _toast_token:
		toast.visible = false


# ------------------------------------------------------------------ timer

func set_timer(on: bool, frac: float, secs: float, paused := false) -> void:
	if timer_bar.visible != on:
		timer_bar.visible = on
	_frac = frac
	_secs = secs
	_paused = paused
	if on:
		timer_bar.queue_redraw()   # ask Godot to call _draw_timer again


## Flash the timer when a node refills it.
func pulse_timer() -> void:
	_pulse = 1.0


## One segment of an LED meter: lit = its colour with a brighter top row (like a
## little glowing bulb), unlit = dark.
func _led(ci: CanvasItem, r: Rect2, lit: bool, col: Color) -> void:
	if not lit:
		ci.draw_rect(r, LED_OFF)
		return
	ci.draw_rect(r, col)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), col.lightened(0.45))


## The ship's lightning bolt icon, 8 x 13 pixels, top-left corner at `b`.
func _bolt(ci: CanvasItem, b: Vector2, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([b + Vector2(5, 0), b + Vector2(1, 7), b + Vector2(4, 7),
		b + Vector2(2, 13), b + Vector2(8, 5), b + Vector2(5, 5), b + Vector2(7, 0)]), col)


func _draw_timer() -> void:
	var size := timer_bar.size
	var font := timer_bar.get_theme_default_font()
	timer_bar.draw_style_box(_plate, Rect2(Vector2.ZERO, size))
	if _paused:
		# pause icon: two bars
		timer_bar.draw_rect(Rect2(Vector2(7, 5), Vector2(3, 12)), Color(0.5, 0.9, 1.0))
		timer_bar.draw_rect(Rect2(Vector2(12, 5), Vector2(3, 12)), Color(0.5, 0.9, 1.0))
	else:
		_bolt(timer_bar, Vector2(7, 4), AMBER)
	# colour: amber -> orange -> blinking red; light blue while paused
	var col := AMBER
	if _paused:
		col = Color(0.45, 0.9, 1.0)
	elif _frac < 0.25:
		col = Color(1.0, 0.25, 0.2) if int(Time.get_ticks_msec() / 120.0) % 2 == 0 else Color(1.0, 0.6, 0.5)
	elif _frac < 0.5:
		col = Color(1.0, 0.55, 0.15)
	if _pulse > 0.0:
		col = col.lerp(Color.WHITE, _pulse)
	# 10 LED segments, one per half second
	var seg_count := 10
	var x0 := 20.0
	var bar_w := size.x - x0 - 38.0
	var gap := 2.0
	var seg_w := floorf((bar_w - gap * (seg_count - 1)) / seg_count)
	var lit := ceili(_frac * seg_count)
	for i in seg_count:
		_led(timer_bar, Rect2(x0 + i * (seg_w + gap), 7, seg_w, size.y - 14), i < lit, col)
	timer_bar.draw_string(font, Vector2(size.x - 33, size.y - 6), "%.1f" % _secs, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)


# ------------------------------------------------------------------ ship power, cells, oxygen

## How many rooms have power, out of how many. Drawn as a segmented bar.
func set_power(on: int, total: int) -> void:
	if on > _power_on:
		_power_flash = 0.8
	_power_on = on
	_power_total = total


## The oxygen gauge (only shown outside the ship). frac: 1 = full, 0 = empty.
func set_o2(visible_now: bool, frac: float) -> void:
	_o2_on = visible_now
	_o2_frac = clampf(frac, 0.0, 1.0)


func set_cells(count: int, total: int, bump := false) -> void:
	_cells = count
	_cells_total = total
	if bump:
		_cell_bump = 1.0


## Bottom-right key reminder: shows [H] when this room has a hint.
func set_hint_available(on: bool) -> void:
	keys_label.text = "[H] hint   [Esc] menu" if on else "[Esc] menu"


## Top left: the ship's POWER meter (one LED per goal) on a metal plate, and
## under it the OXYGEN meter while you're outside.
func _draw_status() -> void:
	var font := status_box.get_theme_default_font()
	var y := 0.0
	if _power_total > 0:
		var flash := _power_flash > 0.0 and int(_t * 10.0) % 2 == 0
		var ink := Color.WHITE if flash else AMBER
		status_box.draw_style_box(_plate, Rect2(0, 0, 88, 22))
		_bolt(status_box, Vector2(7, 4), ink)
		var seg_w := floorf((60.0 - 2.0 * (_power_total - 1)) / _power_total)
		for i in _power_total:
			_led(status_box, Rect2(20 + i * (seg_w + 2.0), 7, seg_w, 8), i < _power_on, ink)
		y = 24.0
	if _o2_on:
		var low := _o2_frac < 0.3
		var col := Color(0.5, 0.85, 1.0)
		if low:
			col = Color(1.0, 0.3, 0.25) if int(_t * 6.0) % 2 == 0 else Color(1.0, 0.7, 0.6)
		status_box.draw_style_box(_plate, Rect2(0, y, 88, 22))
		status_box.draw_string(font, Vector2(6, y + 15), "O2", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
		var bar := Rect2(24, y + 7, 58, 8)
		status_box.draw_rect(bar, LED_OFF)
		var fill := Rect2(bar.position, Vector2(roundf(bar.size.x * _o2_frac), bar.size.y))
		status_box.draw_rect(fill, col)
		status_box.draw_rect(Rect2(fill.position, Vector2(fill.size.x, 1)), col.lightened(0.45))


## Top right: how many power cells you've charged, on a metal plate.
func _draw_cells() -> void:
	if _cells_total <= 0:
		return
	var font := cells_box.get_theme_default_font()
	var s := cells_box.size
	cells_box.draw_style_box(_plate, Rect2(0, 0, s.x, 22))
	var o := Vector2(6, 3 - roundf(_cell_bump * 3.0))
	var body := AMBER.lerp(Color.WHITE, _cell_bump)
	PowerCell.draw_battery(cells_box, o, body, Color(0.4, 0.25, 0.02))   # same picture as in the level
	var txt := "%d/%d" % [_cells, _cells_total]
	var ink := PHOSPHOR if _cells < _cells_total else AMBER
	cells_box.draw_string(font, Vector2(20, 16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)


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
	set_objective("", Vector2.ZERO, false)
	_queue.clear()                    # PIP stops talking: the results get the screen
	_skip_line = true
	_cut_speech = true
	_speech_point = Vector2.INF
	dialogue.visible = false
	$Complete/VBox/Title.text = "LEVEL %d COMPLETE" % number
	$Complete/VBox/Sub.text = message
	var secs := int(stats.get("time", 0.0))
	$Complete/VBox/Stats.text = "TIME %d:%02d  |  CELLS %d/%d  |  RETRIES %d" % [
		secs / 60, secs % 60, stats.get("cells", 0), stats.get("cells_total", 0), stats.get("retries", 0)]
	# what the cells are FOR: every one makes your suit's air last longer
	var bonus := int(stats.get("cells", 0)) * int(Game.O2_PER_CELL)
	$Complete/VBox/Bonus.visible = bonus > 0
	$Complete/VBox/Bonus.text = "Suit upgrade: +%d s of oxygen" % bonus
	$Complete/VBox/StarHelp.text = "Stars: finish - all cells - %d retries or fewer" % stats.get("retry_goal", 0)
	$Complete/VBox/Again.text = ("[E] next level" if has_next else "[E] back to title") + "    [R] play again"
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
	for i in _stars_earned:
		_stars_shown += 1
		_sfx["star"].pitch_scale = 1.0 + i * 0.12
		_sfx["star"].play()
		await get_tree().create_timer(0.35).timeout


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
			stars_box.draw_colored_polygon(pts, AMBER)
			stars_box.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.45, 0.25, 0.0), 1.0)
		else:
			stars_box.draw_colored_polygon(pts, Color(0.06, 0.12, 0.08))                 # an unlit star on the screen
			stars_box.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.25, 0.42, 0.28), 1.0)
