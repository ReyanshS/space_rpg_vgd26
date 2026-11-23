# ---------------------------------------------------------------------------
# title.gd: the title screen. The name of the game, the story in one line,
# the controls, and the buttons to start.
#
# The background is the same Starfield the spacewalk uses (on a CanvasLayer
# behind everything). With no camera in this scene, the stars drift on their own.
# START fades to black and plays the intro cutscene (Scenes/intro.tscn), which
# then asks Game (the autoload) to load Level 1.
# If there's a save file (you finished a level before), the first button says
# CONTINUE instead and goes to the next level, with your skills. NEW GAME
# appears next to it and starts over (it deletes the save).
# Click a button, or pick one with the arrow keys and press E, Space or Enter.
# Top left: DYSLEXIA FONT on/off (Game.set_dyslexic_font), and JUDGE MODE
# (see _make_judge_buttons) for the TSA judges.
# Edit the texts in title.tscn: select a Label or Button and change its Text.
# ---------------------------------------------------------------------------
extends Node2D

@onready var play_button: Button = $UI/Buttons/Play
@onready var new_game_button: Button = $UI/Buttons/NewGame
@onready var fade: ColorRect = $UI/Fade
@onready var astronaut: AnimatedSprite2D = $Astronaut

var _t := 0.0
var _starting := false
var _music: AudioStreamPlayer
var _grab: AudioStreamPlayer


func _ready() -> void:
	var saved := Game.load_game() and Game.has_save()   # results and skills come back
	if saved:
		play_button.text = "CONTINUE: LEVEL %d" % Game.continue_level()
	else:
		Game.new_game()              # a fresh run: forget old results
	new_game_button.visible = saved
	# A new game starts with the intro cutscene; CONTINUE goes straight to the level.
	play_button.pressed.connect(func() -> void:
		if Game.has_save():
			_start(Game.continue_level())
		else:
			_start(1, true))
	new_game_button.pressed.connect(func() -> void:
		Game.new_game()
		_start(1, true))
	fade.color.a = 1.0
	create_tween().tween_property(fade, "color:a", 0.0, 0.8)
	_music = AudioStreamPlayer.new()             # the title theme (see Game.MUSIC)
	_music.stream = Game.load_music("title")
	_music.volume_db = Game.MUSIC["title"]
	add_child(_music)
	_music.play()
	_grab = _make_player("res://Assets/audio/grab.wav", -4.0)
	_make_judge_buttons()
	# select the first button after a moment, so a key still held from the last
	# screen doesn't press it straight away
	await get_tree().create_timer(0.5).timeout
	if is_inside_tree() and not _starting:
		play_button.grab_focus()


## Judge mode, for the TSA judges: a switch in the top left corner. When it's
## on, a button for each level appears under it (jump straight to Level 3), and
## in a level R makes PIP walk the room for you (autopilot.gd). Made in code so
## they always match the levels in Game.LEVELS.
func _make_judge_buttons() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(6, 16)
	box.add_theme_constant_override("separation", 3)
	$UI.add_child(box)
	# the font switch first (see Game.DYSLEXIC_FONT): everyone sees it
	var font_switch := Button.new()
	font_switch.add_theme_font_size_override("font_size", UIStyle.SMALL + 1)
	font_switch.text = Game.font_switch_text()
	font_switch.pressed.connect(func() -> void:
		Game.set_dyslexic_font(not Game.dyslexic_font)
		font_switch.text = Game.font_switch_text())
	box.add_child(font_switch)
	var toggle := Button.new()
	toggle.add_theme_font_size_override("font_size", UIStyle.SMALL + 1)
	box.add_child(toggle)
	var levels: Array[Button] = []
	for n in Game.LEVELS.size():
		var b := Button.new()
		b.add_theme_font_size_override("font_size", UIStyle.SMALL + 1)
		b.text = "LEVEL %d" % (n + 1)
		b.pressed.connect(_start.bind(n + 1))
		box.add_child(b)
		levels.append(b)
	var refresh := func() -> void:
		toggle.text = "JUDGE MODE: " + ("ON" if Game.judge_mode else "OFF")
		for b in levels:
			b.visible = Game.judge_mode
	toggle.pressed.connect(func() -> void:
		Game.judge_mode = not Game.judge_mode
		refresh.call())
	refresh.call()


func _make_player(path: String, volume: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		p.stream = load(path)
	p.volume_db = volume
	add_child(p)
	return p


func _process(delta: float) -> void:
	_t += delta
	# the astronaut floats gently, as if in zero-G
	astronaut.position = Vector2(104, 150) + Vector2(sin(_t * 0.7) * 6.0, sin(_t * 1.1) * 8.0)
	astronaut.rotation = sin(_t * 0.5) * 0.25


## intro = play the opening cutscene first (it loads Level 1 when it's done).
func _start(level: int, intro := false) -> void:
	if _starting:
		return                       # (a second click while it fades)
	_starting = true
	play_button.disabled = true
	new_game_button.disabled = true
	_grab.play()
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.7)
	tw.parallel().tween_property(_music, "volume_db", -60.0, 0.7)
	await tw.finished
	if not is_inside_tree(): return
	if intro:
		Game.go_to_intro()
	else:
		Game.go_to_level(level)
