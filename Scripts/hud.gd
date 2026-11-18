# ---------------------------------------------------------------------------
# hud.gd  -  everything drawn on top of the game.
#
# THE CONSOLE: a metal dashboard along the bottom of the screen (like the status
# bar in old console games). The game is shown ABOVE it (level.gd moves the
# camera up by CONSOLE_H/2), so nothing in the console ever covers the room.
#   left:   PIP's little CRT face and his SPEECH. When he's quiet, the current
#           tutorial instruction (the "objective") is shown there instead.
#   right:  the ship POWER meter (one LED per goal), the POWER CELL counter, and
#           the OXYGEN meter on spacewalks (or key reminders inside the ship).
# Also: the wire TIMER (a small LED bar floating above the astronaut's head, so
# you don't have to look away), the tutorial ARROW, short "toast" messages at
# the top (room names, ZAP...), the white flash / black fade, the RESULTS screen
# with stars, the PAUSE menu, the SKILL TREE screen (skill_tree.gd: T on the
# pause menu or the results screen), and the black film bar of the cutscenes.
#
# It's a CanvasLayer, which means it stays still on screen while the camera
# moves. Its nodes live in hud.tscn - open that scene to change colours and
# sizes without code. All text uses the project theme (Assets/ui/theme.tres ->
# the m6x11 pixel font at size 16).
#
# PAUSING: hud.tscn sets this node's Process Mode to "Always", so the HUD keeps
# running when the game is paused (get_tree().paused = true) - that's how the
# pause menu can still react to keys while everything else is frozen.
# ---------------------------------------------------------------------------
class_name GameHUD
extends CanvasLayer

## Emitted when a speech that freezes the player starts (true) / ends (false).
signal dialogue_blocking(on: bool)

## Height of the console at the bottom. level.gd keeps the room above it.
const CONSOLE_H := 48
const TYPE_SPEED := 48.0          # letters per second in the speech box
# The look: SHIP HARDWARE outside (riveted metal frames, Assets/ui/frame_*.png,
# drawn by tools/art_ui.py) and an old GREEN COMPUTER SCREEN inside.
const NAME_COLOR := "#ffc24d"     # amber: names, keys, headings
const TEXT_COLOR := "#a8f0a0"     # phosphor green: what PIP says
const DIM_COLOR := "#6f9c74"      # dim green: the standing objective
const KEY_COLOR := "#ffc24d"
const AMBER := Color(1.0, 0.76, 0.3)
const PHOSPHOR := Color(0.66, 0.94, 0.63)
# Level 3: when PIP malfunctions he talks as "P!P" in red, with an angry face.
const ROGUE_SPEAKER := "P!P"
const ROGUE_NAME_COLOR := "#ff5a4a"
const ROGUE_TEXT_COLOR := "#ffb09c"
const ROGUE_RED := Color(1.0, 0.33, 0.27)
const LED_OFF := Color(0.12, 0.15, 0.14)  # a segment of a meter that isn't lit

@onready var toast: PanelContainer = $Toast
@onready var toast_label: Label = $Toast/Text
@onready var timer_bar: Control = $TimerBar
@onready var flash_rect: ColorRect = $Flash
@onready var fade_rect: ColorRect = $Fade
@onready var complete_panel: Control = $Complete
@onready var marker: Control = $Marker
@onready var status_box: Control = $Status
@onready var keys_label: Label = $Keys
@onready var dialogue: PanelContainer = $Dialogue
@onready var portrait: Control = $Dialogue/Row/Portrait
@onready var dialogue_text: RichTextLabel = $Dialogue/Row/Text
@onready var stars_box: Control = $Complete/VBox/Stars
@onready var pause_panel: Control = $Pause
@onready var pause_level: Label = $Pause/VBox/Level
@onready var bar_top: ColorRect = $BarTop
@onready var skill_tree: SkillTreeScreen = $SkillTree
## The E key that bobs just under PIP's little screen when you have to press E
## to go on (never on top of the text). It's its own node in hud.tscn: move it
## there to put it somewhere else.
@onready var next_key: Control = $NextKey

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
var _objective := ""                # the tutorial instruction, shown when PIP is quiet
var _cinematic := false             # a cutscene is playing (film bar on)
var _reel_prompt := false           # show the [E] "reel back" key above the astronaut
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
var _points_earned := 0             # skill points this level gave (0 on a replay)

# the skill tree screen
var _tree_from_pause := false       # opened from the pause menu (go back to it on close)

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
	timer_bar.visible = false
	complete_panel.visible = false
	toast.visible = false
	pause_panel.visible = false
	flash_rect.color.a = 0.0
	fade_rect.color.a = 0.0
	bar_top.visible = false
	bar_top.position.y = -bar_top.size.y        # the film bar waits just above the screen
	skill_tree.closed.connect(_on_skill_tree_closed)
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
	_pulse = maxf(0.0, _pulse - delta * 2.5)
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
	# (not while the skill tree is open, or on the frame its Esc closed it)
	var tree_busy := skill_tree.visible or skill_tree.closed_frame == Engine.get_process_frames()
	if Input.is_action_just_pressed("pause") and allow_pause and not tree_busy:
		_set_paused(not get_tree().paused)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).physical_keycode
	# on the pause menu: Q = back to the title screen, T = skill tree
	if pause_panel.visible:
		if key == KEY_Q:
			_set_paused(false)
			Game.go_to_title()
		elif key == KEY_T:
			open_skill_tree()
	# on the results screen: T = skill tree (spend the points you just got)
	elif complete_panel.visible and key == KEY_T:
		open_skill_tree()


func _set_paused(on: bool) -> void:
	get_tree().paused = on
	pause_panel.visible = on
	if on:
		_update_pause_skills()


## The line on the pause menu about your skills.
func _update_pause_skills() -> void:
	var pts := SkillManager.points
	var text := "SKILLS %d/%d" % [SkillManager.unlocked_count(), SkillManager.all_skills().size()]
	if pts > 0:
		text += "   |   %d POINT%s TO SPEND" % [pts, "" if pts == 1 else "S"]
	$Pause/VBox/Suit.text = text


# ------------------------------------------------------------------ skill tree

## Opens the skill tree screen and pauses the game until it closes.
func open_skill_tree() -> void:
	if skill_tree.visible:
		return
	_tree_from_pause = pause_panel.visible
	pause_panel.visible = false
	get_tree().paused = true
	skill_tree.open()


func is_skill_tree_open() -> bool:
	return skill_tree.visible


func _on_skill_tree_closed() -> void:
	if _tree_from_pause:
		pause_panel.visible = true        # back to the pause menu, still paused
		_update_pause_skills()
	else:
		get_tree().paused = false         # back to the results screen
		_update_points_line()


## The pause menu shows which level you're on.
func set_level_info(text: String) -> void:
	pause_level.text = text


## Where the player is on the SCREEN (the HUD doesn't move with the camera).
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
	dialogue_text.text = ("[color=%s]> %s[/color]" % [DIM_COLOR, _objective]) if _objective != "" else ""


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
	if _restart_prompt and not _cinematic:
		_draw_key(_player_on_screen() + Vector2(0, -48 + roundf(sin(_t * 5.0))), "R")


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
		marker.draw_polyline(tri + PackedVector2Array([tip]), dark, 1.0)
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
	var bob := roundf(absf(sin(_t * 4.0)) * -2.0)
	_draw_key(Vector2(6, 6 + bob), "E", next_key)


## A little keyboard key with a letter on it (13 x 13 px, centre at `at`),
## drawn on `ci` (the arrow layer unless you say otherwise).
func _draw_key(at: Vector2, letter: String, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = marker
	var o := (at - Vector2(6, 6)).round()
	ci.draw_rect(Rect2(o + Vector2(0, 1), Vector2(13, 13)), Color(0.05, 0.05, 0.1, 0.9))
	ci.draw_rect(Rect2(o, Vector2(13, 13)), Color(0.95, 0.95, 1.0))
	ci.draw_rect(Rect2(o + Vector2(1, 1), Vector2(11, 10)), Color(0.82, 0.84, 0.92))
	var font := marker.get_theme_default_font()
	ci.draw_string(font, o + Vector2(3, 11), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.12, 0.12, 0.2))


## While he holds the wire and stands still away from the last pad: show the
## [E] key ("you can reel back"), and say so in the console's key reminders.
func set_reel_prompt(on: bool) -> void:
	if on == _reel_prompt:
		return
	_reel_prompt = on
	_update_keys()


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


## The console has room for TWO rows of text, and every line should fit in them,
## so the whole line is on screen at once. (The E key sits under PIP's screen,
## not in the text, so it never adds a row.) If a line is still too long,
## it's split into "pages" here so nothing runs off the screen - but split lines
## get missed, so the editor marks those lines in red: shorten them.
func _pages(speaker: String, line: String) -> PackedStringArray:
	var font := dialogue_text.get_theme_font("normal_font")
	var fsize := dialogue_text.get_theme_font_size("normal_font_size")
	var width := maxf(dialogue_text.size.x, dialogue_text.custom_minimum_size.x) - 2.0
	var prefix := speaker + "> "
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
	_line_bbcode = "[color=%s]%s>[/color] [color=%s]%s[/color]" % [name_col, speaker, text_col, line]
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
## When he's quiet the screen is dimmer.
## Malfunctioning (Level 3): a red screen, slanted angry eyes, and now and then
## a "glitch" that shifts the face sideways and draws a bright bar across it.
func _draw_portrait() -> void:
	var s := portrait.size
	var angry := _line_rogue if _talking else _rogue
	var base := ROGUE_RED if angry else PHOSPHOR
	var ink := base if _talking else base.darkened(0.45)
	portrait.draw_rect(Rect2(Vector2.ZERO, s), Color(0.29, 0.32, 0.38))                  # metal case
	portrait.draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, 1)), Color(0.54, 0.58, 0.65))    # its top edge catches the light
	var glass := Color(0.1, 0.03, 0.03) if angry else Color(0.03, 0.09, 0.05)
	portrait.draw_rect(Rect2(Vector2(2, 2), s - Vector2(4, 4)), glass)                    # the glass
	var glitch := angry and fmod(_t * 7.0, 5.0) < 0.6       # a short burst every so often
	var o := Vector2(signf(sin(_t * 40.0)) if glitch else 0.0, 0.0)
	var blink := fmod(_t, 3.2) < 0.12 and not angry
	for x in [8.0, 16.0]:
		if blink:
			portrait.draw_rect(Rect2(o + Vector2(x, 12), Vector2(4, 1)), ink)
		elif angry:
			# slanted eyes: each one a short staircase, high at the outside edge
			var inner := 3.0 if x < 12.0 else 0.0
			for k in 4:
				var drop := absf(k - inner)       # lower towards the nose = a frown
				portrait.draw_rect(Rect2(o + Vector2(x + k, 9 + drop * 0.5), Vector2(1, 4)), ink)
		else:
			portrait.draw_rect(Rect2(o + Vector2(x, 9), Vector2(4, 5)), ink)
			portrait.draw_rect(Rect2(o + Vector2(x + 2, 10), Vector2(1, 2)), ink.lightened(0.6))
	var mouth := 1.0
	if _typing:
		mouth = 1.0 + float(int(_t * 14.0) % 3)
	portrait.draw_rect(Rect2(o + Vector2(10, 18), Vector2(8, mouth)), ink)
	if glitch:
		var y := 4.0 + float(int(_t * 23.0) % int(s.y - 8.0))
		portrait.draw_rect(Rect2(2, y, s.x - 4, 1), ink.lightened(0.5))
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


# ------------------------------------------------------------------ the wire timer (above his head)

func set_timer(on: bool, frac: float, secs: float, paused := false) -> void:
	timer_bar.visible = on and not _cinematic
	_frac = frac
	_secs = secs
	_paused = paused


## Flash the timer when a node or a power cell refills it.
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


## Five LEDs (one per second) in a tiny dark case floating above the astronaut.
## Amber, then orange, then blinking red when time is short; blue while paused.
func _draw_timer() -> void:
	var size := timer_bar.size
	timer_bar.draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.85))
	timer_bar.draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.48, 0.56), false, 1.0)
	var col := AMBER
	if _paused:
		col = Color(0.45, 0.9, 1.0)
	elif _frac < 0.25:
		col = Color(1.0, 0.25, 0.2) if int(_t * 8.0) % 2 == 0 else Color(1.0, 0.6, 0.5)
	elif _frac < 0.5:
		col = Color(1.0, 0.55, 0.15)
	if _pulse > 0.0:
		col = col.lerp(Color.WHITE, _pulse)
	var lit := ceili(_frac * 5.0 - 0.001)
	for i in 5:
		_led(timer_bar, Rect2(2 + i * 7, 2, 6, size.y - 4), i < lit, col)


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
	if _waiting_key:
		keys_label.text = "[E] next"
	elif _restart_prompt:
		keys_label.text = "[R] back to start"
	elif _reel_prompt:
		keys_label.text = "[E] reel back"
	elif _hint_on:
		keys_label.text = "[H] hint  [Esc] menu"
	else:
		keys_label.text = "[R] restart  [Esc] menu"
	keys_label.visible = not _o2_on or _reel_prompt or _restart_prompt or _waiting_key


## The right side of the console: SHIP POWER LEDs and the cell counter on top,
## the OXYGEN meter underneath while you're outside.
func _draw_status() -> void:
	var font := status_box.get_theme_default_font()
	if _power_total > 0:
		var flash := _power_flash > 0.0 and int(_t * 10.0) % 2 == 0
		var ink := Color.WHITE if flash else AMBER
		_bolt(status_box, Vector2(4, 2), ink)
		var seg_w := floorf((52.0 - 2.0 * (_power_total - 1)) / _power_total)
		for i in _power_total:
			_led(status_box, Rect2(16 + i * (seg_w + 2.0), 5, seg_w, 8), i < _power_on, ink)
	if _cells_total > 0:
		var o := Vector2(74, 1 - roundf(_cell_bump * 3.0))
		PowerCell.draw_battery(status_box, o, AMBER.lerp(Color.WHITE, _cell_bump), Color(0.4, 0.25, 0.02))
		var ink2 := PHOSPHOR if _cells < _cells_total else AMBER
		status_box.draw_string(font, Vector2(88, 14), "%d/%d" % [_cells, _cells_total], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink2)
	# skill points waiting to be spent (amber when you have some)
	var pts := SkillManager.points
	status_box.draw_string(font, Vector2(126, 13), "SP%d" % pts, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
		AMBER if pts > 0 else Color(0.42, 0.62, 0.45))
	if _o2_on and not _reel_prompt and not _restart_prompt and not _waiting_key:
		var col := Color(0.5, 0.85, 1.0)
		if _o2_frac < 0.3:
			col = Color(1.0, 0.3, 0.25) if int(_t * 6.0) % 2 == 0 else Color(1.0, 0.7, 0.6)
		status_box.draw_string(font, Vector2(2, 37), "O2", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
		var bar := Rect2(22, 27, 136, 8)
		status_box.draw_rect(bar, LED_OFF)
		var fill := Rect2(bar.position, Vector2(roundf(bar.size.x * _o2_frac), bar.size.y))
		status_box.draw_rect(fill, col)
		status_box.draw_rect(Rect2(fill.position, Vector2(fill.size.x, 1)), col.lightened(0.45))


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
	$Complete/VBox/Stats.text = "TIME %d:%02d  |  CELLS %d/%d  |  RETRIES %d" % [
		secs / 60, secs % 60, stats.get("cells", 0), stats.get("cells_total", 0), stats.get("retries", 0)]
	# cells you keep also make your suit's air last longer on spacewalks
	var bonus := int(stats.get("cells", 0)) * int(Game.o2_per_cell())
	$Complete/VBox/Bonus.visible = bonus > 0 and has_next     # no spacewalks after the last level
	$Complete/VBox/Bonus.text = "Kept batteries: +%d s of oxygen" % bonus
	_points_earned = int(stats.get("points", 0))
	_update_points_line()
	$Complete/VBox/StarHelp.text = "Stars for finishing, every cell, and %d retries or fewer" % stats.get("retry_goal", 0)
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


## The results line about skill points, e.g. "+2 SKILL POINTS   [T] skill tree".
func _update_points_line() -> void:
	var label: Label = $Complete/VBox/Points
	var pts := SkillManager.points
	if _points_earned > 0:
		label.text = "+%d SKILL POINT%s   [T] skill tree" % [_points_earned, "" if _points_earned == 1 else "S"]
	elif pts > 0:
		label.text = "%d skill point%s to spend   [T] skill tree" % [pts, "" if pts == 1 else "s"]
	else:
		label.text = "[T] skill tree"


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
